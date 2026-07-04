#!/bin/bash
set -e -o pipefail

profile="${1:-}"
config_file="${2:-.config}"

if [ -z "$profile" ]; then
  echo "Usage: $0 <device-profile> [config-file]" >&2
  exit 1
fi

expected="CONFIG_TARGET_mediatek_filogic_DEVICE_${profile}=y"

if ! grep -Fqx "$expected" "$config_file"; then
  echo "Target profile was not enabled after make defconfig: $profile" >&2
  echo "Expected config line: $expected" >&2
  selected="$(grep -E '^CONFIG_TARGET_mediatek_filogic_DEVICE_.+=y$' "$config_file" || true)"
  if [ -n "$selected" ]; then
    echo "Selected profile line(s):" >&2
    echo "$selected" >&2
  fi
  exit 1
fi

echo "Validated selected target profile: $profile"
