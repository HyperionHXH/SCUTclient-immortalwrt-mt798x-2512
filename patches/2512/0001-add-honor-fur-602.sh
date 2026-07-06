#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$PATCH_DIR/files"

DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/dts"
IMAGE_MK="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
NETWORK_FILE="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "错误：OPENWRT_DIR 看起来不是 ImmortalWrt 源码树：$OPENWRT_DIR" >&2
  exit 1
fi

insert_before_marker() {
  local file="$1"
  local marker="$2"
  local block_file="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    index($0, marker) && !done {
      printf "%s", block
      done = 1
    }
    { print }
    END {
      if (!done) exit 1
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

install -m 0644 "$FILES_DIR/mt7981b-honor-fur-602.dts" "$DTS_DIR/mt7981b-honor-fur-602.dts"

if ! grep -q '^define Device/honor_fur-602$' "$IMAGE_MK"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/honor_fur-602
  DEVICE_VENDOR := HONOR
  DEVICE_MODEL := FUR-602/603
  DEVICE_DTS := mt7981b-honor-fur-602
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += honor,fur-602
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += honor_fur-602

DEVICE
  insert_before_marker "$IMAGE_MK" "define Device/h3c_magic-nx30-pro" "$block"
  rm -f "$block"
fi

if ! grep -q 'honor,fur-602' "$NETWORK_FILE"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	honor,fur-602|\
NETWORK
  insert_before_marker "$NETWORK_FILE" "jcg,q30-pro|\\" "$block"
  rm -f "$block"
fi

echo "HONOR FUR-602/603 25.12 适配已准备好。"
