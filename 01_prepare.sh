#!/bin/bash
set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$(pwd)}"

cd "$OPENWRT_DIR"

./scripts/feeds update -a

rm -rf package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon

rm -rf feeds/luci/applications/luci-app-scutclient
git clone --depth=1 https://github.com/hanwckf/luci-app-scutclient.git feeds/luci/applications/luci-app-scutclient

scut_controller="feeds/luci/applications/luci-app-scutclient/luasrc/controller/scutclient.lua"
if [ -f "$scut_controller" ] && grep -q 'require "nixio.fs"' "$scut_controller"; then
  python3 "$SCRIPT_DIR/scripts/patch_scutclient.py" "$scut_controller"
fi

rm -rf package/scut-unicom
mkdir -p package/scut-unicom
wget --tries=5 --timeout=30 \
  https://raw.githubusercontent.com/wykdg/route_script/master/scut-unicom/Makefile \
  -O package/scut-unicom/Makefile

rm -rf package/luci-app-tailscale
git clone --depth=1 https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale

./scripts/feeds install -a

if [ -f package/base-files/files/etc/rc.local ] && \
   ! grep -q 'scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local; then
  sed -i '/^exit 0/i # If using Unicom accelerator, uncomment and fill in the following values\n#sleep 10 && /usr/share/scut_unicom/add_route.sh server_ip username password' \
    package/base-files/files/etc/rc.local
fi

ttyd_config="feeds/packages/utils/ttyd/files/ttyd.config"
if [ -f "$ttyd_config" ]; then
  sed -i "s#option command '/bin/login'#option command '/bin/login -f root'#" "$ttyd_config"
fi

default_settings="package/emortal/default-settings/files/99-default-settings"
if [ -f "$default_settings" ] && ! grep -q 'trojan-go' "$default_settings"; then
  sed -i "s#exit 0#[ ! -f '/usr/sbin/trojan' ] \\&\\& [ -f '/usr/bin/trojan-go' ] \\&\\& ln -sf /usr/bin/trojan-go /usr/bin/trojan\\nexit 0#" "$default_settings"
fi
