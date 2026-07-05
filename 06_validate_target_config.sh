#!/bin/bash
set -e -o pipefail

profile="${1:-}"
config_file="${2:-.config}"

if [ -z "$profile" ]; then
  echo "用法：$0 <device-profile> [config-file]" >&2
  exit 1
fi

expected="CONFIG_TARGET_mediatek_filogic_DEVICE_${profile}=y"

if ! grep -Fqx "$expected" "$config_file"; then
  echo "make defconfig 后目标 profile 没有被启用：$profile" >&2
  echo "期望配置行：$expected" >&2
  selected="$(grep -E '^CONFIG_TARGET_mediatek_filogic_DEVICE_.+=y$' "$config_file" || true)"
  if [ -n "$selected" ]; then
    echo "当前选中的 profile 行：" >&2
    echo "$selected" >&2
  fi
  exit 1
fi

echo "已验证选中的目标 profile：$profile"
