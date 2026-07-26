# ImmortalWrt MT798x 25.12 编译指南

## 当前状态

2026-07-05 在 WSL 检查过：

- `cmcc_rax3000m` 通过 `make defconfig`。
- `06_validate_target_config.sh` 确认指定 profile 仍然被选中。
- `03_validate_packages.sh` 确认请求的 33 个包都已启用。
- `cmcc_rax3000m` 的直接 `make -j1 V=s` 编译完成。
- `BUILD_PROFILE=cmcc_rax3000m JOBS=2 DOWNLOAD_JOBS=8 bash build_all.sh` 编译完成，并把产物收集到 `/home/miunah/my_project/mt798x_build_2512/artifacts/cmcc_rax3000m`。
- 真实设备刷机仍未验证。

## 源码

- 源码仓库：`immortalwrt/immortalwrt`
- 源码分支：`openwrt-25.12`
- 编译目标：`mediatek/filogic`

已验证的 23.05 固件使用 `padavanonly/immortalwrt-mt798x-6.6` 私有 MTK Wi-Fi 路线。这个仓库目前没有 `openwrt-25.12` 分支，所以 25.12 项目使用官方 ImmortalWrt `mediatek/filogic` profile。

## 插件

编辑 `package.conf`，每行写一个包名。不要写 `CONFIG_PACKAGE_` 前缀，也不要写 `=y`。

25.12 相比 23.05 的包名差异：

- WireGuard 的 LuCI 支持是 `luci-proto-wireguard`。
- Socat 直接选择 `socat`。
- Passwall 26.7.1 没有单独的 `luci-app-passwall_INCLUDE_tuic_client`，TUIC 通过 Sing-Box 支持处理。

## 设备 Profile

编辑 `profiles.conf`。

格式：

```text
profile|artifact-dir|description
```

`profile` 必须匹配官方源码 `target/linux/mediatek/image/filogic.mk` 里的 `define Device/<profile>`。

`profile_groups.conf` 用来把多个 profile 合成一个编译组。组内 profile 会在同一个 OpenWrt multi-profile 构建里一起编译，避免每台设备重复编译一遍工具链。

## GitHub Actions

现在以 GitHub Actions 手动编译为主，本地 WSL 只用于排错和复现。

手动运行 workflow：`MT798x 25.12 手动编译`。

- 默认 `build_target=mt7981-ax3000`：编译 MT7981 / AX3000 这一组设备。
- `build_target=<group>`：编译 `profile_groups.conf` 里的某个分组。
- `build_target=<profile>`：只编译一个已列出的 profile。
- `build_target=custom` 加 `custom_profile=<profile>`：编译一个没列出、但官方源码存在的 profile。
- `build_target=all`：编译 `profile_groups.conf` 里的全部 3 个分组。

确保仓库设置中启用了：

`Settings > Actions > General > Workflow permissions > Read and write permissions`

否则 workflow 可能能编译，但不能创建 Release。

workflow 只有 `workflow_dispatch`，不能因为 push 自动运行。

## 本地 WSL 参考

本地完整编译必须放在 WSL 文件系统里，不要放在 `/mnt/c`。现在不建议长期保留本地源码和缓存，下面命令只用于排错参考。

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

## 已知 25.12 修复

- `luci-app-scutclient`：固定上游提交，把 LuCI 依赖和运行状态改为局部变量，保留 dispatcher 的 `template()` 路由函数，并用标准 Lua 文件检查替代 `nixio.fs`。
- `scut-unicom`：上游日期格式 `PKG_RELEASE=YYYY-MM-DD` 不是合法 APK 版本，`01_prepare.sh` 会改写为 `PKG_VERSION=YYYYMMDD` 加 `PKG_RELEASE=1`。
- `luci-app-openvpn-server`：自带重复的 `/etc/config/openvpn`，会和 `openvpn-openssl` 冲突；`01_prepare.sh` 会删除该文件，并通过 uci-defaults 初始化 `openvpn.myvpn`。
- `tailscale`：使用官方 `luci-app-tailscale-community` 和官方 `tailscale`；不要再克隆旧的第三方 `luci-app-tailscale`。

## Wi-Fi 说明

23.05 已验证源码事实：

- 保留 `/sbin/wifi`。
- 使用 `kmod-mt_wifi`、`mtwifi-cfg`、`luci-app-mtwifi-cfg` 和 `wifi-dats`。
- 不使用 `wifi-profile` 或 `luci-app-mtk`。

25.12 源码事实：

- 官方 `mediatek/filogic` profile 会选择自己的无线包。
- 本项目不删除 `/sbin/wifi`。
- 本项目不启用旧的 `wifi-profile` 绕路方案。

除非已经加入并验证 25.12 兼容的源码，否则不要把 23.05 私有 MTK Wi-Fi 栈强行塞进 25.12。
