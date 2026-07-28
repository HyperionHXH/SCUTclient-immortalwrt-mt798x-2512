#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_SOURCE_COMMIT="${REPO_COMMIT:-1cfeb3edade40fe2dfec59c21381de1d8e361100}"
DTS="$OPENWRT_DIR/target/linux/mediatek/dts/mt7981b-honor-fur-602.dts"
IMAGE_MK="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
NETWORK_FILE="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
UPGRADE_FILE="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
DOWNLOAD_SCRIPT="$OPENWRT_DIR/scripts/download.pl"
PROJECT_MIRRORS="$OPENWRT_DIR/scripts/projectsmirrors.json"
LOCAL_MIRRORS="$OPENWRT_DIR/scripts/localmirrors"
HAPROXY_DEFAULTS="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults/99-disable-unused-haproxy"
DOWNLOAD_PATCH="$WRAPPER_DIR/patches/2512/build-system/download-reliability.patch"

fail() {
  echo "FUR602 适配校验失败：$*" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "缺少文件 $1"
}

device_block_has() {
  local expected="$1"

  awk -v expected="$expected" '
    $0 == "define Device/honor_fur-602" { in_device = 1; count++ }
    in_device && index($0, expected) { found = 1 }
    in_device && $0 == "endef" { in_device = 0 }
    END { exit !(count == 1 && found) }
  ' "$IMAGE_MK"
}

dts_node_has() {
  local node="$1"
  local expected="$2"

  awk -v node="$node" -v expected="$expected" '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
    }
    (line == node " {" || index(line, ": " node " {") > 0) { in_node = 1; count++ }
    in_node && index($0, expected) { found = 1 }
    in_node && line == "};" { in_node = 0 }
    END { exit !(count == 1 && found) }
  ' "$DTS"
}

for script in "$WRAPPER_DIR"/*.sh "$WRAPPER_DIR"/scripts/*.sh "$WRAPPER_DIR"/patches/2512/*.sh; do
  [ -f "$script" ] || continue
  bash -n "$script" || fail "脚本语法错误：$script"
done

actual_commit="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
[ "$actual_commit" = "$EXPECTED_SOURCE_COMMIT" ] || \
  fail "源码提交为 $actual_commit，尚未审查；预期 $EXPECTED_SOURCE_COMMIT"

require_file "$DTS"
require_file "$IMAGE_MK"
require_file "$NETWORK_FILE"
require_file "$UPGRADE_FILE"
require_file "$DOWNLOAD_SCRIPT"
require_file "$PROJECT_MIRRORS"
require_file "$LOCAL_MIRRORS"
require_file "$HAPROXY_DEFAULTS"
require_file "$DOWNLOAD_PATCH"

grep -Fq '/etc/init.d/haproxy disable' "$HAPROXY_DEFAULTS" || \
  fail "未默认禁用 HAProxy 示例服务"
grep -Fq '/etc/init.d/haproxy stop' "$HAPROXY_DEFAULTS" || \
  fail "未停止 HAProxy 示例服务"

grep -Fq -- '--speed-limit 1024 --speed-time 30 --max-time 300' "$DOWNLOAD_SCRIPT" || \
  fail "download.pl 缺少低速连接和单次下载时限"
grep -Fq -- '--retry 2 --retry-delay 2 --retry-max-time 180' "$DOWNLOAD_SCRIPT" || \
  fail "download.pl 的重试次数仍可能长时间占用 Action"
[ "$(sed -n '1p' "$LOCAL_MIRRORS" | tr -d '\r')" = 'https://sources.cdn.openwrt.org' ] || \
  fail "OpenWrt CDN 不是首选下载源"

kernel_cdn_line="$(grep -nF '"https://cdn.kernel.org/pub"' "$PROJECT_MIRRORS" | cut -d: -f1 || true)"
kernel_iscas_line="$(grep -nF '"https://mirror.iscas.ac.cn/kernel.org"' "$PROJECT_MIRRORS" | cut -d: -f1 || true)"
[ -n "$kernel_cdn_line" ] && [ -n "$kernel_iscas_line" ] && \
  [ "$kernel_cdn_line" -lt "$kernel_iscas_line" ] || \
  fail "KERNEL 下载仍然优先访问 ISCAS，而不是 cdn.kernel.org"

grep -Fq '#include <dt-bindings/pinctrl/mt65xx.h>' "$DTS" || \
  fail "DTS 缺少 MTK pinctrl 常量头文件"
grep -Fq 'compatible = "honor,fur-602", "mediatek,mt7981";' "$DTS" || \
  fail "DTS compatible 错误"
grep -Fq 'compatible = "mediatek,mt7531";' "$DTS" || fail "未使用 MT7531 DSA"
grep -Fq 'mediatek,nmbm;' "$DTS" || fail "SPI NAND 未启用 NMBM"
grep -Fq 'mediatek,bmt-max-ratio = <1>;' "$DTS" || fail "NMBM 坏块比例错误"
grep -Fq 'mediatek,bmt-max-reserved-blocks = <64>;' "$DTS" || \
  fail "NMBM 保留块数量错误"
grep -Fq 'reg = <0x580000 0x7200000>;' "$DTS" || fail "UBI 分区布局错误"
grep -Fq 'eeprom_factory_0: eeprom@0' "$DTS" || fail "缺少无线 EEPROM 单元"
grep -Fq 'nvmem-cells = <&eeprom_factory_0>;' "$DTS" || fail "Wi-Fi 未引用 Factory EEPROM"

dts_node_has 'port@0' 'label = "wan";' || fail "交换机端口 0 不是 WAN"
dts_node_has 'port@1' 'label = "lan3";' || fail "交换机端口 1 不是 LAN3"
dts_node_has 'port@2' 'label = "lan2";' || fail "交换机端口 2 不是 LAN2"
dts_node_has 'port@3' 'label = "lan1";' || fail "交换机端口 3 不是 LAN1"
dts_node_has 'port@6' 'ethernet = <&gmac0>;' || fail "交换机 CPU 口未连接 GMAC0"

for expected in \
  'DEVICE_DTS := mt7981b-honor-fur-602' \
  'SUPPORTED_DEVICES += honor,fur-602' \
  'IMAGE_SIZE := 116736k' \
  'KERNEL_IN_UBI := 1' \
  'IMAGES += factory.bin' \
  'IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)' \
  'IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata'; do
  device_block_has "$expected" || fail "设备 profile 缺少：$expected"
done

awk '
  index($0, "honor,fur-602") { in_case = 1; found_board++ }
  in_case && index($0, "ucidef_set_interfaces_lan_wan \"lan1 lan2 lan3\" wan") { found_network = 1 }
  in_case && /^[[:space:]]*;;[[:space:]]*$/ { in_case = 0 }
  END { exit !(found_board == 1 && found_network) }
' "$NETWORK_FILE" || fail "LAN/WAN 网络配置错误"

grep -Fq $'\t*)' "$UPGRADE_FILE" || fail "升级脚本缺少默认设备分支"
grep -Fq $'\t\tnand_do_upgrade "$1"' "$UPGRADE_FILE" || fail "升级脚本不再默认执行 NAND 升级"
grep -Fq 'nand_do_platform_check "$board" "$1"' "$UPGRADE_FILE" || \
  fail "升级脚本不再默认校验 NAND sysupgrade"

echo "FUR602 25.12 适配校验通过。"
