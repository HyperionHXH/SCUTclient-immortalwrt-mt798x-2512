# ImmortalWrt MT798x 25.12 Build

Build ImmortalWrt 25.12 firmware for MT7981/MT7986 routers.

Source:

- Repository: `immortalwrt/immortalwrt`
- Branch: `openwrt-25.12`
- Target: `mediatek/filogic`

The old verified 23.05 build used `padavanonly/immortalwrt-mt798x-6.6` plus the MTK private Wi-Fi stack (`kmod-mt_wifi`, `mtwifi-cfg`, `luci-app-mtwifi-cfg`). That repository currently has no 25.12 branch, so this project uses the official ImmortalWrt 25.12 stable branch and its built-in `mediatek/filogic` device profiles.

## Files

- `profiles.conf`: device profiles to build.
- `package.conf`: extra packages and LuCI apps.
- `01_prepare.sh`: update feeds and add third-party packages used by the 23.05 build.
- `04_make_profile_config.sh`: generate `.config` for one `mediatek/filogic` profile.
- `06_validate_target_config.sh`: fail if `make defconfig` did not keep the requested profile selected.
- `.github/workflows/mt798x.yml`: GitHub Actions build and release workflow.

## Local Build

```bash
cd /home/miunah/my_project/mt798x_build_2512

git clone --depth=1 -b openwrt-25.12 https://github.com/immortalwrt/immortalwrt.git openwrt
bash build_all.sh
```

Build one profile:

```bash
BUILD_PROFILE=xiaomi_mi-router-ax3000t bash build_all.sh
```

## Validation Status

Checked on 2026-07-04 in WSL:

- `cmcc_rax3000m` passed `make defconfig`.
- `06_validate_target_config.sh` confirmed the requested profile stayed selected.
- `03_validate_packages.sh` confirmed all 33 requested packages are enabled.

Full firmware compilation and real-device flashing are still pending.

## GitHub Actions

Push this directory as a repository, enable `Settings > Actions > General > Workflow permissions > Read and write permissions`, then run `mt798x_25_12_CI`.

Manual inputs:

- `build_profile=all`: build every profile in `profiles.conf`.
- `build_profile=<profile>`: build one profile, such as `cmcc_rax3000m`.
- `build_profile=custom` with `custom_profile=<profile>`: build a profile not listed in `profiles.conf`.

## Wi-Fi Notes

Package-name note for 25.12:

- WireGuard LuCI support is `luci-proto-wireguard`.
- Socat is selected as `socat`.
- Passwall 26.7.1 has no separate `luci-app-passwall_INCLUDE_tuic_client`; TUIC is handled through Sing-Box support.

23.05 verified source state:

- `package/base-files/files/sbin/wifi` is present and must not be deleted.
- defconfigs use `kmod-mt_wifi`, `mtwifi-cfg`, `luci-app-mtwifi-cfg`, and `wifi-dats`.
- `wifi-profile` and `luci-app-mtk` are not the active route.
- `mtwifi-cfg` installs `/etc/hotplug.d/net/10-mtwifi-detect`, `/lib/wifi/mtwifi.sh`, and `/lib/netifd/wireless/mtwifi.sh`.

25.12 official source state:

- `openwrt-25.12` uses official `mediatek/filogic` profiles.
- Device wireless packages are selected by each upstream profile, typically `kmod-mt7915e`, SoC firmware packages, and `*-wo-firmware`.
- This build does not delete or replace `/sbin/wifi`, and does not enable the old `wifi-profile` workaround.

Always test one device profile on real hardware before trusting a full matrix release.
