#!/bin/bash
set -e -o pipefail

profile="${1:-}"
image_makefile="${2:-target/linux/mediatek/image/filogic.mk}"

if [ -z "$profile" ]; then
  echo "Usage: $0 <device-profile> [filogic.mk]" >&2
  exit 1
fi

if [ ! -f "$image_makefile" ]; then
  echo "Missing image makefile: $image_makefile" >&2
  exit 1
fi

if ! grep -Fqx "define Device/${profile}" "$image_makefile"; then
  echo "Unknown mediatek/filogic device profile: $profile" >&2
  echo "Run this in the openwrt tree to list profiles:" >&2
  echo "  grep -E '^define Device/' target/linux/mediatek/image/filogic.mk | sed 's/^define Device\\///'" >&2
  exit 1
fi

echo "Validated profile: $profile"
