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
- `.github/workflows/mt798x.yml`: manual-only GitHub Actions build and release template.

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

The default local compile parallelism is `JOBS=2`. The first WSL test with `JOBS=8` failed while building host LLVM/Clang because the kernel OOM-killed `cc1plus`, so raise `JOBS` only after host LLVM is already cached or WSL memory is increased.

Recommended WSL2 resource settings for the first 25.12 build:

```ini
[wsl2]
memory=12GB
processors=16
swap=16GB
localhostForwarding=true
```

After editing `C:\Users\MiunaH\.wslconfig`, run `wsl --shutdown` from Windows and confirm with `free -h` inside WSL. The first successful retry used 12GB RAM plus 16GB swap and continued past the previous host LLVM OOM point with `make -j1 V=s`.

## Validation Status

Checked on 2026-07-05 in WSL:

- `cmcc_rax3000m` passed `make defconfig`.
- `06_validate_target_config.sh` confirmed the requested profile stayed selected.
- `03_validate_packages.sh` confirmed all 33 requested packages are enabled.
- First full compile attempt with `JOBS=8` reached host LLVM/Clang, then failed due to WSL OOM, not a package source error.
- WSL was then configured with 12GB RAM and 16GB swap. A direct `make -j1 V=s` completed successfully for `cmcc_rax3000m`.
- `BUILD_PROFILE=cmcc_rax3000m JOBS=2 DOWNLOAD_JOBS=8 bash build_all.sh` completed successfully and collected firmware artifacts under `/home/miunah/my_project/mt798x_build_2512/artifacts/cmcc_rax3000m`.
- Generated firmware includes `initramfs-recovery.itb`, `squashfs-sysupgrade.itb`, eMMC/NAND preloaders, eMMC/NAND BL31/U-Boot FIP files, eMMC GPT, manifest, and `sha256sums`.

Real-device flashing is still pending.

Compatibility fixes applied during the successful local build:

- `scut-unicom`: convert date-based `PKG_RELEASE` from `YYYY-MM-DD` to APK-compatible `PKG_VERSION=YYYYMMDD` plus `PKG_RELEASE=1`.
- `luci-app-openvpn-server`: remove its duplicate `/etc/config/openvpn` file and seed `openvpn.myvpn` through uci-defaults instead, avoiding a conflict with `openvpn-openssl`.
- `tailscale`: use official `luci-app-tailscale-community` with official `tailscale`, and remove the old third-party `package/luci-app-tailscale` clone to avoid `/etc/config/tailscale` and init script conflicts.

## Build Policy

Build in local WSL first. GitHub Actions must stay manual-only until at least one WSL build succeeds and the firmware is reviewed.

Reason: local WSL builds are easier to debug and patch when package or toolchain failures appear.

The workflow file is kept only as a later release template and has no automatic `push` trigger. Do not rely on GitHub Actions for the first successful 25.12 firmware.

## GitHub Actions Template

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
