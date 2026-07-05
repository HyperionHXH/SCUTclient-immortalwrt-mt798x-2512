#!/bin/bash
set -e -o pipefail

profile="${1:-}"
image_makefile="${2:-target/linux/mediatek/image/filogic.mk}"

if [ -z "$profile" ]; then
  echo "用法：$0 <device-profile> [filogic.mk]" >&2
  exit 1
fi

if [ ! -f "$image_makefile" ]; then
  echo "缺少镜像 Makefile：$image_makefile" >&2
  exit 1
fi

if ! grep -Fqx "define Device/${profile}" "$image_makefile"; then
  echo "未知的 mediatek/filogic 设备 profile：$profile" >&2
  echo "可以在 openwrt 源码树中运行下面命令列出 profile：" >&2
  echo "  grep -E '^define Device/' target/linux/mediatek/image/filogic.mk | sed 's/^define Device\\///'" >&2
  exit 1
fi

echo "已验证 profile：$profile"
