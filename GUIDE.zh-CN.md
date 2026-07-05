# ImmortalWrt MT798x 25.12 Build Guide

## Status

Checked on 2026-07-05 in WSL:

- `cmcc_rax3000m` passed `make defconfig`.
- `06_validate_target_config.sh` confirmed the requested profile stayed selected.
- `03_validate_packages.sh` confirmed all 33 requested packages are enabled.
- Direct `make -j1 V=s` completed successfully for `cmcc_rax3000m`.
- `BUILD_PROFILE=cmcc_rax3000m JOBS=2 DOWNLOAD_JOBS=8 bash build_all.sh` completed successfully and collected artifacts under `/home/miunah/my_project/mt798x_build_2512/artifacts/cmcc_rax3000m`.
- Real-device flashing is still pending.

## Source

- Repository: `immortalwrt/immortalwrt`
- Branch: `openwrt-25.12`
- Target: `mediatek/filogic`

The verified 23.05 firmware used the `padavanonly/immortalwrt-mt798x-6.6` private MTK Wi-Fi route. That repository currently has no `openwrt-25.12` branch, so this 25.12 project uses official ImmortalWrt `mediatek/filogic` profiles instead.

## Packages

Edit `package.conf`, one package name per line. Do not include `CONFIG_PACKAGE_` or `=y`.

25.12 package-name differences from 23.05:

- WireGuard LuCI support is `luci-proto-wireguard`.
- Socat is selected as `socat`.
- Passwall 26.7.1 has no separate `luci-app-passwall_INCLUDE_tuic_client`; TUIC is handled through Sing-Box support.

## Profiles

Edit `profiles.conf`.

Format:

```text
profile|artifact-dir|description
```

The profile must match `define Device/<profile>` in official `target/linux/mediatek/image/filogic.mk`.

## Local WSL Build

Use the WSL filesystem, not `/mnt/c`, for full builds.

```bash
cd /home/miunah/my_project/mt798x_build_2512
git clone --depth=1 -b openwrt-25.12 https://github.com/immortalwrt/immortalwrt.git openwrt
bash build_all.sh
```

Build one profile:

```bash
BUILD_PROFILE=cmcc_rax3000m bash build_all.sh
```

## GitHub Actions

Build locally in WSL first. GitHub Actions is kept as a later manual release template only; do not use it as the first validation path.

Run workflow `mt798x_25_12_CI` manually only after local WSL output has been reviewed.

- `build_profile=all`: build every profile in `profiles.conf`.
- `build_profile=<profile>`: build one listed profile.
- `build_profile=custom` plus `custom_profile=<profile>`: build one official profile not listed in `profiles.conf`.

Enable `Settings > Actions > General > Workflow permissions > Read and write permissions` so the workflow can create Releases.

The workflow has only `workflow_dispatch`; it must not auto-run on push.

## Known 25.12 Fixes

- `scut-unicom`: its upstream date-based `PKG_RELEASE=YYYY-MM-DD` is not a valid APK version. `01_prepare.sh` rewrites it to `PKG_VERSION=YYYYMMDD` plus `PKG_RELEASE=1`.
- `luci-app-openvpn-server`: its duplicate `/etc/config/openvpn` conflicts with `openvpn-openssl`. `01_prepare.sh` removes that file and seeds `openvpn.myvpn` through uci-defaults.
- `tailscale`: use official `luci-app-tailscale-community` and official `tailscale`; do not clone the old third-party `luci-app-tailscale`.

## Wi-Fi Notes

23.05 verified source facts:

- Keep `/sbin/wifi`.
- Use `kmod-mt_wifi`, `mtwifi-cfg`, `luci-app-mtwifi-cfg`, and `wifi-dats`.
- Do not use `wifi-profile` or `luci-app-mtk`.

25.12 source facts:

- Official `mediatek/filogic` profiles select their own wireless packages.
- This project does not delete `/sbin/wifi`.
- This project does not enable the old `wifi-profile` workaround.

Do not force the 23.05 private MTK Wi-Fi stack into 25.12 unless a 25.12-compatible source is added and validated.
