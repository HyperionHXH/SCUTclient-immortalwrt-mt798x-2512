#!/bin/bash
set -e -o pipefail

profile="${1:-}"
config_file="${2:-.config}"

if [ -z "$profile" ]; then
  echo "Usage: $0 <device-profile> [config-file]" >&2
  exit 1
fi

cat > "$config_file" <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_MULTI_PROFILE=n
CONFIG_TARGET_mediatek_filogic_DEVICE_${profile}=y
CONFIG_TARGET_SQUASHFS_XZ=y
CONFIG_PACKAGE_luci=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_IMAGEOPT=y
CONFIG_VERSIONOPT=y
CONFIG_VERSION_DIST="ImmortalWrt"
CONFIG_VERSION_NUMBER="25.12"
CONFIG_VERSION_REPO="https://downloads.immortalwrt.org/releases/25.12.0"
CONFIG_VERSION_HOME_URL="https://immortalwrt.org/"
CONFIG_VERSION_SUPPORT_URL="https://github.com/immortalwrt/immortalwrt"
CONFIG_VERSION_BUG_URL="https://github.com/immortalwrt/immortalwrt/issues"
EOF
