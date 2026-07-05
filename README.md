# ImmortalWrt MT798x 25.12 固件编译

这个仓库用于编译 ImmortalWrt 25.12 下的 MT7981/MT7986 路由器固件。

- 源码仓库：`immortalwrt/immortalwrt`
- 源码分支：`openwrt-25.12`
- 编译目标：`mediatek/filogic`
- 当前策略：以 GitHub Actions 手动编译为主，本地 WSL 只作为排错和复现参考

已经验证可用的 23.05 仓库使用 `padavanonly/immortalwrt-mt798x-6.6` 和 MTK 私有 Wi-Fi 栈（`kmod-mt_wifi`、`mtwifi-cfg`、`luci-app-mtwifi-cfg`）。这个源码仓库目前没有 25.12 分支，所以 25.12 这里改用官方 ImmortalWrt 稳定分支自带的 `mediatek/filogic` 设备 profile。

## 文件说明

- `profiles.conf`：要编译的设备 profile 列表。
- `profile_groups.conf`：按平台/档位合并的编译组，GitHub Actions 默认按这个分组编译。
- `package.conf`：额外插件和 LuCI 应用列表。
- `01_prepare.sh`：刷新 feeds，并加入 23.05 自用固件也用到的第三方包。
- `04_make_profile_config.sh`：为单个 `mediatek/filogic` profile 生成 `.config`。
- `06_validate_target_config.sh`：检查 `make defconfig` 后指定 profile 是否仍然被选中。
- `.github/workflows/mt798x.yml`：只允许手动触发的 GitHub Actions 编译和 Release 流程。

## GitHub Actions 编译

入口：

[MT798x 25.12 手动编译](https://github.com/HyperionHXH/-immortalwrt-mt798x-2512/actions/workflows/mt798x.yml)

点 **Run workflow** 后可以选择：

- 默认 `build_target=mt7981-ax3000`：编译 MT7981 / AX3000 这一组设备，共用同一套工具链。
- `build_target=<group>`：编译 `profile_groups.conf` 里的某个分组，例如 `mt7986-ax6000`。
- `build_target=<profile>`：只编译某个已列出的单独 profile，例如 `cmcc_rax3000m`。
- `build_target=custom` 并填写 `custom_profile=<profile>`：编译一个没写进 `profiles.conf`、但官方源码里存在的 profile。
- `build_target=all`：编译 `profile_groups.conf` 里的所有分组；当前只展开 3 个分组 job，不再把 30 个设备拆成 30 个 job。

Actions 只有 `workflow_dispatch`，不会因为 push 自动开始编译。

如果 Release 创建失败，检查仓库设置：

`Settings > Actions > General > Workflow permissions > Read and write permissions`

## 本地 WSL 参考

现在不建议在本地长期保留完整源码和编译缓存。下面命令只用于以后排查 GitHub Actions 失败、或者需要本地复现时参考。

```bash
cd /home/miunah/my_project/mt798x_build_2512

git clone --depth=1 -b openwrt-25.12 https://github.com/immortalwrt/immortalwrt.git openwrt
bash build_all.sh
```

只编译一个分组：

```bash
BUILD_TARGET=mt7981-ax3000 bash build_all.sh
```

只编译一个 profile：

```bash
BUILD_TARGET=cmcc_rax3000m bash build_all.sh
```

本地默认编译线程是 `JOBS=2`。第一次 WSL 测试用 `JOBS=8` 时，host LLVM/Clang 编译阶段触发内核 OOM，`cc1plus` 被杀掉；除非 host LLVM 已经缓存好，或者 WSL 内存已经调大，否则不要盲目提高 `JOBS`。

如果必须本地做第一次完整编译，建议 WSL2 资源配置：

```ini
[wsl2]
memory=12GB
processors=16
swap=16GB
localhostForwarding=true
```

编辑 `C:\Users\MiunaH\.wslconfig` 后，在 Windows 执行 `wsl --shutdown`，再进 WSL 用 `free -h` 确认内存和 swap。之前成功越过 host LLVM OOM 点的本地重试使用了 12GB RAM、16GB swap 和 `make -j1 V=s`。

## 验证状态

2026-07-05 在 WSL 检查过：

- `cmcc_rax3000m` 通过 `make defconfig`。
- `06_validate_target_config.sh` 确认指定 profile 没有被 `make defconfig` 改掉。
- `03_validate_packages.sh` 确认请求的 33 个包都已启用。
- 第一次 `JOBS=8` 完整编译走到 host LLVM/Clang 后因为 WSL OOM 失败，不是插件源码错误。
- WSL 调整为 12GB RAM 和 16GB swap 后，`cmcc_rax3000m` 的 `make -j1 V=s` 完成。
- `BUILD_PROFILE=cmcc_rax3000m JOBS=2 DOWNLOAD_JOBS=8 bash build_all.sh` 完成，并把固件收集到 `/home/miunah/my_project/mt798x_build_2512/artifacts/cmcc_rax3000m`。
- 产物包括 `initramfs-recovery.itb`、`squashfs-sysupgrade.itb`、eMMC/NAND preloader、eMMC/NAND BL31/U-Boot FIP、eMMC GPT、manifest 和 `sha256sums`。

真实设备刷机仍未验证。

本地成功编译时应用过的兼容修复：

- `scut-unicom`：把日期格式 `PKG_RELEASE=YYYY-MM-DD` 改成 APK 可接受的 `PKG_VERSION=YYYYMMDD` 加 `PKG_RELEASE=1`。
- `luci-app-openvpn-server`：删除重复的 `/etc/config/openvpn`，改用 uci-defaults 初始化 `openvpn.myvpn`，避免和 `openvpn-openssl` 冲突。
- `tailscale`：使用官方 `luci-app-tailscale-community` 和官方 `tailscale`，删除旧的第三方 `package/luci-app-tailscale` 克隆，避免 `/etc/config/tailscale` 和 init 脚本冲突。

## Wi-Fi 说明

25.12 包名差异：

- WireGuard 的 LuCI 支持是 `luci-proto-wireguard`。
- Socat 直接选择 `socat`。
- Passwall 26.7.1 没有单独的 `luci-app-passwall_INCLUDE_tuic_client`，TUIC 通过 Sing-Box 支持处理。

23.05 已验证源码状态：

- `package/base-files/files/sbin/wifi` 存在，必须保留。
- defconfig 使用 `kmod-mt_wifi`、`mtwifi-cfg`、`luci-app-mtwifi-cfg` 和 `wifi-dats`。
- `wifi-profile` 和 `luci-app-mtk` 不是当前可用路线。
- `mtwifi-cfg` 安装 `/etc/hotplug.d/net/10-mtwifi-detect`、`/lib/wifi/mtwifi.sh` 和 `/lib/netifd/wireless/mtwifi.sh`。

25.12 官方源码状态：

- `openwrt-25.12` 使用官方 `mediatek/filogic` profile。
- 无线相关包由每个上游 profile 自己选择，通常是 `kmod-mt7915e`、SoC firmware 包和 `*-wo-firmware`。
- 本仓库不会删除或替换 `/sbin/wifi`，也不会启用旧的 `wifi-profile` 绕路方案。

全量发布前，至少要先拿一个 profile 在真实设备上验证启动、以太网、Wi-Fi、LuCI 和 sysupgrade。
