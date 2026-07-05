#!/bin/bash
set -e -o pipefail

profiles_input="${1:-}"
image_makefile="${2:-target/linux/mediatek/image/filogic.mk}"

if [ -z "$profiles_input" ]; then
  echo "用法：$0 <device-profile...> [filogic.mk]" >&2
  exit 1
fi

if [ ! -f "$image_makefile" ]; then
  echo "缺少镜像 Makefile：$image_makefile" >&2
  exit 1
fi

read_profiles() {
  printf '%s\n' "$profiles_input" | tr ',' ' ' | xargs -n1
}

mapfile -t profiles < <(read_profiles)
for profile in "${profiles[@]}"; do
  if ! grep -Fqx "define Device/${profile}" "$image_makefile"; then
    echo "未知的 mediatek/filogic 设备 profile：$profile" >&2
    echo "可以在 openwrt 源码树中运行下面命令列出 profile：" >&2
    echo "  grep -E '^define Device/' target/linux/mediatek/image/filogic.mk | sed 's/^define Device\\///'" >&2
    exit 1
  fi
done

echo "已验证 ${#profiles[@]} 个 profile：${profiles[*]}"
