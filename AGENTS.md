# AGENTS.md - ImmortalWrt MT798x 25.12 编译

## 项目

使用官方稳定分支为 MT7981/MT7986 路由器编译 ImmortalWrt 25.12 固件。

- 源码仓库：`https://github.com/immortalwrt/immortalwrt.git`
- 源码分支：`openwrt-25.12`
- 编译目标：`mediatek/filogic`

## 重要的 23.05 参考

已验证可用的 23.05 构建可以作为插件和流程参考，但它的 Wi-Fi 栈和分支强绑定：

- 23.05 使用 `padavanonly/immortalwrt-mt798x-6.6` 的 `openwrt-23.05` 分支。
- 实际 WSL 源码状态里，标准 `package/base-files/files/sbin/wifi` 存在。
- 实际 defconfig 选择 `kmod-mt_wifi`、`mtwifi-cfg`、`luci-app-mtwifi-cfg` 和 `wifi-dats`。
- 实际 defconfig 禁用 `wifi-profile` 和 `luci-app-mtk`。
- 不要照搬旧 CI 里删除 `/sbin/wifi` 的步骤。

## 25.12 Wi-Fi

除非已经加入并验证 25.12 兼容的源码，否则不要把 23.05 私有 MTK Wi-Fi 包强行塞进官方 25.12。官方 25.12 `mediatek/filogic` profile 会选择自己的无线包。

## 编译策略

当前策略是：GitHub Actions 手动编译为主，本地 WSL 只作为排错和复现参考。workflow 默认编译 `mt7981-ax3000` 分组；只有明确输入 `all` 时，才会展开 `profile_groups.conf` 里的全部 3 个分组。

workflow 必须保持手动触发，不允许添加自动 `push` 触发。

如果必须本地复现，第一次 25.12 编译不要用 `JOBS=8`：之前 host LLVM/Clang 编译阶段触发 OOM，`cc1plus` 被杀掉。`tools/llvm-bpf` 缓存好之前，用 `JOBS=1` 或 `JOBS=2`。已测试的 WSL2 资源基线是 `C:\Users\MiunaH\.wslconfig` 里 12GB RAM 加 16GB swap。

2026-07-05 本地 WSL 验证：

- `cmcc_rax3000m` 的直接 `make -j1 V=s` 已完成。
- `BUILD_PROFILE=cmcc_rax3000m JOBS=2 DOWNLOAD_JOBS=8 bash build_all.sh` 已完成并收集产物。
- 产物路径是 `/home/miunah/my_project/mt798x_build_2512/artifacts/cmcc_rax3000m`。
- 真实设备刷机仍未验证。

已知 25.12 包修复：

- `scut-unicom`：把上游 `PKG_RELEASE=YYYY-MM-DD` 改成 APK 兼容的 `PKG_VERSION=YYYYMMDD` 加 `PKG_RELEASE=1`。
- `luci-app-openvpn-server`：删除重复的 `/etc/config/openvpn`，并通过 uci-defaults 初始化 `openvpn.myvpn`。
- `tailscale`：使用官方 `luci-app-tailscale-community`；不要克隆旧第三方 `luci-app-tailscale`。

## 设备 Profile

Profile 写在 `profiles.conf`，格式是：

```text
profile|artifact-dir|description
```

`profile` 必须匹配 `target/linux/mediatek/image/filogic.mk` 里的 `define Device/<profile>`。

编译分组写在 `profile_groups.conf`，格式是：

```text
group|artifact-dir|profiles|description
```

组内 `profiles` 使用空格分隔，并通过 OpenWrt multi-profile 一次构建，避免每台设备重复编译同一套工具链。

## 插件列表

额外插件写在 `package.conf`，每行一个包名，不带 `CONFIG_PACKAGE_` 前缀，也不带 `=y`。

`02_add_package.sh` 会检查包名格式和重复项。`03_validate_packages.sh` 会在 `make defconfig` 后检查所有请求的包是否真的被启用。

每次 `make defconfig` 后都要运行 `06_validate_target_config.sh <profile>`；否则格式错误的 Kconfig 符号可能静默退回到其他默认设备。
