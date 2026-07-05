# AGENTS.md - ImmortalWrt MT798x 25.12 Build

## Project

Build ImmortalWrt 25.12 firmware for MT7981/MT7986 routers using the official stable branch.

- Source repository: `https://github.com/immortalwrt/immortalwrt.git`
- Source branch: `openwrt-25.12`
- Target: `mediatek/filogic`

## Important 23.05 Reference

The verified 23.05 build is useful as a package/workflow reference, but its Wi-Fi stack is branch-specific:

- It uses `padavanonly/immortalwrt-mt798x-6.6` branch `openwrt-23.05`.
- Actual WSL source state has standard `package/base-files/files/sbin/wifi` present.
- Actual defconfigs select `kmod-mt_wifi`, `mtwifi-cfg`, `luci-app-mtwifi-cfg`, and `wifi-dats`.
- Actual defconfigs disable `wifi-profile` and `luci-app-mtk`.
- Do not copy old CI steps that delete `/sbin/wifi`.

## 25.12 Wi-Fi

Do not force 23.05 MTK private Wi-Fi packages into official 25.12 unless a 25.12-compatible source exists and has been validated. Official 25.12 `mediatek/filogic` profiles select their own wireless packages.

## Build Policy

Build and debug in local WSL first. GitHub Actions must stay manual-only until at least one WSL build succeeds and the output has been reviewed.

Keep the workflow file as a later release template only, with no automatic `push` trigger; do not use GitHub Actions as the first validation path.

For the first local 25.12 build, avoid `JOBS=8`: it OOM-killed `cc1plus` while building host LLVM/Clang. Use `JOBS=1` or `JOBS=2` until `tools/llvm-bpf` is cached. The tested WSL2 resource baseline is 12GB RAM plus 16GB swap in `C:\Users\MiunaH\.wslconfig`.

2026-07-05 local WSL validation:

- Direct `make -j1 V=s` completed for `cmcc_rax3000m`.
- `BUILD_PROFILE=cmcc_rax3000m JOBS=2 DOWNLOAD_JOBS=8 bash build_all.sh` completed and collected artifacts.
- Artifacts are under `/home/miunah/my_project/mt798x_build_2512/artifacts/cmcc_rax3000m`.
- Real-device flashing is still pending.

Known 25.12 package fixes:

- `scut-unicom`: rewrite upstream `PKG_RELEASE=YYYY-MM-DD` to APK-compatible `PKG_VERSION=YYYYMMDD` plus `PKG_RELEASE=1`.
- `luci-app-openvpn-server`: remove duplicate `/etc/config/openvpn` and seed `openvpn.myvpn` through uci-defaults.
- `tailscale`: use official `luci-app-tailscale-community`; do not clone old third-party `luci-app-tailscale`.

## Build Profiles

Profiles live in `profiles.conf` as:

```text
profile|artifact-dir|description
```

The profile must match `define Device/<profile>` in `target/linux/mediatek/image/filogic.mk`.

## Package List

Extra packages live in `package.conf`, one package symbol per line without `CONFIG_PACKAGE_` or `=y`.

`02_add_package.sh` validates package entry syntax and duplicate entries. `03_validate_packages.sh` fails after `make defconfig` if any requested package was not enabled.

Always run `06_validate_target_config.sh <profile>` after `make defconfig`; otherwise a malformed Kconfig symbol can silently fall back to another default device.
