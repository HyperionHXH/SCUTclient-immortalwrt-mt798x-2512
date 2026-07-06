#!/bin/bash
set -e -o pipefail

profiles_input="${1:-}"
config_file="${2:-.config}"

if [ -z "$profiles_input" ]; then
  echo "用法：$0 <device-profile...> [config-file]" >&2
  exit 1
fi

read_profiles() {
  printf '%s\n' "$profiles_input" | tr ',' ' ' | xargs -n1
}

mapfile -t profiles < <(read_profiles)
if [ "${#profiles[@]}" -eq 0 ]; then
  echo "没有可验证的设备 profile" >&2
  exit 1
fi

multi_profile=n
if [ "${#profiles[@]}" -gt 1 ]; then
  multi_profile=y
fi

for profile in "${profiles[@]}"; do
  if [ "$multi_profile" = "y" ]; then
    expected="CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${profile}=y"
  else
    expected="CONFIG_TARGET_mediatek_filogic_DEVICE_${profile}=y"
  fi

  if ! grep -Fqx "$expected" "$config_file"; then
    echo "make defconfig 后目标 profile 没有被启用：$profile" >&2
    echo "期望配置行：$expected" >&2
    selected="$(grep -E '^(CONFIG_TARGET_mediatek_filogic_DEVICE_|CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_).+=y$' "$config_file" || true)"
    if [ -n "$selected" ]; then
      echo "当前选中的 profile 行：" >&2
      echo "$selected" >&2
    fi
    exit 1
  fi
done

echo "已验证选中的 ${#profiles[@]} 个目标 profile：${profiles[*]}"
