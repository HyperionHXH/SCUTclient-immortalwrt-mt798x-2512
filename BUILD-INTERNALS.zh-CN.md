# ImmortalWrt MT798x 25.12 编译详解

> 这份文档的目标：让你（有点 C++ 基础、没接触过路由器固件）能彻底看懂
> `immortalwrt-mt798x-2512/` 里每个文件在干什么，并且以后能自己
> **更新编译流程、增删插件、加设备、重新出固件**。
>
> 阅读顺序建议：先看第 0、1、2 章建立整体概念，再按需查第 3~6 章的逐行注释，
> 最后把第 7 章当成操作手册。

---

## 目录

- [0. 先搞懂这些名词](#0-先搞懂这些名词)
- [1. 编译总流程](#1-编译总流程)
- [2. 文件地图：哪个文件该改，哪个不能动](#2-文件地图哪个文件该改哪个不能动)
- [3. 脚本逐行详解](#3-脚本逐行详解)
  - [3.1 build_all.sh](#31-build_allsh本地一键编译)
  - [3.2 01_prepare.sh](#32-01_preparesh准备源码)
  - [3.3 02_add_package.sh](#33-02_add_packagesh把插件写进-config)
  - [3.4 03_validate_packages.sh](#34-03_validate_packagessh检查插件真的启用了)
  - [3.5 04_make_profile_config.sh](#35-04_make_profile_configsh生成-config)
  - [3.6 05_validate_profile.sh](#36-05_validate_profilesh检查设备名存在)
  - [3.7 06_validate_target_config.sh](#37-06_validate_target_configsh检查设备没被改掉)
- [4. 配置文件详解](#4-配置文件详解)
- [5. GitHub Actions 工作流详解](#5-github-actions-工作流详解)
- [6. 设备适配详解（以 HONOR FUR-602 为例）](#6-设备适配详解以-honor-fur-602-为例)
- [7. 日常操作手册](#7-日常操作手册)
- [8. 报错对照表](#8-报错对照表)
- [9. 容易踩的坑](#9-容易踩的坑)

---

## 0. 先搞懂这些名词

### 0.1 两个"仓库"要分清

| | 是什么 | 在哪里 | 你该不该动 |
|---|---|---|---|
| **包装仓库**（本项目） | 你的"配方"：告诉编译器编哪台设备、装哪些插件、打哪些补丁 | `Desktop\openwrt\immortalwrt-mt798x-2512\`（本目录，十几个文件） | ✅ 你要改的就是这里 |
| **源码树** | 真正的 OpenWrt 源代码，几十万个文件（内核、驱动、LuCI、各种包） | 编译时自动下载到 `immortalwrt-mt798x-2512/openwrt/`（被 `.gitignore` 忽略） | ❌ 不要手改，会被重新克隆/覆盖 |

编译 = 用"配方"去配置源码树 → 交叉编译 → 产出 `.bin` / `.itb` 固件。

### 0.2 名词表

| 名词 | 大白话解释 |
|---|---|
| **交叉编译** | 在你 x86 电脑上，编译出 ARM 路由器 CPU 能执行的程序。因为路由器性能太弱，跑不动编译器。 |
| **target / 目标平台** | `mediatek`，指联发科芯片平台。 |
| **subtarget / 子平台** | `filogic`，指 MT7981 / MT7986 这一代芯片。 |
| **profile / Device** | 具体机型，例如 `honor_fur-602`、`cmcc_rax3000m`。定义在源码的 `target/linux/mediatek/image/filogic.mk` 里。 |
| **feeds** | OpenWrt 的"软件源"。`./scripts/feeds update -a` 把一堆额外软件包仓库拉下来，`install -a` 再把它们软链接进 `package/feeds/`，这样 `make menuconfig` 才能看到。 |
| **package / 软件包** | 一个功能模块（比如 `luci-app-sqm`），每个包有自己的 Makefile 描述"从哪下载、怎么编译、装哪些文件"。 |
| **Kconfig / .config** | OpenWrt 用 Kconfig 系统管理"要编译哪些东西"。`.config` 是一份纯文本清单，形如 `CONFIG_PACKAGE_luci-app-sqm=y`。 |
| **`make defconfig`** | 按 Kconfig 的规则，把 `.config` 里没写的选项补上默认值，并**删掉源码里不存在的选项**。它不会覆盖你已经明确写下的值。 |
| **`make menuconfig`** | 图形化菜单，改完会写回 `.config`。⚠️ 本项目里 `.config` 每次都由脚本重新生成，所以菜单里的改动会丢，改插件请改 `package.conf`。 |
| **`dl/`** | 所有第三方源码压缩包的下载缓存。第一次编译要下载几个 GB，之后复用。 |
| **`bin/targets/mediatek/filogic/`** | 最终固件产物的目录。 |
| **sysupgrade** | 日常升级用的文件（在已装 OpenWrt 的系统里刷）。 |
| **factory** | 全新刷机 / 首次刷入用的文件（从 U-Boot 或原厂系统刷）。 |
| **squashfs** | 只读的压缩根文件系统。系统文件压得很小，用户配置存在另一个可写分区。 |
| **UBI** | NAND 闪存上的卷管理层，负责坏块管理。MT798x 基本都是 SPI-NAND + UBI。 |
| **DTS / 设备树** | 用类似 C 的文本语法描述"这块板子上有什么硬件、接在哪个引脚"。内核启动时读它来初始化硬件。 |
| **APK** | 25.12 用的包管理器（取代旧的 opkg）。它的版本号规则比 opkg 严，不能出现日期里的横杠。 |
| **toolchain / 工具链** | 交叉编译器（gcc/clang 等）。第一次编译要花很久先把它编出来，之后各组共用。 |

---

## 1. 编译总流程

```
  你改的 3 个文件              自动脚本                 产物
  ─────────────────           ─────────────           ──────────────
  profiles.conf      ──05──→ 确认设备名在源码里存在
  profile_groups.conf ─04──→ 生成一份全新的 .config ──┐
  package.conf       ──02──→ 往 .config 追加插件 ─────┤
                                                      ↓
                                              make defconfig
                                        （补全默认值、丢掉不存在的项）
                                                      ↓
                                        06 检查设备还在 / 03 检查插件还在
                                                      ↓
                                               make download
                                        （把源码包下到 openwrt/dl/）
                                                      ↓
                                                  make -jN
                                        （编译工具链 → 内核 → 包 → 镜像）
                                                      ↓
                          openwrt/bin/targets/mediatek/filogic/*.bin
                                                      ↓
                     artifacts/<组名>/          （日常升级用）
                     artifacts/<组名>-install/  （新刷/救砖用）
                     + sha256sums 校验文件 + 7z 压缩包
```

**顺序为什么这么排**（每一步都是防呆）：

1. `05` 先查设备名 —— 名字写错就别浪费时间了。
2. `04` 生成 `.config` —— 注意它会**整个覆盖** `.config`。
3. `02` 追加插件 —— 必须在 `04` 之后，否则被覆盖。
4. `make defconfig` —— 必须在这里，因为它才真正把配置补全。
5. `06` / `03` 校验 —— 必须在 `defconfig` 之后，因为 `defconfig` 可能悄悄改掉东西。
6. `make download` 和 `make` 分开 —— 下载失败一眼能看出是网络问题，而不是编到一半才炸。

一个"编译组"（group）走完上面全套。多个组依次编译，**工具链和已编译的包会复用**，所以第二组开始会快很多。

---

## 2. 文件地图：哪个文件该改，哪个不能动

### ✅ 你日常要改的（3 个）

| 文件 | 作用 |
|---|---|
| `package.conf` | 插件清单。一行一个包名。增删插件就改这里。 |
| `profiles.conf` | 设备清单（单个设备）。 |
| `profile_groups.conf` | 编译分组（多台设备一起编，共享工具链）。 |

### 🔍 你想深入时要看的（了解即可，改前先想清楚）

| 文件 | 作用 |
|---|---|
| `04_make_profile_config.sh` | 生成 `.config` 的模板。固件版本号、压缩方式在这里。 |
| `01_prepare.sh` | 编译前的所有"魔改"：打补丁、换第三方包、首启默认设置。 |
| `.github/workflows/mt798x.yml` | GitHub 上点按钮编译的流程。 |
| `build_all.sh` | 本地 WSL 一键编译。 |

### ⚙️ 校验脚本（一般不用改，但要知道它们在检查什么）

| 文件 | 检查什么 |
|---|---|
| `05_validate_profile.sh` | 设备名在 `filogic.mk` 里存在吗 |
| `06_validate_target_config.sh` | `defconfig` 之后设备没被换成别的吧 |
| `03_validate_packages.sh` | 插件真的都启用了？SQM 依赖齐吗？Tailscale 确实没混进来吧 |
| `scripts/validate_fur602.sh` | FUR602 的分区表、网口、Wi-Fi 校准、镜像格式、上游提交号 |
| `scripts/validate_scutclient.sh` | 校园网插件的 Lua 代码是否符合新 LuCI 规范 |

### 🔧 设备适配文件（和 FUR602 强相关，改前必须懂）

| 文件 | 作用 |
|---|---|
| `patches/2512/files/mt7981b-honor-fur-602.dts` | FUR602 的硬件描述（设备树）。 |
| `patches/2512/0001-add-honor-fur-602.sh` | 把 FUR602 加进源码：拷 DTS、往 `filogic.mk` 插设备定义、往 `02_network` 插网口映射。 |
| `patches/2512/build-system/download-reliability.patch` | 让源码下载更抗卡死（换镜像、加超时）。 |
| `patches/2512/luci-app-scutclient-modern-luci.patch` | 修校园网插件在新版 LuCI 下的报错。 |

### 🗂️ 杂项

| 文件 | 作用 |
|---|---|
| `.config`（本目录根下） | 只是 `04` 脚本为单个设备生成的一份样例/残留，编译时**不会用到**（真正用的是 `openwrt/.config`）。可以当参考。 |
| `.gitattributes` | 强制所有脚本用 LF 换行（见 [9.3](#93-windows-换行符-crlf-会毁掉所有脚本)）。 |
| `.gitignore` | 忽略 `openwrt/`、`artifacts/`、`logs/`、`*.7z` 等。 |
| `README.md` / `GUIDE.zh-CN.md` / `AGENTS.md` | 给人（和 AI）看的说明文档。 |

---

## 3. 脚本逐行详解

> 下面每个代码块里，`#` 开头的注释是我加的讲解；脚本里原有的注释我保留原样。
> Shell 语法速查：`$0` 脚本名、`$1` 第一个参数、`"$var"` 取变量、`${var:-默认}` 有值用值没值用默认、
> `[ -d 路径 ]` 判断目录存在、`[ -f 路径 ]` 判断文件存在、`&&` 前面成功才执行后面、`||` 前面失败才执行后面。

---

### 3.1 `build_all.sh`（本地一键编译）

**作用**：在 WSL 里从零到有，把源码拉下来、配置好、编译、把产物收集到 `artifacts/`。

#### 3.1.1 开头与变量

```bash
#!/bin/bash
# ↑ 声明用 bash 解释本文件（不能用 sh，下面用了 [[ ]]、< <(...) 等 bash 专有语法）

set -e -o pipefail
# ↑ set -e            ：任何一条命令失败（返回非 0）就立刻退出，避免"出错了还继续编"
#   set -o pipefail  ：管道 a | b 中只要 a 失败，整条管道就算失败
#   合成一行写法就是 set -e -o pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
# ↑ 固定 PATH。有些环境（CI、或 WSL 里用 sudo 之后）PATH 会缺项导致 make/git 找不到，
#   这里显式给一套标准路径，保证命令都能找到。

export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
# ↑ Go 语言的模块代理。OpenClash / Passwall 里有 Go 写的组件，
#   国内直连 proxy.golang.org 会超时，所以走 goproxy.cn。
#   ${VAR:-默认值} = "如果 VAR 已有值就用原来的，否则用默认值"。

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt.git}"
# ↑ 上游源码仓库
REPO_BRANCH="${REPO_BRANCH:-openwrt-25.12}"
# ↑ 分支名（主要用于显示和缓存标识）
REPO_COMMIT="${REPO_COMMIT:-1cfeb3edade40fe2dfec59c21381de1d8e361100}"
# ↑ 【重要】锁定的源码提交号。保证每次编译用的源码一模一样，
#   不会出现"昨天能编今天编不过"。更新方法见 7.6。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# ↑ 本脚本所在目录的绝对路径。
#   $0 = 脚本路径 → dirname 取目录 → cd 进去 → pwd 拿绝对路径
#   （先 cd 再 pwd 是为了把相对路径变成绝对路径）
OPENWRT_DIR="${OPENWRT_DIR:-$SCRIPT_DIR/openwrt}"
# ↑ 源码树位置，默认 ./openwrt/
ARTIFACT_DIR="${ARTIFACT_DIR:-$SCRIPT_DIR/artifacts}"
# ↑ 固件产物收集目录，默认 ./artifacts/
PROFILES_CONF="${PROFILES_CONF:-$SCRIPT_DIR/profiles.conf}"
PROFILE_GROUPS_CONF="${PROFILE_GROUPS_CONF:-$SCRIPT_DIR/profile_groups.conf}"
# ↑ 两个配置文件的路径

JOBS="${JOBS:-2}"
# ↑ make 并行线程数。默认 2：WSL 内存不够时 -j8 会在编译 LLVM/Clang 阶段
#   触发 OOM，cc1plus 被系统杀掉（不是代码错误，是内存不够）。
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-8}"
# ↑ 下载并行数。下载是网络 I/O 密集，开大一点没关系。
BUILD_TARGET="${BUILD_TARGET:-${BUILD_PROFILE:-all}}"
# ↑ 要编什么：
#   all            = 编 profile_groups.conf 里的所有分组
#   <分组名>       = 只编一个分组，如 mt7981-ax3000
#   <设备 profile> = 只编一台设备，如 cmcc_rax3000m
#   BUILD_PROFILE 是旧写法，这里做兼容。
```

#### 3.1.2 下载源码

```bash
clone_openwrt() {
  if [ -d "$OPENWRT_DIR/.git" ]; then
    echo "使用已有源码树：$OPENWRT_DIR"
    return
    # ↑ 已经有源码就不重复下载（省几 GB 流量和时间）。
    #   注意：它**不会**自动更新源码，也不会检查本地改动。
  fi

  git init "$OPENWRT_DIR"
  # ↑ 在目标目录建一个空 git 仓库
  git -C "$OPENWRT_DIR" remote add origin "$REPO_URL"
  # ↑ -C 目录 = "在哪个目录里执行 git"，省得反复 cd
  git -C "$OPENWRT_DIR" fetch --depth=1 origin "$REPO_COMMIT"
  # ↑ --depth=1 = 只抓这一个提交，不要几万条历史（下载快非常多）
  git -C "$OPENWRT_DIR" checkout --detach FETCH_HEAD
  # ↑ 切到刚抓下来的提交。--detach = 不挂在任何分支上，
  #   就是"钉死在这个提交"，不会因为分支移动而变化。
}
```

#### 3.1.3 解析配置文件

```bash
read_profiles() {
  awk -F'|' '
    # ↑ -F'|' 表示用竖线 | 作为字段分隔符，所以 $1 是第 1 列、$2 是第 2 列
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    # ↑ 空行 或 # 开头的注释行 → next（跳过这一行）
    NF < 2 { printf("profiles.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
    # ↑ NF = 字段个数。少于 2 列说明格式写错了，立刻报错。
    #   > "/dev/stderr" = 输出到错误流（这样不会混进正常输出被当成数据）
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      # ↑ gsub = 全局替换。把每列开头/结尾的空格和 Tab 去掉。
      if ($1 == "" || $2 == "") { printf("profiles.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
      print $1 "|" $2
      # ↑ 规范化后输出 "设备名|产物目录"
    }
  ' "$PROFILES_CONF"
}
```

```bash
read_groups() {
  awk -F'|' '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    NF < 3 { printf("profile_groups.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
    # ↑ 分组文件至少要有 3 列：分组名|产物目录|设备列表
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      gsub(/^[ \t]+|[ \t]+$/, "", $3)
      if ($1 == "" || $2 == "" || $3 == "") { printf("profile_groups.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
      print $1 "|" $2 "|" $3
      # ↑ 只输出前 3 列（第 4 列的说明文字丢掉，用不上）
    }
  ' "$PROFILE_GROUPS_CONF"
}
```

```bash
resolve_targets() {
  # 把"用户输入的 BUILD_TARGET"翻译成统一的 "分组名|产物目录|设备列表" 格式

  if [ "$BUILD_TARGET" = "all" ]; then
    read_groups
    return
    # ↑ all → 直接输出 profile_groups.conf 里的所有分组
  fi

  local group_line
  # ↑ local = 这个变量只在函数内有效
  group_line="$(read_groups | awk -F'|' -v p="$BUILD_TARGET" '$1 == p { print; found=1 } END { if (!found) exit 1 }' || true)"
  # ↑ 先按"分组名"去找。
  #   -v p="$BUILD_TARGET" ：把 shell 变量传给 awk 用
  #   $1 == p             ：第 1 列等于目标名就打印这一行
  #   END { if (!found) exit 1 } ：一行都没匹配到就返回失败
  #   || true ：因为开头有 set -e，这里要防止"找不到"直接让整个脚本退出
  if [ -n "$group_line" ]; then
    printf '%s\n' "$group_line"
    return
  fi

  local artifact_subdir
  artifact_subdir="$(read_profiles | awk -F'|' -v p="$BUILD_TARGET" '$1 == p { print $2; found=1 } END { if (!found) exit 1 }' || true)"
  # ↑ 不是分组名，就当成"单个设备"去 profiles.conf 找，取第 2 列（产物目录）
  if [ -z "$artifact_subdir" ]; then
    echo "未知的编译目标：$BUILD_TARGET" >&2
    echo "请使用 profile_groups.conf 里的分组名、profiles.conf 里的 profile，或 all。" >&2
    exit 1
  fi
  printf '%s|%s|%s\n' "$BUILD_TARGET" "$artifact_subdir" "$BUILD_TARGET"
  # ↑ 输出 "设备名|产物目录|设备名"：设备列表就是它自己（只编一台）
}
```

#### 3.1.4 主流程

```bash
echo "========================================="
echo "  ImmortalWrt MT798x 25.12 编译"
echo "  源码: $REPO_URL $REPO_BRANCH"
echo "  开始时间: $(date)"
echo "========================================="
# ↑ 打印横幅。$(date) 会先执行 date 命令再拼进字符串。

clone_openwrt
# ↑ 第 1 步：准备源码树

actual_commit="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
# ↑ rev-parse HEAD = 取当前提交号
if [ "$actual_commit" != "$REPO_COMMIT" ]; then
  echo "源码提交为 $actual_commit，尚未审查；预期 $REPO_COMMIT" >&2
  exit 1
fi
# ↑ 第 2 步：确认源码真的在预期提交上。
#   如果本地源码被人改过 / 切过分支，这里直接停下 —— 因为补丁和校验
#   都是针对那个具体版本写的，换了版本可能编出问题固件。

cd "$OPENWRT_DIR"
# ↑ 后面所有命令都在源码树根目录执行（make 必须在这里跑）

bash "$SCRIPT_DIR/01_prepare.sh"
# ↑ 第 3 步：打补丁、更新 feeds、换第三方包、写首启默认设置（详见 3.2）

bash "$SCRIPT_DIR/scripts/validate_fur602.sh" .
# ↑ 第 4 步：检查 FUR602 适配是否都到位（详见 6.5）。
#   参数 "." = 源码树就是当前目录

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
# ↑ 清空并重建产物目录，保证这次的结果不掺上一次的
```

```bash
while IFS='|' read -r target artifact_subdir profiles; do
# ↑ 逐行读 resolve_targets 的输出，按 | 拆成 3 个变量。
#   IFS='|' 是"读入时用什么字符切分"，read -r 表示不处理反斜杠转义。
  echo ""
  echo "========== $target =========="
  echo "开始时间: $(date)"

  bash "$SCRIPT_DIR/05_validate_profile.sh" "$profiles"
  # ↑ 5. 设备名在源码 filogic.mk 里存在吗？（详见 3.6）

  bash "$SCRIPT_DIR/04_make_profile_config.sh" "$profiles" .config
  # ↑ 6. 按模板生成一份全新的 .config（**会覆盖旧的**，详见 3.5）

  bash "$SCRIPT_DIR/02_add_package.sh"
  # ↑ 7. 把 package.conf 里的插件追加进 .config（详见 3.3）

  make defconfig
  # ↑ 8. 让 Kconfig 补全没写的选项的默认值，并丢弃源码里不存在的符号

  bash "$SCRIPT_DIR/06_validate_target_config.sh" "$profiles"
  # ↑ 9. 确认 defconfig 之后设备没被改掉（详见 3.7）

  bash "$SCRIPT_DIR/03_validate_packages.sh"
  # ↑ 10. 确认所有插件真的被启用了（详见 3.4）

  make download -j"$DOWNLOAD_JOBS"
  # ↑ 11. 先把所有第三方源码包下载到 openwrt/dl/

  make -j"$JOBS"
  # ↑ 12. 真正编译。第一次会先编交叉工具链（很久），之后复用。

  profile_artifact_dir="$ARTIFACT_DIR/$target"
  profile_install_dir="$ARTIFACT_DIR/$target-install"
  mkdir -p "$profile_artifact_dir" "$profile_install_dir"

  find "bin/targets/$artifact_subdir" -maxdepth 1 -type f \
    \( -name '*factory*' -o -name '*sysupgrade*' -o -name '*.manifest' \) \
    -exec cp -f {} "$profile_artifact_dir/" \;
  # ↑ 13. 从源码树产物目录里挑出"日常要用"的文件，拷到 artifacts/<组名>/
  #   -maxdepth 1   ：只在第一层找，不进子目录
  #   -type f       ：只要文件，不要目录
  #   \( ... \)     ：括号分组；-o 是"或"。括号要用 \ 转义，否则被 shell 吃掉
  #   -name '*xxx*' ：文件名里包含 xxx
  #   -exec cp -f {} 目标 \; ：对每个找到的文件执行 cp，{} 代表文件名
  #   manifest 是"这个固件里装了哪些包"的清单，不是刷机文件，但很有用

  (
    cd "$profile_artifact_dir"
    find . -maxdepth 1 -type f ! -name sha256sums -printf '%P\0' | sort -z | xargs -0 sha256sum > sha256sums
  )
  # ↑ 14. 生成 sha256sums 校验文件（刷机前可以核对固件有没有损坏）。
  #   ( ... )        ：子 shell，里面的 cd 不会影响外面
  #   ! -name        ：排除 sha256sums 自己
  #   -printf '%P\0' ：只输出相对路径，用 \0（NUL 字节）分隔。
  #                    用 NUL 而不是换行，是为了兼容文件名里有空格的情况
  #   sort -z / xargs -0 ：配套使用，同样按 NUL 分隔
  #   sha256sum > sha256sums ：把每个文件的哈希写进 sha256sums

  find "bin/targets/$artifact_subdir" -maxdepth 1 -type f \
    \( -name '*initramfs*' -o -name '*recovery*' -o -name '*preloader*' -o -name '*bl31*' -o -name '*fip*' -o -name '*gpt*' \) \
    -exec cp -f {} "$profile_install_dir/" \;
  # ↑ 15. 另一类文件：只有"首次刷机 / 救砖 / 换启动链"才用得到，
  #   单独放 -install 目录，避免你平时升级时手滑刷错。

  if find "$profile_install_dir" -maxdepth 1 -type f | grep -q .; then
    # ↑ 如果这个目录里真的有文件（grep -q . 表示"有任意输出"）
    cat > "$profile_install_dir/README-install.zh-CN.txt" <<'EOF'
这个目录只用于新刷、救援或更换启动链。
日常升级请使用普通目录里的 sysupgrade 文件，不要随便刷 preloader、FIP、GPT 或 recovery。
刷写启动链前必须备份原厂分区，尤其是 Factory/factory 校准分区。
EOF
    # ↑ <<'EOF' 是 heredoc（多行文本），单引号包住 EOF 表示里面的内容不做变量展开
    (
      cd "$profile_install_dir"
      find . -maxdepth 1 -type f ! -name sha256sums -printf '%P\0' | sort -z | xargs -0 sha256sum > sha256sums
    )
  else
    rmdir "$profile_install_dir"
    # ↑ 没有这类文件（很多设备没有 recovery），就把空目录删掉
  fi

  count="$(find "$profile_artifact_dir" -type f | wc -l)"
  # ↑ wc -l = 数行数 = 文件个数
  if [ "$count" -eq 0 ]; then
    echo "没有为 $target 收集到产物" >&2
    exit 1
    # ↑ 编译"成功"了却一个产物都没有 = 肯定有问题，必须报错而不是假装成功
  fi

  echo "完成 $target：$count 个文件"
done < <(resolve_targets)
# ↑ < <(...) 是"进程替换"：把 resolve_targets 的输出当成一个临时文件喂给 while 读。
#   这样写 while 不是在子 shell 里，循环内的变量改动能保留。

echo ""
echo "========================================="
echo "  全部完成：$(date)"
echo "========================================="
find "$ARTIFACT_DIR" -mindepth 1 -maxdepth 2 -type f | sort
du -sh "$ARTIFACT_DIR"
# ↑ 最后列出所有产物文件和总大小
```

**用法**：

```bash
bash build_all.sh                              # 编全部分组（很慢）
BUILD_TARGET=mt7981-ax3000 bash build_all.sh   # 只编一个分组
BUILD_TARGET=cmcc_rax3000m bash build_all.sh   # 只编一台设备
JOBS=1 bash build_all.sh                       # 内存小的时候
```

---

### 3.2 `01_prepare.sh`（准备源码）

**作用**：这是整个流程里"魔改"最多的一步 —— 打补丁、更新 feeds、替换第三方包、
写首启默认设置。**每次编译只跑一次**（在分组循环之前）。

```bash
#!/bin/bash
set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$(pwd)}"
# ↑ 源码树位置，默认"当前目录"（因为调用方已经 cd 到 openwrt/ 了）
SCUTCLIENT_COMMIT="d9d618be97870813252b5ce7540f6a4ea4c22ab0"
# ↑ 校园网 LuCI 插件锁定的上游提交（这个版本已经被验证过能配我们的补丁）
DOWNLOAD_PATCH="$SCRIPT_DIR/patches/2512/build-system/download-reliability.patch"

cd "$OPENWRT_DIR"
```

#### 3.2.1 应用下载可靠性补丁（可重复执行）

```bash
if git apply --reverse --check "$DOWNLOAD_PATCH" >/dev/null 2>&1; then
  echo "下载器可靠性补丁已经应用。"
  # ↑ --reverse --check = "试试反向撤销这个补丁，看行不行"。
  #   能反向撤销 → 说明它已经打过了 → 跳过，避免重复打补丁报错。
  #   >/dev/null 2>&1 = 把正常输出和错误输出都丢掉（这里只关心退出码）
elif git apply --check "$DOWNLOAD_PATCH"; then
  git apply "$DOWNLOAD_PATCH"
  echo "已应用下载器可靠性补丁。"
  # ↑ 正向检查能通过 → 说明没打过且能干净地打上 → 打它
else
  echo "错误：下载器可靠性补丁与当前源码不匹配。" >&2
  exit 1
  # ↑ 两种情况都不成立 = 源码变了、补丁打不上了 → 必须人工处理，别硬来
fi

for patch_script in "$SCRIPT_DIR"/patches/2512/*.sh; do
  [ -e "$patch_script" ] || continue
  bash "$patch_script" "$OPENWRT_DIR"
done
# ↑ 把 patches/2512/ 下所有 .sh 依次执行。
#   目前只有一个：0001-add-honor-fur-602.sh（把 FUR602 加进源码，见 6.2）。
#   每个脚本内部都会自己检查"是不是已经加过了"，所以可以重复执行。
```

#### 3.2.2 更新 feeds、替换第三方包

```bash
./scripts/feeds update -a
# ↑ 把所有 feeds（额外软件包源）拉取/更新到最新。
#   ⚠️ 注意：源码树固定在某个 commit，但 feeds 是**滚动更新**的。
#   这意味着插件版本会随时间变化 —— 好处是能拿到新功能，
#   代价是上游改动可能让某些包编不过（这时候就是 01_prepare 里的适配要跟着改）。

rm -rf package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
# ↑ 把 Argon 主题从官方仓库直接克隆到 package/ 下。
#   先 rm 是为了避免残留旧版本；克隆到 package/ 下意味着它会被当成"本地包"编译，
#   不受 feeds 版本影响。

rm -rf feeds/luci/applications/luci-app-scutclient
git clone https://github.com/hanwckf/luci-app-scutclient.git feeds/luci/applications/luci-app-scutclient
# ↑ 用 hanwckf 的版本替换 feeds 自带的校园网插件
git -C feeds/luci/applications/luci-app-scutclient checkout --detach "$SCUTCLIENT_COMMIT"
# ↑ 钉死到验证过的提交
[ "$(git -C feeds/luci/applications/luci-app-scutclient rev-parse HEAD)" = "$SCUTCLIENT_COMMIT" ]
# ↑ 再确认一次真的切过去了（切不过去就报错退出）
git -C feeds/luci/applications/luci-app-scutclient apply \
  "$SCRIPT_DIR/patches/2512/luci-app-scutclient-modern-luci.patch"
# ↑ 打上新 LuCI 兼容补丁（见 6.4）
bash "$SCRIPT_DIR/scripts/validate_scutclient.sh" \
  feeds/luci/applications/luci-app-scutclient/luasrc/controller/scutclient.lua
# ↑ 打完后立刻校验补丁内容真的生效了（见 6.6）
```

```bash
rm -rf package/scut-unicom
mkdir -p package/scut-unicom
wget --tries=5 --timeout=30 \
  https://raw.githubusercontent.com/wykdg/route_script/master/scut-unicom/Makefile \
  -O package/scut-unicom/Makefile
# ↑ 联通校园网加速脚本只有一个 Makefile 在 GitHub 上，直接下载过来当成一个本地包。
#   --tries=5 --timeout=30 = 重试 5 次、每次 30 秒超时

sed -i \
  -e 's#^PKG_RELEASE:=$(shell date "+%Y-%m-%d")#PKG_VERSION:=$(shell date "+%Y%m%d")\nPKG_RELEASE:=1#' \
  -e 's#^  VERSION:=$(PKG_RELEASE)#  VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)#' \
  package/scut-unicom/Makefile
# ↑ 改写 Makefile 里的版本号写法。
#   背景：上游用 PKG_RELEASE = 2026-07-04 这种带横杠的日期，但 25.12 的包管理器
#   APK 不接受横杠，会直接报错编不过。
#   改成：PKG_VERSION=20260704（纯数字）+ PKG_RELEASE=1（固定）。
#   sed 语法：s#原内容#新内容# ，用 # 当分隔符是因为内容里有很多 /
#   -e 可以写多组替换。\n 表示换行。
```

#### 3.2.3 修 OpenVPN Server 的配置冲突

```bash
openvpn_server_dir="feeds/luci/applications/luci-app-openvpn-server"
if [ -d "$openvpn_server_dir" ]; then
  rm -f "$openvpn_server_dir/root/etc/config/openvpn"
  # ↑ 这个插件自带一份 /etc/config/openvpn，会和 openvpn-openssl 包自带的
  #   同名文件冲突（两个包都想装同一个文件，编译时直接报错）。
  #   所以删掉它，改用下面的 uci-defaults 方式在首启时初始化。

  openvpn_defaults="$openvpn_server_dir/root/etc/uci-defaults/openvpn"
  # ↑ uci-defaults 目录：里面的脚本在系统**首次启动时执行一次**，然后自动删除。
  #   这是 OpenWrt 里写"出厂默认配置"的标准位置。

  if [ -f "$openvpn_defaults" ] && ! grep -q "openvpn.myvpn=openvpn" "$openvpn_defaults"; then
    # ↑ 如果这个文件存在、并且还没有我们的配置段，就补进去
    tmp_file="$(mktemp)"
    {
      cat <<'EOF'
if ! uci -q get openvpn.myvpn >/dev/null; then
uci -q batch <<-'EOF_UCI' >/dev/null
	set openvpn.myvpn=openvpn
	set openvpn.myvpn.enabled='0'
	...
	commit openvpn
EOF_UCI
fi

EOF
      cat "$openvpn_defaults"
    } > "$tmp_file"
    # ↑ { 命令1; 命令2; } > 文件  = 把多条命令的输出合并写入同一个文件。
    #   先写我们的默认配置块，再原样接上文件原有内容。
    #   最外层 heredoc 用 'EOF'（带引号）= 内容不做变量展开。
    #   内层嵌套的 heredoc 用 'EOF_UCI'，注意内层结束标记必须顶格写。
    #   uci -q batch <<-'EOF_UCI' ：<<- 表示允许结束标记前有 Tab 缩进
    cat "$tmp_file" > "$openvpn_defaults"
    rm -f "$tmp_file"
    # ↑ 用临时文件再覆盖回去（不能直接边读边写同一个文件）
  fi
fi
```

> `uci` 是 OpenWrt 的配置命令行工具。`set openvpn.myvpn=openvpn` = 在
> `/etc/config/openvpn` 里建一个名为 `myvpn` 的 `openvpn` 类型配置段；
> 后面的 `set openvpn.myvpn.xxx='yyy'` 就是给这个段加选项；
> `commit` = 保存。`enabled='0'` 表示默认不启动，避免空配置白占内存。

#### 3.2.4 移除 Tailscale、安装 feeds、写首启脚本

```bash
rm -rf package/luci-app-tailscale
# ↑ 删掉可能残留的第三方 Tailscale 插件。
#   原因：Tailscale 没配置也会自动启动 tailscaled，FUR602 内存小扛不住。
#   03_validate_packages.sh 还会再检查一次，确保它没被编进去。

./scripts/feeds install -a
# ↑ 把更新好的 feeds 里所有包"安装"（实际是软链接）到 package/feeds/，
#   这样 make menuconfig 才能看到它们。
#   ⚠️ 必须在替换第三方包**之后**执行，否则 feeds 会把你替换掉的包又装回来。

# Passwall 需要 haproxy 二进制，但系统自带的示例服务不应在首启时常驻。
haproxy_defaults="package/base-files/files/etc/uci-defaults/99-disable-unused-haproxy"
mkdir -p "$(dirname "$haproxy_defaults")"
# ↑ 直接往源码树的 base-files 包里塞一个首启脚本，
#   这样它会出现在固件的 /etc/uci-defaults/ 里。
cat > "$haproxy_defaults" <<'EOF'
#!/bin/sh

if [ -x /etc/init.d/haproxy ]; then
	/etc/init.d/haproxy disable
	/etc/init.d/haproxy stop
fi

exit 0
EOF
chmod 0755 "$haproxy_defaults"
# ↑ chmod 0755 = 让脚本可执行（uci-defaults 里的脚本必须有执行权限）
```

```bash
if [ -f package/base-files/files/etc/rc.local ] && \
   ! grep -q 'scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local; then
  sed -i '/^exit 0/i # 如果要使用联通加速，取消下一行注释并填好参数\n#sleep 10 && /usr/share/scut_unicom/add_route.sh server_ip username password' \
    package/base-files/files/etc/rc.local
fi
# ↑ 往 /etc/rc.local（开机自启脚本）里，在 "exit 0" 这行**前面**插入两行注释，
#   提示你以后想用联通加速该怎么写。
#   sed 的 i 命令 = insert，在匹配行之前插入。
```

```bash
ttyd_config="feeds/packages/utils/ttyd/files/ttyd.config"
if [ -f "$ttyd_config" ]; then
  sed -i "s#option command '/bin/login'#option command '/bin/login -f root'#" "$ttyd_config"
fi
# ↑ ttyd 是网页版终端。默认登录要输用户名，改成 -f root 直接以 root 登录。
#   （这是你自己家里的路由器，方便优先。）
```

```bash
default_settings="package/emortal/default-settings/files/99-default-settings"
if [ -f "$default_settings" ] && ! grep -q 'trojan-go' "$default_settings"; then
  sed -i "s#exit 0#[ ! -f '/usr/sbin/trojan' ] \\&\\& [ -f '/usr/bin/trojan-go' ] \\&\\& ln -sf /usr/bin/trojan-go /usr/bin/trojan\\nexit 0#" "$default_settings"
fi
# ↑ 有些插件调用的是 trojan 这个名字，但 25.12 里装的是 trojan-go。
#   首启时做个软链接：如果 /usr/sbin/trojan 不存在、而 /usr/bin/trojan-go 存在，
#   就创建 /usr/bin/trojan → trojan-go。
#
#   转义说明（很容易看晕，拆开看）：
#   shell 双引号里 \\&  → 实际传给 sed 的是 \&
#   sed 替换内容里 & 有特殊含义（代表"匹配到的整段"），要写成 \& 才是字面量 &
#   所以 \\&\\& 最终在文件里产生 &&
#   \\n 同理 → sed 看到 \n → 输出换行
```

---

### 3.3 `02_add_package.sh`（把插件写进 .config）

**作用**：读 `package.conf`，把每一行变成一个 `CONFIG_PACKAGE_xxx=y` 追加到 `.config`。
这是你"加插件"的入口脚本。

```bash
#!/bin/bash
set -e -o pipefail

CONFIG_FILE="${CONFIG_FILE:-.config}"
# ↑ 要写入的配置文件，默认当前目录的 .config（也就是 openwrt/.config）
PACKAGE_CONF="${PACKAGE_CONF:-../package.conf}"
# ↑ 插件清单，默认上一层目录的 package.conf

declare -A seen=()
# ↑ 关联数组（类似 C++ 的 unordered_map），用来查重：seen["包名"]=1 表示见过

while IFS= read -r pkg || [ -n "$pkg" ]; do
# ↑ 逐行读。|| [ -n "$pkg" ] 是为了兼容"最后一行没有换行符"的文件。

  pkg="${pkg%$'\r'}"
  # ↑ 去掉行尾的 \r。如果 package.conf 是 Windows 换行（CRLF），
  #   \r 会被一起读进来，导致包名变成 "luci-app-sqm\r" 而匹配失败。

  pkg="${pkg%%#*}"
  # ↑ 从第一个 # 开始全部截掉，所以支持 "包名 # 我的备注" 这种写法。

  pkg="${pkg#"${pkg%%[![:space:]]*}"}"
  pkg="${pkg%"${pkg##*[![:space:]]}"}"
  # ↑ 这两行是 bash 里"去掉首尾空白"的经典写法（等价于其他语言的 trim）：
  #   ${pkg%%[![:space:]]*} = 从开头到第一个非空白字符，即"开头的空白"
  #   ${pkg#前缀}           = 删掉这个前缀
  #   第二行同理处理结尾。

  [ -z "$pkg" ] && continue
  # ↑ 空行跳过

  if [[ "$pkg" =~ [[:space:]] ]] || ! [[ "$pkg" =~ ^[A-Za-z0-9_.+@-]+$ ]]; then
    echo "package.conf 条目格式无效：'$pkg'" >&2
    exit 1
  fi
  # ↑ 包名里不能有空格；只允许字母、数字和 _ . + @ -
  #   写错了立刻报错，而不是让 make 默默忽略（默默忽略最坑人）

  if [[ -n "${seen[$pkg]:-}" ]]; then
    echo "package.conf 条目重复：'$pkg'" >&2
    exit 1
  fi
  seen[$pkg]=1
  # ↑ 查重，重复就报错

  echo "CONFIG_PACKAGE_${pkg}=y"
  # ↑ 输出一行 Kconfig 配置：
  #   CONFIG_PACKAGE_luci-app-sqm=y  →  编译时把 luci-app-sqm 装进固件
done < "$PACKAGE_CONF" >> "$CONFIG_FILE"
# ↑ 整个循环的输出（stdout）被追加到 .config 末尾
```

**手动运行**：

```bash
cd openwrt
bash ../02_add_package.sh          # 默认写 .config
```

---

### 3.4 `03_validate_packages.sh`（检查插件真的启用了）

**作用**：`make defconfig` 之后，确认 `package.conf` 里每个包**真的**被启用了。
为什么需要？因为包名写错、或者依赖不满足时，Kconfig 会**静默地**不启用它 ——
你以为装了，刷完发现没有。

```bash
#!/bin/bash
set -e -o pipefail

CONFIG_FILE="${CONFIG_FILE:-.config}"
PACKAGE_CONF="${PACKAGE_CONF:-../package.conf}"

fail() {
  echo "软件包校验失败：$*" >&2
  exit 1
}
# ↑ $* = 所有参数拼成一个字符串

require_enabled() {
  grep -Fqx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE" || fail "缺少 $1"
}
# ↑ grep 参数含义：
#   -F 把模式当普通字符串（不当正则，包名里有 . + 时很关键）
#   -q 安静模式，只返回退出码不打印
#   -x 整行必须完全匹配（防止 CONFIG_PACKAGE_foo 误匹配 CONFIG_PACKAGE_foo-bar）
#   找不到 → grep 返回非 0 → || 触发 fail

require_disabled() {
  ! grep -Fqx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE" || fail "$1 不应被选中"
  ! grep -Fqx "CONFIG_PACKAGE_$1=m" "$CONFIG_FILE" || fail "$1 不应被选中"
}
# ↑ 逻辑：grep 找到了 → ! 取反 → 假 → || 不触发 → 通过；
#        grep 没找到 → ! 取反 → 真 → || 触发 fail。
#   同时检查 =y（编进固件）和 =m（编成可安装的包）两种形式。

find_enabled() {
  local package
  for package in "$@"; do
    if grep -Fqx "CONFIG_PACKAGE_$package=y" "$CONFIG_FILE"; then
      printf '%s\n' "$package"
      return 0
    fi
  done
  return 1
}
# ↑ 在一组候选包里找第一个启用的，打印出来并返回成功；一个都没有则失败。
#   用途：tc 有 tc / tc-tiny / tc-full 三种，只要有任意一个就行。

[ -f "$CONFIG_FILE" ] || fail "缺少配置文件 $CONFIG_FILE"

missing=()
requested=0
# ↑ 数组 + 计数器

while IFS= read -r pkg || [ -n "$pkg" ]; do
  pkg="${pkg%$'\r'}"                        # 去 CRLF
  pkg="${pkg%%#*}"                          # 去注释
  pkg="${pkg#"${pkg%%[![:space:]]*}"}"      # trim 左
  pkg="${pkg%"${pkg##*[![:space:]]}"}"      # trim 右
  [ -z "$pkg" ] && continue
  ((requested += 1))
  # ↑ (( )) 是 bash 的算术运算语法

  if ! grep -Fqx "CONFIG_PACKAGE_${pkg}=y" "$CONFIG_FILE"; then
    missing+=("$pkg")
    # ↑ 没启用的记到 missing 数组里
  fi
done < "$PACKAGE_CONF"

if (( ${#missing[@]} > 0 )); then
  echo "make defconfig 后，下面这些请求的包没有被启用：" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "请检查包名、ImmortalWrt 25.12 分支支持情况和依赖关系。" >&2
  exit 1
fi
# ↑ ${#missing[@]} = 数组长度

require_enabled luci-app-sqm
require_enabled sqm-scripts
require_enabled kmod-sched-cake
require_enabled kmod-ifb
require_enabled iptables-mod-ipopt
# ↑ SQM（智能队列管理，用来解决"下载时游戏卡顿"）需要这一组包一起才生效

tc_provider="$(find_enabled tc tc-tiny tc-full || true)"
[ -n "$tc_provider" ] || fail "缺少 tc、tc-tiny 或 tc-full"
# ↑ tc 是流量控制工具，SQM 依赖它，三种实现有任意一种就行

iptables_provider="$(find_enabled iptables iptables-nft iptables-legacy || true)"
[ -n "$iptables_provider" ] || fail "缺少 iptables、iptables-nft 或 iptables-legacy"

require_disabled luci-app-tailscale
require_disabled luci-app-tailscale-community
require_disabled tailscale
# ↑ 确保 Tailscale 无论从哪个包名都进不来（占内存）

echo "已验证 $requested 个请求的包：SQM 及其依赖已启用（tc: $tc_provider，iptables: $iptables_provider），Tailscale 已移除。"
```

---

### 3.5 `04_make_profile_config.sh`（生成 .config）

**作用**：按模板生成一份**全新的** `.config`。⚠️ 它会**整个覆盖**已有的 `.config`。

```bash
#!/bin/bash
set -e -o pipefail

profiles_input="${1:-}"
# ↑ 第 1 个参数：设备列表（可以用逗号或空格分隔）
config_file="${2:-.config}"
# ↑ 第 2 个参数：输出文件名，默认 .config

if [ -z "$profiles_input" ]; then
  echo "用法：$0 <device-profile...> [config-file]" >&2
  exit 1
fi

read_profiles() {
  printf '%s\n' "$profiles_input" | tr ',' ' ' | xargs -n1
  # ↑ tr ',' ' '   ：把逗号换成空格
  #   xargs -n1    ：每个参数单独输出一行
  #   效果："a,b c" → a / b / c 各一行
}

mapfile -t profiles < <(read_profiles)
# ↑ mapfile -t 把输入按行读进数组 profiles（-t 去掉行尾换行）
if [ "${#profiles[@]}" -eq 0 ]; then
  echo "没有可写入配置的设备 profile" >&2
  exit 1
fi

multi_profile=n
if [ "${#profiles[@]}" -gt 1 ]; then
  multi_profile=y
fi
# ↑ 设备数 > 1 就用"多设备模式"
```

```bash
cat > "$config_file" <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_MULTI_PROFILE=$multi_profile
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
# ↑ 注意这里是 <<EOF（没加引号），所以 $multi_profile 会被 shell 替换成 y 或 n。
#   如果写成 <<'EOF'，$multi_profile 就会原样留在文件里 —— 这是个常见坑。
```

逐行含义：

| 配置行 | 含义 |
|---|---|
| `CONFIG_TARGET_mediatek=y` | 选联发科平台 |
| `CONFIG_TARGET_mediatek_filogic=y` | 选 filogic 子平台（MT7981/7986） |
| `CONFIG_TARGET_MULTI_PROFILE=y/n` | 是否"一次编多台设备"。开了之后各组共享工具链，快很多 |
| `CONFIG_TARGET_SQUASHFS_XZ=y` | 用 xz 压缩 squashfs，固件体积明显变小（解压稍慢一点点） |
| `CONFIG_PACKAGE_luci=y` | 带上 LuCI 网页管理界面 |
| `CONFIG_LUCI_LANG_zh_Hans=y` | 简体中文语言包 |
| `CONFIG_IMAGEOPT=y` | 允许自定义镜像选项（下面那些 VERSION_* 才生效） |
| `CONFIG_VERSIONOPT=y` | 允许自定义版本信息 |
| `CONFIG_VERSION_DIST="ImmortalWrt"` | 发行版名字（显示在 LuCI 首页 / `/etc/openwrt_release`） |
| `CONFIG_VERSION_NUMBER="25.12"` | 版本号 |
| `CONFIG_VERSION_REPO="..."` | 固件里默认的软件源地址（apk 装插件时用） |
| `CONFIG_VERSION_HOME_URL` / `SUPPORT_URL` / `BUG_URL` | LuCI 上显示的官网/支持/报错链接 |

```bash
for profile in "${profiles[@]}"; do
  if [ "$multi_profile" = "y" ]; then
    echo "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${profile}=y" >> "$config_file"
    echo "CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_${profile}=\"\"" >> "$config_file"
  else
    echo "CONFIG_TARGET_mediatek_filogic_DEVICE_${profile}=y" >> "$config_file"
  fi
done
# ↑ 写设备选择。
#
# 【关键】单设备 vs 多设备的 Kconfig 符号名不一样：
#   单设备：CONFIG_TARGET_mediatek_filogic_DEVICE_<profile>=y
#   多设备：CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_<profile>=y
#           （注意中间多了一个 TARGET_DEVICE_ 前缀）
#   名字写错的话，Kconfig 不会报错，而是**静默回退到默认设备**，
#   编出来的固件刷到你机器上可能直接变砖 —— 这就是 06 脚本存在的原因。
#
# CONFIG_TARGET_DEVICE_PACKAGES_...="" 表示"这台设备不要额外附加软件包"。
# 注意：设备自己的 DEVICE_PACKAGES（比如 Wi-Fi 驱动）不在这里，
#       那些写在源码 filogic.mk 的设备定义里，不受这一行影响。
```

---

### 3.6 `05_validate_profile.sh`（检查设备名存在）

**作用**：在动手编译之前，先确认你要编的 `profile` 在源码里真的有定义。
因为 `04` 生成的配置里如果写了个不存在的设备名，`defconfig` 会静默换成别的设备。

```bash
#!/bin/bash
set -e -o pipefail

profiles_input="${1:-}"
image_makefile="${2:-target/linux/mediatek/image/filogic.mk}"
# ↑ 第 2 个参数是设备定义文件，默认是 filogic.mk

if [ -z "$profiles_input" ]; then
  echo "用法：$0 <device-profile...> [filogic.mk]" >&2
  exit 1
fi

if [ ! -f "$image_makefile" ]; then
  echo "缺少镜像 Makefile：$image_makefile" >&2
  exit 1
fi

read_profiles() {
  printf '%s\n' "$profiles_input" | tr ',' ' ' | xargs -n1
}

mapfile -t profiles < <(read_profiles)
for profile in "${profiles[@]}"; do
  if ! grep -Fqx "define Device/${profile}" "$image_makefile"; then
    # ↑ 在 filogic.mk 里找一行完全等于 "define Device/<设备名>" 的内容
    echo "未知的 mediatek/filogic 设备 profile：$profile" >&2
    echo "可以在 openwrt 源码树中运行下面命令列出 profile：" >&2
    echo "  grep -E '^define Device/' target/linux/mediatek/image/filogic.mk | sed 's/^define Device\\///'" >&2
    # ↑ 这句提示很有用：直接给你一条能列出所有可用设备名的命令
    exit 1
  fi
done

echo "已验证 ${#profiles[@]} 个 profile：${profiles[*]}"
```

**自己查有哪些可用设备名**：

```bash
cd openwrt
grep -E '^define Device/' target/linux/mediatek/image/filogic.mk | sed 's/^define Device\///'
```

---

### 3.7 `06_validate_target_config.sh`（检查设备没被改掉）

**作用**：`make defconfig` 之后，确认你选的设备**仍然是**你选的那个。
这是防止"编错机型"的最后一道闸门。

```bash
#!/bin/bash
set -e -o pipefail

profiles_input="${1:-}"
config_file="${2:-.config}"

... 参数检查 / read_profiles / mapfile 同 05 ...

multi_profile=n
if [ "${#profiles[@]}" -gt 1 ]; then
  multi_profile=y
fi

for profile in "${profiles[@]}"; do
  if [ "$multi_profile" = "y" ]; then
    expected="CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${profile}=y"
  else
    expected="CONFIG_TARGET_mediatek_filogic_DEVICE_${profile}=y"
  fi
  # ↑ 期望的配置行，和 04 脚本写进去的必须一致

  if ! grep -Fqx "$expected" "$config_file"; then
    echo "make defconfig 后目标 profile 没有被启用：$profile" >&2
    echo "期望配置行：$expected" >&2
    selected="$(grep -E '^(CONFIG_TARGET_mediatek_filogic_DEVICE_|CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_).+=y$' "$config_file" || true)"
    if [ -n "$selected" ]; then
      echo "当前选中的 profile 行：" >&2
      echo "$selected" >&2
      # ↑ 把"实际选中的是谁"打印出来，方便你对比 —— 通常就是符号名写错了
    fi
    exit 1
  fi
done

echo "已验证选中的 ${#profiles[@]} 个目标 profile：${profiles[*]}"
```

---

## 4. 配置文件详解

### 4.1 `profiles.conf`（设备清单）

```text
# profile|artifact-dir|description
# 每行一个 profile。profile 名称必须匹配 ImmortalWrt 25.12
# target/linux/mediatek/image/filogic.mk 里的 Device/<profile>。

# MT7981 / AX3000 级别设备
cmcc_rax3000m|mediatek/filogic|CMCC RAX3000M
honor_fur-602|mediatek/filogic|HONOR FUR-602/603（本仓库适配）
...
```

| 列 | 含义 |
|---|---|
| 第 1 列 `profile` | 设备名，**必须**和源码 `filogic.mk` 里的 `define Device/<名字>` 完全一致 |
| 第 2 列 `artifact-dir` | 产物在 `openwrt/bin/targets/` 下的子目录，目前都是 `mediatek/filogic` |
| 第 3 列 `description` | 人看的说明，脚本不用 |

- `#` 开头的行是注释，空行忽略。
- **加设备**：加一行即可，但前提是源码里已经有这个 Device。
- 这个文件只影响"单独编译某台设备"（`BUILD_TARGET=<设备名>`），
  GitHub Actions 的 `custom` 模式也会来查它。

### 4.2 `profile_groups.conf`（编译分组）

```text
# group|artifact-dir|profiles|description
mt7981-ax3000|mediatek/filogic|cmcc_rax3000m cmcc_rax3000me ... konka_komi-a31|MT7981 / AX3000 级别设备
```

| 列 | 含义 |
|---|---|
| 第 1 列 `group` | 分组名，`BUILD_TARGET=<这个名字>` 就是编这一组 |
| 第 2 列 `artifact-dir` | 同上 |
| 第 3 列 `profiles` | 组内设备列表，**空格分隔** |
| 第 4 列 `description` | 说明文字（`build_all.sh` 会丢掉，workflow 也不用） |

**为什么要分组？** OpenWrt 编译最耗时的部分是工具链和内核。
把同一代的设备（比如所有 MT7981）放在一次 `make` 里，它们共享工具链，
比"每台设备单独编一遍"快几倍。

**注意**：组内所有设备的固件会一起产出。组太大 → 编译时间长、磁盘占用大。

### 4.3 `package.conf`（插件清单）

```text
# 代理客户端和核心
luci-app-openclash
luci-app-passwall
luci-app-passwall_INCLUDE_Xray
...
# 常用可选插件（删除行首 # 即可启用）
# luci-app-nlbwmon
# luci-app-wol
```

规则：

- 一行一个包名，**不要**写 `CONFIG_PACKAGE_` 前缀，**不要**写 `=y`。
- `#` 开头的行被忽略 → 所以"临时禁用某插件"就是在行首加 `#`。
- 行尾也可以加 `# 备注`。
- 不能有空格、不能重复（`02_add_package.sh` 会检查并报错）。

**25.12 的包名和 23.05 有差异，容易踩坑**：

| 想要的功能 | 25.12 里正确的包名 |
|---|---|
| WireGuard 的 LuCI 界面 | `luci-proto-wireguard` |
| socat | `socat`（直接选它） |
| Passwall 的 Xray / Hysteria2 / SingBox 支持 | `luci-app-passwall_INCLUDE_Xray` 等（这是 Passwall 的子选项） |
| TUIC | Passwall 26.7.1 **没有**独立的 `INCLUDE_tuic_client`，通过 Sing-Box 支持 |

**怎么查一个包的正确名字**：

```bash
cd openwrt
# 方法 1：从 feeds 列表里找关键字
./scripts/feeds list -r | grep -i 关键字

# 方法 2：在 Kconfig 生成的清单里找（跑过一次 make defconfig 后才有）
grep -i "关键字" tmp/.config-package.in | head

# 方法 3：图形菜单里搜索（在 menuconfig 里按 "/" 然后输入关键字）
make menuconfig
```

### 4.4 根目录的 `.config`

```text
CONFIG_TARGET_mediatek=y
...
CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m=y
```

这是 `04` 脚本为**单个设备**（`cmcc_rax3000m`）生成的一份样例，留在这里当参考。
编译时**不会用到它** —— 真正生效的是 `openwrt/.config`。
（如果你好奇某个配置项长什么样，可以看它，但改了没用。）

### 4.5 `.gitattributes`

```text
*.sh text eol=lf
*.py text eol=lf
*.yml text eol=lf
*.conf text eol=lf
*.dts text eol=lf
*.patch text eol=lf
*.md text eol=lf
.gitattributes text eol=lf
.gitignore text eol=lf
```

强制这些文件在 git 里用 **LF**（Unix）换行，而不是 Windows 的 CRLF。
**为什么重要**：脚本第一行是 `#!/bin/bash`，如果变成 `#!/bin/bash\r`，
Linux 会去找一个叫 `bash\r` 的解释器，报错 `bad interpreter: No such file or directory`。
而且 `03_validate_packages.sh` 里用 `grep -Fqx` 整行匹配，行尾多个 `\r` 也会导致匹配失败。

### 4.6 `.gitignore`

```text
openwrt/      # 源码树（几十 GB，不入库）
artifacts/    # 编译产物
logs/
*.7z          # 压缩后的固件包
*.tar
*.tar.gz
__pycache__/
*.pyc
```

---

## 5. GitHub Actions 工作流详解

文件：`.github/workflows/mt798x.yml`。这是你**平时最常用**的编译方式。

### 5.1 头部

```yaml
name: MT798x 25.12 手动编译
run-name: MT798x 25.12 - ${{ inputs.build_target || 'mt7981-ax3000' }}
# ↑ 每次运行在 Actions 列表里显示的名字

env:
  REPO_URL: https://github.com/immortalwrt/immortalwrt.git
  REPO_BRANCH: openwrt-25.12
  REPO_COMMIT: 1cfeb3edade40fe2dfec59c21381de1d8e361100
# ↑ 和 build_all.sh 里的三个变量一一对应（源码仓库/分支/锁定提交）
```

### 5.2 触发方式与权限

```yaml
on:
  workflow_dispatch:
    inputs:
      build_target:
        description: 要编译的分组或设备 profile
        required: true
        default: mt7981-ax3000
        type: string
      custom_profile:
        description: 仅在 build_target 为 custom 时使用
        required: false
        type: string
# ↑ workflow_dispatch = 只能手动点按钮触发。
#   这是故意的：不会因为你 push 代码就自动开编（避免浪费额度）。
#   两个输入框：build_target（编什么）和 custom_profile（自定义设备名）

permissions:
  contents: write
# ↑ 需要写权限才能创建 Release。
#   如果 Release 建不出来，去仓库 Settings > Actions > General >
#   Workflow permissions 选 "Read and write permissions"。
```

### 5.3 第一个 job：生成编译矩阵

```yaml
jobs:
  prepare-matrix:
    runs-on: ubuntu-22.04
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
    # ↑ 这个 job 只干一件事：算出"要开几个编译任务"，输出给下一个 job
    steps:
      - name: 拉取本仓库
        uses: actions/checkout@v5

      - name: 生成编译矩阵
        id: matrix
        env:
          BUILD_TARGET: ${{ inputs.build_target || 'mt7981-ax3000' }}
          CUSTOM_PROFILE: ${{ inputs.custom_profile }}
        run: |
          set -e -o pipefail
          selected="$BUILD_TARGET"
          if [ "$selected" = "custom" ]; then
            selected="$CUSTOM_PROFILE"
            if [ -z "$selected" ]; then
              echo "build_target=custom 时必须填写 custom_profile" >&2
              exit 1
            fi
          fi
          # ↑ custom 模式下，真正的目标名从 custom_profile 取
          ...
          # ↑ 后面几段是纯 awk：读 profile_groups.conf / profiles.conf，
          #   拼出一段 JSON，形如：
          #   {"include":[{"target":"mt7981-ax3000","artifact_subdir":"mediatek/filogic","profiles":"..."}]}
          #   这段 JSON 就是"矩阵"：include 里有几项，就会开几个并行编译 job。
```

三种输入对应的行为：

| 输入 | 行为 |
|---|---|
| `all` | 展开 `profile_groups.conf` 里的**所有**分组，每个分组一个并行 job |
| `<分组名>` | 只展开这一个分组 |
| `<设备名>` | 去 `profiles.conf` 查它的产物目录，单个 job 编这一台 |
| `custom` + `custom_profile=<设备名>` | 同上，用于"没写进 profiles.conf 但源码里有"的设备 |

### 5.4 第二个 job：编译

```yaml
  build:
    needs: prepare-matrix
    runs-on: ubuntu-22.04
    timeout-minutes: 355
    # ↑ 整个 job 最多跑 355 分钟（GitHub 硬上限是 360），超时自动失败

    strategy:
      fail-fast: false
      # ↑ 一组失败不影响其他组继续编（否则一个包出错全部白跑）
      matrix: ${{ fromJSON(needs.prepare-matrix.outputs.matrix) }}

    env:
      BUILD_TARGET: ${{ matrix.target }}
      PROFILES: ${{ matrix.profiles }}
      ARTIFACT_SUBDIR: ${{ matrix.artifact_subdir }}
      GOPROXY: https://goproxy.cn,direct
```

**步骤 1：安装编译依赖**

```yaml
      - name: 安装编译依赖
        env:
          DEBIAN_FRONTEND: noninteractive
          # ↑ 让 apt 不弹交互式对话框
        run: |
          sudo apt clean
          sudo rm -rf /var/lib/apt/lists/*
          sudo apt update -y
          sudo apt install -y --no-install-recommends ack antlr3 asciidoc autoconf automake ... zlib1g-dev
          # ↑ 这一长串是 OpenWrt 官方文档要求的编译依赖：
          #   编译器(gcc/g++-multilib)、构建工具(make/cmake/ninja/autotools)、
          #   脚本语言(python3/perl相关)、镜像打包(squashfs-tools/cpio/p7zip)、
          #   设备树编译器(device-tree-compiler)、以及其他杂项
          sudo apt clean
          sudo rm -rf /var/lib/apt/lists/*
          # ↑ 装完清缓存，省磁盘
```

**步骤 2：清理磁盘空间**

```yaml
      - name: 清理 GitHub Runner 编译空间
        run: |
          set -e -o pipefail
          echo "清理前："
          df -h / "$GITHUB_WORKSPACE"
          # ↑ df -h = 显示磁盘剩余空间

          # maximize-build-space 曾在当前 Runner 镜像上把根分区压缩到约 1 GiB。
          # 这里只删除 MT798x 编译不需要的预装 SDK，不修改 Runner 分区布局。
          sudo rm -rf /usr/share/dotnet
          sudo rm -rf /usr/local/lib/android
          sudo rm -rf /opt/ghc
          sudo rm -rf /opt/hostedtoolcache/CodeQL
          sudo docker image prune --all --force || true
          # ↑ GitHub 的 runner 预装了一堆我们不需要的东西（.NET、Android SDK、
          #   Haskell 编译器、CodeQL 工具、docker 镜像）。删掉腾出空间。
          #   注释里那句是历史教训：曾经用过第三方"扩容"脚本，结果反而把根分区
          #   压到 1GB 导致失败，所以现在只删文件、不动分区。

          echo "清理后："
          df -h / "$GITHUB_WORKSPACE"
          workspace_available_kb="$(df --output=avail "$GITHUB_WORKSPACE" | tail -1)"
          # ↑ --output=avail 只取"可用空间(KB)"那一列，tail -1 取数值行
          if [ "$workspace_available_kb" -lt 73400320 ]; then
            echo "错误：工作区可用空间不足 70 GiB，停止编译以避免中途耗尽。" >&2
            exit 1
          fi
          # ↑ 73400320 KB = 70 GiB。空间不够就别开始了，省得编到 3 小时才失败。
```

**步骤 3：准备源码和配置**

```yaml
      - name: 准备源码和配置
        run: |
          set -e -o pipefail
          build_date="$(date +%Y%m%d)"
          image_prefix="immortalwrt-25.12-${BUILD_TARGET}"
          echo "image_name=${image_prefix}-${build_date}" >> "$GITHUB_ENV"
          echo "release_tag=${image_prefix}-${build_date}" >> "$GITHUB_ENV"
          # ↑ 写进 $GITHUB_ENV 的变量，后续步骤可以直接用（像普通环境变量）
          #   例如 release 的 tag 形如 immortalwrt-25.12-mt7981-ax3000-20260908

          git init openwrt
          git -C openwrt remote add origin "$REPO_URL"
          git -C openwrt fetch --depth=1 origin "$REPO_COMMIT"
          git -C openwrt checkout --detach FETCH_HEAD
          test "$(git -C openwrt rev-parse HEAD)" = "$REPO_COMMIT"
          # ↑ 和 build_all.sh 的 clone_openwrt 完全一样

          cd openwrt
          bash ../01_prepare.sh
          bash ../scripts/validate_fur602.sh .
          bash ../05_validate_profile.sh "$PROFILES"
          bash ../04_make_profile_config.sh "$PROFILES" .config
          bash ../02_add_package.sh
          make defconfig
          bash ../06_validate_target_config.sh "$PROFILES"
          bash ../03_validate_packages.sh
          # ↑ 和 build_all.sh 里的顺序一模一样：准备 → 05 → 04 → 02 →
          #   defconfig → 06 → 03
```

**步骤 4：缓存下载目录**

```yaml
      - name: 缓存下载目录
        uses: actions/cache@v5
        with:
          path: openwrt/dl
          key: ${{ runner.os }}-${{ env.REPO_BRANCH }}-dl-${{ hashFiles('package.conf', '01_prepare.sh') }}
          restore-keys: |
            ${{ runner.os }}-${{ env.REPO_BRANCH }}-dl-
          # ↑ 把 openwrt/dl（源码包缓存）存起来，下次编译直接复用，省很多时间。
          #   key 里带 package.conf 和 01_prepare.sh 的哈希：
          #   这两个文件变了（插件变了）就换一个新缓存。
          #   restore-keys 是"找不到精确匹配就退而求其次用前缀匹配的旧缓存"。
```

**步骤 5：下载 + 编译（带失败回退）**

```yaml
      - name: 下载源码包
        run: |
          cd openwrt
          timeout 30m make download -j8 || {
            echo "并行下载失败或超时，改用单线程详细日志重试..."
            timeout 20m make download -j1 V=s
          }
          # ↑ 先并行下载（快）。失败或超时就单线程重试，
          #   并且 V=s 打开详细日志，方便你看是哪一行出错。
          #   这种"先快后慢"的写法在 CI 里很实用。

      - name: 编译固件
        run: |
          cd openwrt
          timeout 4h make -j"$(nproc)" || {
            echo "并行编译失败或超时，改用单线程详细日志重试..."
            timeout 75m make -j1 V=s
          }
          # ↑ $(nproc) = 当前机器的 CPU 核心数（GitHub runner 是 4 核）
          #   同样的回退策略。注意：如果是真正的代码错误，
          #   单线程重试也会失败，但至少日志会告诉你错在哪。
```

**步骤 6：打包**

```yaml
      - name: 打包固件
        run: |
          set -e -o pipefail
          rm -rf artifact install-artifact
          mkdir -p artifact install-artifact
          target_dir="openwrt/bin/targets/${ARTIFACT_SUBDIR}"
          find "$target_dir" -maxdepth 1 -type f -printf '%p\n' | sort

          mapfile -t images < <(find "$target_dir" -maxdepth 1 -type f \
            \( -name '*factory*' -o -name '*sysupgrade*' -o -name '*.manifest' \) | sort)
          if [ "${#images[@]}" -eq 0 ]; then
            echo "在 openwrt/bin/targets/${ARTIFACT_SUBDIR} 下没有找到固件产物" >&2
            exit 1
          fi
          cp "${images[@]}" artifact/
          # ↑ 普通包：factory + sysupgrade + manifest（日常升级用的）

          (
            cd artifact
            find . -maxdepth 1 -type f ! -name sha256sums -printf '%P\0' | sort -z | xargs -0 sha256sum > sha256sums
            7z a -t7z -m0=lzma2 -mx=9 -md=256m -mfb=273 -ms=on -mmt=on -myx=9 "../${image_name}.7z" .
          )
          # ↑ 生成校验文件，然后压成一个 7z。
          #   7z 参数逐个解释：
          #     -t7z          用 7z 格式（比 zip 小很多）
          #     -m0=lzma2     压缩算法用 LZMA2
          #     -mx=9         压缩级别最高
          #     -md=256m      字典大小 256MB（越大压得越小，但吃内存）
          #     -mfb=273      匹配器 fast bytes 设到最大
          #     -ms=on        固实压缩：把多个文件当成一个大文件压，效果更好
          #     -mmt=on       多线程压缩
          #     -myx=9        极限模式（在 -mx=9 基础上进一步尝试）
          #   实测能比默认参数把 release 包再压小 25~40%。

          release_artifacts="${image_name}.7z"

          mapfile -t install_images < <(find "$target_dir" -maxdepth 1 -type f \
            \( -name '*recovery*' -o -name '*preloader*' -o -name '*bl31*' -o -name '*fip*' -o -name '*gpt*' \) | sort)
          if [ "${#install_images[@]}" -gt 0 ]; then
            cp "${install_images[@]}" install-artifact/
            cat > install-artifact/README-install.zh-CN.txt <<'EOF'
          ...（新刷/救援警告 + RAX3000M 的 eMMC/NAND 说明）...
          EOF
            (
              cd install-artifact
              find . -maxdepth 1 -type f ! -name sha256sums -printf '%P\0' | sort -z | xargs -0 sha256sum > sha256sums
              7z a -t7z ... "../${image_name}-install.7z" .
            )
            release_artifacts="${release_artifacts},${image_name}-install.7z"
          fi
          # ↑ install 包：只有"新刷/救砖/换启动链"才用得到的文件，
          #   单独压一个包，并在里面放一个中文警告说明。
          #   如果一个都没有（比如 FUR602 就没有 preloader/recovery），就跳过。

          echo "release_artifacts=${release_artifacts}" >> "$GITHUB_ENV"
```

**步骤 7：创建 Release**

```yaml
      - name: 创建 Release
        if: github.event_name != 'pull_request'
        uses: ncipollo/release-action@v1.21.0
        with:
          name: ${{ env.release_tag }}
          allowUpdates: true
          prerelease: false
          tag: ${{ env.release_tag }}
          commit: ${{ github.sha }}
          makeLatest: false
          artifactErrorsFailBuild: true
          replacesArtifacts: true
          token: ${{ secrets.GITHUB_TOKEN }}
          artifacts: ${{ env.release_artifacts }}
          # ↑ 在仓库的 Releases 页面创建一个带 tag 的发布，把 7z 传上去。
          #   allowUpdates + replacesArtifacts：同名 tag 已存在时更新并替换文件，
          #   所以同一天重复编译不会报错。
```

---

## 6. 设备适配详解（以 HONOR FUR-602 为例）

> 这一章讲的是"怎么把一台源码里原本不支持的机器加进去"。
> 如果你只是增删插件，可以跳过；但想看明白固件为什么能启动、Wi-Fi 为什么有信号，值得读。

### 6.1 `patches/2512/files/mt7981b-honor-fur-602.dts`（设备树）

设备树（Device Tree）用文本描述硬件。语法很像 C 的结构体，但其实是独立语言：

- `/ { ... }` 是根节点；
- `名字 = 值;` 是属性；
- `节点名 { ... }` 是子节点；
- `&标签 { ... }` 是"往别处定义好的节点里追加/覆盖内容"；
- `#include` 和 C 的 include 类似，引入宏定义和通用片段。

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
// ↑ 许可证声明

/dts-v1/;
// ↑ 声明"这是设备树源文件，版本 1"

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>
#include <dt-bindings/pinctrl/mt65xx.h>
// ↑ 引入宏定义，比如 GPIO_ACTIVE_LOW（低电平有效）、KEY_RESTART（重启键码）、
//   LED_COLOR_ID_GREEN（绿色）、MTK_DRIVE_8mA（引脚驱动能力 8mA）
//   注意：最后一个 mt65xx.h 是联发科特有的，有些版本里不叫这个名字，
//   所以 validate_fur602.sh 会专门检查它存在。

#include "mt7981b.dtsi"
// ↑ 引入 MT7981 SoC 的通用定义（.dtsi = 类似头文件的设备树片段）。
//   里面已经定义好了 CPU、内存控制器、各种外设，我们只需要"改/补"这台机器的差异。
```

```dts
/ {
	model = "HONOR FUR-602/603";
	compatible = "honor,fur-602", "mediatek,mt7981";
	// ↑ 内核靠 compatible 来识别"这是哪台机器"。
	//   第一个字符串是具体机型，第二个是 SoC 型号（作为兜底）。
	//   这个字符串必须和 filogic.mk 里的 SUPPORTED_DEVICES 一致，
	//   否则 sysupgrade 会拒绝刷入（"设备不匹配"）。
```

```dts
	aliases {
		label-mac-device = &wan;
		// ↑ 用 WAN 口的 MAC 地址作为设备标签上印的 MAC
		led-boot = &status_red_led;
		led-failsafe = &status_red_led;
		led-running = &status_green_led;
		led-upgrade = &status_green_led;
		// ↑ 状态灯约定：
		//   开机中 / 恢复模式(failsafe) → 红灯
		//   正常运行 / 升级中        → 绿灯
		serial0 = &uart0;
	};

	chosen: chosen {
		stdout-path = "serial0:115200n8";
		// ↑ 内核日志从串口输出，波特率 115200，8 位数据无校验。
		//   救砖时接 USB-TTL 看这个串口能救命。
	};

	memory@40000000 {
		reg = <0 0x40000000 0 0x10000000>;
		device_type = "memory";
		// ↑ 内存起始地址 0x40000000，大小 0x10000000 = 256 MiB
	};
```

```dts
	gpio-keys {
		compatible = "gpio-keys";

		button-reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
			// ↑ Reset 键接在 GPIO 1 上，按下时是低电平
		};

		button-mesh {
			label = "mesh";
			linux,code = <BTN_9>;
			linux,input-type = <EV_SW>;
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
			// ↑ Mesh 键接在 GPIO 0 上
		};
	};

	leds {
		compatible = "gpio-leds";

		status_green_led: led-0 {
			color = <LED_COLOR_ID_GREEN>;
			function = LED_FUNCTION_STATUS;
			gpios = <&pio 8 GPIO_ACTIVE_LOW>;
			// ↑ 绿灯接 GPIO 8，低电平点亮
		};

		status_red_led: led-1 {
			color = <LED_COLOR_ID_RED>;
			function = LED_FUNCTION_STATUS;
			gpios = <&pio 13 GPIO_ACTIVE_LOW>;
		};
	};
};
// ↑ led-0 / led-1 这种命名是给内核排序用的，保证每次启动编号一致
```

```dts
&eth {
	status = "okay";
	// ↑ status = "okay" 表示"启用这个设备"（"disabled" 是禁用）

	gmac0: mac@0 {
		compatible = "mediatek,eth-mac";
		reg = <0>;
		phy-mode = "2500base-x";
		// ↑ 这是 SoC 的以太网控制器 GMAC0，以 2500BASE-X 模式
		//   连接到交换机芯片的 CPU 口

		nvmem-cell-names = "mac-address";
		nvmem-cells = <&macaddr_factory_4 0>;
		// ↑ MAC 地址从 Factory 分区的 macaddr_factory_4 读，参数 0 = 基础地址

		fixed-link {
			speed = <2500>;
			full-duplex;
			pause;
			// ↑ 固定 2500Mbps 全双工（因为连的是板载交换机，不是外部网线）
		};
	};
};

&mdio_bus {
	switch: switch@1f {
		compatible = "mediatek,mt7531";
		// ↑ 交换机芯片型号 MT7531
		reg = <31>;
		// ↑ 在 MDIO 总线上的地址是 31（0x1f）
		reset-gpios = <&pio 39 GPIO_ACTIVE_HIGH>;
		interrupt-controller;
		#interrupt-cells = <1>;
		interrupt-parent = <&pio>;
		interrupts = <38 IRQ_TYPE_LEVEL_HIGH>;
		// ↑ 复位脚 GPIO 39，中断脚 GPIO 38
	};
};
```

```dts
&spi0 {
	pinctrl-names = "default";
	pinctrl-0 = <&spi0_flash_pins>;
	status = "okay";

	spi_nand: spi_nand@0 {
		compatible = "spi-nand";
		reg = <0>;

		spi-max-frequency = <52000000>;
		spi-tx-bus-width = <4>;
		spi-rx-bus-width = <4>;
		// ↑ SPI 时钟 52MHz，收/发都是 4 线（Quad SPI，速度快）

		spi-cal-enable;
		spi-cal-mode = "read-data";
		spi-cal-datalen = <7>;
		spi-cal-data = /bits/ 8 <0x53 0x50 0x49 0x4e 0x41 0x4e>;
		spi-cal-addrlen = <5>;
		spi-cal-addr = /bits/ 32 <0x0 0x0 0x0 0x0 0x0>;
		// ↑ SPI NAND 的"校准序列"：初始化时先读这 7 个字节，
		//   期望值是 0x53 0x50 0x49 0x4e 0x41 0x4e = ASCII 的 "SPINAND"。
		//   读到说明时序参数正确，控制器才能可靠地读写这颗闪存。

		mediatek,nmbm;
		mediatek,bmt-max-ratio = <1>;
		mediatek,bmt-max-reserved-blocks = <64>;
		// ↑ 启用 NMBM（MediaTek 的 NAND 坏块管理表）：
		//   坏块映射表最多占 1 倍比例，保留 64 个块给坏块管理用。
		//   这些参数是 MTK 平台的标准写法，validate 脚本会逐条检查。

		partitions {
			compatible = "fixed-partitions";
			#address-cells = <1>;
			#size-cells = <1>;
			// ↑ 分区表用固定偏移描述

			partition@0 {
				label = "BL2";
				reg = <0x0 0x100000>;
				read-only;
				// ↑ 0 偏移，1 MiB：BL2（二级引导，BootROM 之后第一段代码）
			};

			partition@100000 {
				label = "u-boot-env";
				reg = <0x100000 0x80000>;
				// ↑ 1 MiB 偏移，512 KiB：U-Boot 的环境变量
			};

			partition@180000 {
				label = "Factory";
				reg = <0x180000 0x1e0000>;
				read-only;
				// ↑ 1.5 MiB 偏移，1.875 MiB：出厂数据区，只读
				//   ⚠️ 这里面有每台机器唯一的无线校准数据和 MAC 地址，
				//   刷机时绝对不能覆盖，否则 Wi-Fi 废掉。

				nvmem-layout {
					compatible = "fixed-layout";
					#address-cells = <1>;
					#size-cells = <1>;

					eeprom_factory_0: eeprom@0 {
						reg = <0x0 0x1000>;
						// ↑ Factory 分区开头 4 KiB 是无线 EEPROM（校准数据）
					};

					macaddr_factory_4: macaddr@4 {
						compatible = "mac-base";
						reg = <0x4 0x6>;
						#nvmem-cell-cells = <1>;
						// ↑ 从第 4 字节开始读 6 字节 = MAC 地址。
						//   mac-base 表示"这是一个基础地址，可以按序号自动 +1"
					};
				}
			};

			partition@360000 {
				label = "Trace";
				reg = <0x360000 0x20000>;
				read-only;
				// ↑ 128 KiB：厂商调试跟踪区
			};

			partition@380000 {
				label = "FIP";
				reg = <0x380000 0x200000>;
				read-only;
				// ↑ 2 MiB：FIP = Firmware Image Package，
				//   里面是 ARM Trusted Firmware(BL31) + U-Boot
			};

			partition@580000 {
				label = "ubi";
				reg = <0x580000 0x7200000>;
				// ↑ 5.5 MiB 偏移，0x7200000 = 114 MiB：系统区（UBI 卷）
				//   内核和根文件系统都装在这里
			};
		};
	};
};
```

```dts
&switch {
	ports {
		#address-cells = <1>;
		#size-cells = <0>;

		wan: port@0 {
			reg = <0>;
			label = "wan";
			nvmem-cell-names = "mac-address";
			nvmem-cells = <&macaddr_factory_4 1>;
			// ↑ 参数 1 表示"基础 MAC + 1"，和 GMAC0 的 MAC 不同
		};

		port@1 { reg = <1>; label = "lan3"; };
		port@2 { reg = <2>; label = "lan2"; };
		port@3 { reg = <3>; label = "lan1"; };
		// ↑ 注意：DTS 里的端口编号和面板上的标注**不是顺序对应的**。
		//   这里才是决定 Linux 里网口名字的地方。
		//   validate_fur602.sh 会逐个检查这四条，防止改错导致网口错乱。

		port@6 {
			reg = <6>;
			ethernet = <&gmac0>;
			phy-mode = "2500base-x";
			fixed-link {
				speed = <2500>;
				full-duplex;
				pause;
			};
			// ↑ 端口 6 是交换机连到 SoC 的 CPU 口（内部口）
		};
	};
};

&pio {
	spi0_flash_pins: spi0-pins {
		mux {
			function = "spi";
			groups = "spi0", "spi0_wp_hold";
			// ↑ 把这些引脚复用成 SPI 功能
		};

		conf-pu {
			pins = "SPI0_CS", "SPI0_HOLD", "SPI0_WP";
			drive-strength = <MTK_DRIVE_8mA>;
			bias-pull-up = <MTK_PUPD_SET_R1R0_11>;
			// ↑ CS/HOLD/WP 三个脚上拉
		};

		conf-pd {
			pins = "SPI0_CLK", "SPI0_MOSI", "SPI0_MISO";
			drive-strength = <MTK_DRIVE_8mA>;
			bias-pull-down = <MTK_PUPD_SET_R1R0_11>;
			// ↑ 时钟和数据脚下拉
		};
	};
};

&uart0 { status = "okay"; };
// ↑ 启用串口控制台

&watchdog { status = "okay"; };
// ↑ 启用硬件看门狗（死机自动重启）

&wifi {
	status = "okay";
	nvmem-cell-names = "eeprom";
	nvmem-cells = <&eeprom_factory_0>;
	// ↑ 启用 Wi-Fi，并告诉它去 Factory 分区读校准数据。
	//   没有这一行，Wi-Fi 要么起不来，要么发射功率不受控。
};
```

### 6.2 `patches/2512/0001-add-honor-fur-602.sh`（把 FUR602 加进源码）

这个脚本做三件事：装 DTS、往 `filogic.mk` 加设备定义、往 `02_network` 加网口映射。
它被 `01_prepare.sh` 自动调用，且**可以重复执行**（每一步都先检查"是不是已经做过了"）。

```bash
#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ↑ ${BASH_SOURCE[0]} 和 $0 类似，但在被 source 时更可靠
FILES_DIR="$PATCH_DIR/files"

DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/dts"
IMAGE_MK="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
NETWORK_FILE="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "错误：OPENWRT_DIR 看起来不是 ImmortalWrt 源码树：$OPENWRT_DIR" >&2
  exit 1
fi
# ↑ 防呆：确认目录真的是源码树
```

```bash
insert_before_marker() {
  # 用法：insert_before_marker <文件> <标记行> <要插入的内容文件>
  local file="$1"
  local marker="$2"
  local block_file="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
      # ↑ BEGIN 块：先把要插入的内容整个读进变量 block
      #   ORS = 输出记录分隔符（默认换行）
    }
    index($0, marker) && !done {
      printf "%s", block
      done = 1
      # ↑ 遇到标记行时，先输出要插入的内容，再把 done 置 1（保证只插一次）
    }
    { print }
    # ↑ 然后照常输出当前行
    END {
      if (!done) exit 1
      # ↑ 如果整个文件里都没找到标记 → 失败退出（说明源码结构变了）
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  # ↑ 写入临时文件再覆盖回去（awk 不能直接写正在读的文件）
}
# ↑ 为什么用 awk 而不是 sed：要插入的是多行内容，
#   而且"没找到标记要报错"这件事 sed 做起来很别扭，awk 很自然。
```

```bash
install -m 0644 "$FILES_DIR/mt7981b-honor-fur-602.dts" "$DTS_DIR/mt7981b-honor-fur-602.dts"
# ↑ install -m 0644 = 复制文件并设权限为 rw-r--r--
#   （比 cp 更明确，且会覆盖）

if ! grep -q '^define Device/honor_fur-602$' "$IMAGE_MK"; then
  # ↑ 如果还没加过设备定义，就加
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/honor_fur-602
  DEVICE_VENDOR := HONOR
  DEVICE_MODEL := FUR-602/603
  DEVICE_DTS := mt7981b-honor-fur-602
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += honor,fur-602
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += honor_fur-602

DEVICE
  # ↑ <<'DEVICE' 带引号 = 内容原样写入，$ 不会被 shell 展开
  #   （这一点很关键，否则 $$$$ 会被 shell 吃掉）

  insert_before_marker "$IMAGE_MK" "define Device/h3c_magic-nx30-pro" "$block"
  # ↑ 插在另一个 MT7981 设备前面（保持文件里设备按平台聚集）
  rm -f "$block"
fi
```

逐行解释这段设备定义：

| 行 | 含义 |
|---|---|
| `DEVICE_VENDOR := HONOR` | 厂商名，用于生成文件名和 LuCI 显示 |
| `DEVICE_MODEL := FUR-602/603` | 型号 |
| `DEVICE_DTS := mt7981b-honor-fur-602` | 用哪个设备树文件（**不带 `.dts` 后缀**） |
| `DEVICE_DTS_DIR := ../dts` | 设备树所在目录（相对于 `target/linux/mediatek/image/`） |
| `SUPPORTED_DEVICES += honor,fur-602` | 允许刷入的设备标识，和 DTS 里的 `compatible` 对应；sysupgrade 靠它判断"这固件是不是给这台机器的" |
| `DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware` | 这台设备额外要装的包 —— 就是 **Wi-Fi 驱动和固件**（25.12 走官方 MTK 驱动路线） |
| `UBINIZE_OPTS := -E 5` | 传给 `ubinize` 的额外参数。`-E` 是 OpenWrt 给 mtd-utils 打的补丁选项（`--eof-markers`），意思是"在生成的 UBI 镜像尾部写 5 个 EOF 标记块"，让引导程序能识别镜像结束位置。MTK 平台设备统一这么写，照抄即可 |
| `BLOCKSIZE := 128k` | NAND 擦除块大小 128 KiB |
| `PAGESIZE := 2048` | NAND 页大小 2048 字节 |
| `IMAGE_SIZE := 116736k` | 镜像允许的最大尺寸 = 114 MiB。超过会被 `check-size` 拦下并报错 |
| `KERNEL_IN_UBI := 1` | 内核也打包进 UBI 卷里（而不是单独放在内核分区） |
| `IMAGES += factory.bin` | 除了默认产物，额外产出一个 `factory.bin` |
| `IMAGE/factory.bin := append-ubi \| check-size $$$$(IMAGE_SIZE)` | factory.bin 的生成流水线：先打包成 UBI 镜像，再检查大小是否超标 |
| `IMAGE/sysupgrade.bin := sysupgrade-tar \| append-metadata` | sysupgrade.bin 的生成流水线：打成 tar 包，再附加元数据（版本、支持的设备等，供 sysupgrade 校验） |
| `TARGET_DEVICES += honor_fur-602` | 把设备注册进这个 target（漏了这行设备不会出现在 menuconfig 里） |

> `$$$$(IMAGE_SIZE)` 为什么要写 4 个 `$`？
> 这段定义在 Makefile 里会被展开两次：第一次 `$$$$` → `$$`，第二次 `$$` → `$`，
> 最终变成 `$(IMAGE_SIZE)`，也就是把 114 MiB 这个值传给 `check-size`。
> 这是 OpenWrt 设备定义里的固定写法，照抄。

```bash
if ! grep -q 'honor,fur-602' "$NETWORK_FILE"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	honor,fur-602|\
NETWORK
  insert_before_marker "$NETWORK_FILE" "jcg,q30-pro|\\" "$block"
  rm -f "$block"
fi
# ↑ 02_network 是一个巨大的 case 语句，负责"板子标识 → 网口配置"的映射。
#   这里把 honor,fur-602|\ 插到 jcg,q30-pro|\ 前面，
#   意思是"FUR602 沿用和 JCG Q30 Pro 同一段配置"，
#   也就是 validate 脚本检查的那句：
#       ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan
#   即：lan1/lan2/lan3 组成 LAN 桥，port0 是 WAN。
#   行尾的 \ 是 shell 的续行符，让多个设备标识共享同一个 case 分支。

echo "HONOR FUR-602/603 25.12 适配已准备好。"
```

### 6.3 `patches/2512/build-system/download-reliability.patch`

这个补丁改三处，目的都是"别让一个卡住的镜像拖死整个编译"：

```diff
--- a/scripts/download.pl
+++ b/scripts/download.pl
@@ -124,7 +124,9 @@ sub download_cmd {
 	if ($download_tool eq "curl") {
-		return (qw(curl -f --connect-timeout 5 --retry 3 --location),
+		return (qw(curl -f --connect-timeout 15
+			--speed-limit 1024 --speed-time 30 --max-time 300
+			--retry 2 --retry-delay 2 --retry-max-time 180 --location),
```

| 参数 | 含义 |
|---|---|
| `--connect-timeout 15` | 连接超时 15 秒（原来是 5 秒，国内访问国外源经常来不及） |
| `--speed-limit 1024 --speed-time 30` | **30 秒内平均速度低于 1024 B/s 就放弃**，换下一个镜像 —— 这条最关键，专治"连上了但几乎不动"的死连接 |
| `--max-time 300` | 单个文件最多下 5 分钟 |
| `--retry 2 --retry-delay 2 --retry-max-time 180` | 失败重试 2 次、间隔 2 秒、总共最多耗 180 秒（防止无限重试占满 CI 时间） |

```diff
+++ b/scripts/localmirrors        （新增文件）
+https://sources.cdn.openwrt.org
+https://sources.openwrt.org
+https://sources-cdn.immortalwrt.org
+https://sources.immortalwrt.org
```
下载源码包时的镜像优先级：**首选 OpenWrt 官方 CDN**（最快最全），最后才用 immortalwrt 的源。

```diff
 	"@KERNEL": [
-		"https://mirror.iscas.ac.cn/kernel.org",
+		"https://cdn.kernel.org/pub",
 		"https://mirrors.ustc.edu.cn/kernel.org",
 		"https://mirror.nju.edu.cn/kernel.org",
-		"https://cdn.kernel.org/pub",
+		"https://mirror.iscas.ac.cn/kernel.org",
```
下载 Linux 内核时，把 `cdn.kernel.org` 提到 `iscas` 前面（ISCAS 曾经出过长时间无响应）。
`validate_fur602.sh` 会检查这个顺序对不对。

### 6.4 `patches/2512/luci-app-scutclient-modern-luci.patch`

**背景**：老版 LuCI 允许随便定义全局变量；新版 LuCI（ucode bridge）对全局变量很敏感，
插件会报错或整个页面 500。这个补丁把老代码"现代化"：

```lua
module("luci.controller.scutclient", package.seeall)
-- ↑ 这行让下面所有赋值默认变成**全局变量**，是问题根源

-http = require "luci.http"        -- 全局，会污染环境
-fs = require "nixio.fs"           -- 25.12 不推荐/没有这个模块
-sys  = require "luci.sys"
+local http = require "luci.http"          -- 改成局部变量
+local sys = require "luci.sys"
+local luci_template = require "luci.template"
+local io_open = io.open                   -- 把标准库函数存成局部变量
+local table_foreach = table.foreach
+
+local function file_exists(path)          -- 自己写一个"文件存在吗"
+	local file = io_open(path, "r")
+	if file then
+		file:close()
+		return true
+	end
+	return false
+end

-log_file = "/tmp/scutclient.log"          -- 全局 → 局部
+local log_file = "/tmp/scutclient.log"
```

其他几处替换：

| 原来 | 改成 | 原因 |
|---|---|---|
| `fs.access(path)` | `file_exists(path)` | 不再依赖 `nixio.fs` |
| `fs.mkdirr(dir)` | `sys.call("mkdir -p " .. dir)` | 用系统命令代替 |
| `luci.template.render(...)` | `luci_template.render(...)` | 不依赖 LuCI 全局变量 |
| `luci.http.formvalue(...)` | `http.formvalue(...)` | 同上 |
| `table.foreach(...)` | `table_foreach(...)` | 新版环境里 `table` 全局可能被限制 |

⚠️ 一个容易看漏的细节：**不能**把局部变量起名叫 `template`，因为 LuCI 的
dispatcher 用 `template()` 做页面路由，局部变量会把它遮住。
所以补丁里叫 `luci_template`。`validate_scutclient.sh` 专门检查这一点。

### 6.5 `scripts/validate_fur602.sh`

**作用**：编译前检查 FUR602 的适配是否完整。结构是：

```bash
EXPECTED_SOURCE_COMMIT="${REPO_COMMIT:-1cfeb3edade40fe2dfec59c21381de1d8e361100}"
DTS="$OPENWRT_DIR/target/linux/mediatek/dts/mt7981b-honor-fur-602.dts"
IMAGE_MK="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
NETWORK_FILE=".../filogic/base-files/etc/board.d/02_network"
UPGRADE_FILE=".../filogic/base-files/lib/upgrade/platform.sh"
DOWNLOAD_SCRIPT="$OPENWRT_DIR/scripts/download.pl"
PROJECT_MIRRORS="$OPENWRT_DIR/scripts/projectsmirrors.json"
LOCAL_MIRRORS="$OPENWRT_DIR/scripts/localmirrors"
HAPROXY_DEFAULTS="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults/99-disable-unused-haproxy"
# ↑ 所有要检查的文件的绝对路径
```

它检查的东西分 5 类：

1. **脚本语法**：对每个 `.sh` 跑 `bash -n`（只做语法检查，不执行）。
2. **源码提交号**：必须等于 `EXPECTED_SOURCE_COMMIT` —— 因为所有补丁都是针对这个版本写的。
3. **文件存在**：DTS、filogic.mk、02_network、platform.sh 等都要在。
4. **内容正确**：
   - download.pl 里有没有那两行超时参数；
   - `localmirrors` 第一行是不是 `https://sources.cdn.openwrt.org`；
   - `projectsmirrors.json` 里 cdn.kernel.org 是不是排在 iscas 前面；
   - haproxy 首启脚本里有没有 disable + stop；
   - DTS 里的关键内容（NMBM、分区布局、MT7531、compatible、Wi-Fi EEPROM、四个网口的 label、CPU 口连 GMAC0）；
   - filogic.mk 里的设备定义各字段；
   - 02_network 里的 LAN/WAN 配置；
   - platform.sh 里有没有默认的 NAND 升级分支。
5. **辅助函数**：

```bash
device_block_has() {
  # 检查 filogic.mk 的 define Device/honor_fur-602 块里，是否出现某段文字
  awk -v expected="$expected" '
    $0 == "define Device/honor_fur-602" { in_device = 1; count++ }
    # ↑ 进入设备定义块
    in_device && index($0, expected) { found = 1 }
    # ↑ 在块内找目标字符串
    in_device && $0 == "endef" { in_device = 0 }
    # ↑ 遇到 endef 退出块
    END { exit !(count == 1 && found) }
    # ↑ 要求：设备块只出现一次，且包含目标字符串
  ' "$IMAGE_MK"
}
# ↑ 为什么要"只出现一次"？防止文件被重复插入了两遍设备定义。

dts_node_has() {
  # 检查 DTS 的某个节点里是否有某行内容（比如 port@0 里有没有 label = "wan";）
  ...
}
```

**为什么这些检查值得存在**：设备树和分区表写错，后果不是"编译失败"，而是
**固件能编出来但刷上去变砖**（比如分区偏移错了会覆盖 bootloader）。
所以宁可编译前多花两秒检查。

### 6.6 `scripts/validate_scutclient.sh`

**作用**：验证校园网插件的 Lua 代码确实被补丁改成了"现代 LuCI 兼容"的写法。

```bash
controller="${1:?用法：validate_scutclient.sh <scutclient.lua>}"
# ↑ ${1:?错误信息} = 如果第 1 个参数为空，就打印这句错误并退出

grep -Fq 'local http = require "luci.http"' "$controller" || fail "http 不是局部变量"
grep -Fq 'local function file_exists(path)' "$controller" || fail "缺少文件检查函数"
grep -Fq 'template("scutclient/logs")' "$controller" || fail "日志页面路由缺失"
# ↑ 逐条确认"该有的新写法在"

! grep -Fq 'require "nixio.fs"' "$controller" || fail "仍依赖 25.12 不应使用的 nixio.fs"
! grep -Eq '(^|[^[:alnum:]_])fs\.' "$controller" || fail "仍有 fs 全局调用"
! grep -Eq '^[[:space:]]*luci\.(http|sys|template)\.' "$controller" || \
  fail "仍直接使用不可靠的 luci 全局变量"
! grep -Fq 'local template = require "luci.template"' "$controller" || \
  fail "局部变量遮蔽了 LuCI dispatcher 的 template 路由函数"
# ↑ 逐条确认"不该有的旧写法都不在"
#   -E 表示用扩展正则，(^|[^[:alnum:]_]) 是为了避免把 xxxfs. 也误判

echo "scutclient 现代 LuCI 兼容校验通过。"
```

---

## 7. 日常操作手册

### 7.1 增加 / 删除插件

**加插件**：

1. 打开 `package.conf`，在合适的分组下面加一行包名（不带 `CONFIG_PACKAGE_` 和 `=y`）：

   ```text
   luci-app-wol
   ```

2. 如果你不确定包名，先查（见 [4.3](#43-packageconf插件清单)）。
3. 本地验证（可选但推荐）：

   ```bash
   cd /home/miunah/my_project/mt798x_build_2512/openwrt
   bash ../05_validate_profile.sh mt7981-ax3000
   bash ../04_make_profile_config.sh mt7981-ax3000 .config
   bash ../02_add_package.sh
   make defconfig
   bash ../06_validate_target_config.sh mt7981-ax3000
   bash ../03_validate_packages.sh
   ```

   `03` 不报错就说明新包名有效。
4. 去 GitHub Actions 点一次编译。

**删插件**：在 `package.conf` 里把那一行**删掉**，或者行首加 `#` 临时禁用。

⚠️ 注意依赖关系：删掉某个包，可能连带影响依赖它的插件。
比如 `luci-app-passwall` 依赖 haproxy，删掉 haproxy 相关包会让 Passwall 编不过。

**加完一定要看 `03_validate_packages.sh` 的输出** —— 它会告诉你有没有包没被启用。

### 7.2 增加设备

**场景 A：只编这一台，不进分组**

1. 确认源码里有这个设备：

   ```bash
   cd openwrt
   grep -E '^define Device/' target/linux/mediatek/image/filogic.mk | sed 's/^define Device\///'
   ```

2. 在 `profiles.conf` 加一行：

   ```text
   xiaomi_mi-router-ax3000t|mediatek/filogic|Xiaomi AX3000T
   ```

3. GitHub Actions 里 `build_target` 填 `custom`，`custom_profile` 填设备名。

**场景 B：加进编译组（推荐，省时间）**

在 `profile_groups.conf` 对应分组的第 3 列（空格分隔）里加上设备名。
同代芯片的放同一组，工具链能复用。

**加设备后必须验证**：`05` 会告诉你设备名是否存在，`06` 会告诉你 `defconfig`
之后它还在不在。**这两步过了，才能保证编出来的固件是给这台机器的。**

### 7.3 改固件版本号 / 默认设置

**版本号**：改 `04_make_profile_config.sh` 里这几行：

```bash
CONFIG_VERSION_DIST="ImmortalWrt"
CONFIG_VERSION_NUMBER="25.12"
CONFIG_VERSION_REPO="https://downloads.immortalwrt.org/releases/25.12.0"
```

改完刷机后在 LuCI 首页和 `cat /etc/openwrt_release` 里能看到。

**出厂默认设置**：在 `01_prepare.sh` 里往
`package/base-files/files/etc/uci-defaults/` 写一个脚本（参考 haproxy 那段）。
`/etc/uci-defaults/` 里的脚本**只在系统首次启动时执行一次**，执行完自动删除，
所以很适合放"出厂默认值"。

例如"默认关闭 Wi-Fi 的某个开关"：

```bash
wifi_defaults="package/base-files/files/etc/uci-defaults/99-my-wifi-default"
cat > "$wifi_defaults" <<'EOF'
#!/bin/sh
uci set wireless.default_radio0.disabled='0'
uci commit wireless
exit 0
EOF
chmod 0755 "$wifi_defaults"
```

### 7.4 在 GitHub 上编译（最常用）

1. 打开仓库的 **Actions** 页面 → 左侧选 **MT798x 25.12 手动编译**。
2. 点右侧 **Run workflow**。
3. 填写：
   - `build_target`：
     - `mt7981-ax3000`（默认，编整组 AX3000 设备）
     - `mt7986-ax6000`（编 AX6000 那组）
     - 某个具体设备名，如 `honor_fur-602`
     - `custom` + 填 `custom_profile`
     - `all`（编全部分组，最慢最占额度）
   - `custom_profile`：只有 `build_target=custom` 时才填。
4. 点绿色按钮开始。一个分组大约 1~2 小时。
5. 编译完成后去 **Releases** 页面下载 7z：
   - `immortalwrt-25.12-<目标>-<日期>.7z` → 日常升级用
   - `...-install.7z` → 新刷/救砖用（**不要随便刷里面的 preloader/FIP/GPT**）

如果 Release 建不出来：`Settings > Actions > General > Workflow permissions`
选 **Read and write permissions**。

### 7.5 本地 WSL 编译

```bash
cd /home/miunah/my_project/mt798x_build_2512
bash build_all.sh                                  # 全部分组
BUILD_TARGET=mt7981-ax3000 bash build_all.sh       # 只编一组
BUILD_TARGET=cmcc_rax3000m bash build_all.sh       # 只编一台
JOBS=1 bash build_all.sh                           # 内存小时用
```

**内存很重要**：第一次编译要在本地编译 LLVM/Clang，`JOBS=8` 会把 WSL 内存吃爆
（症状：`cc1plus` 被 killed）。WSL2 配置参考：

```ini
# C:\Users\MiunaH\.wslconfig
[wsl2]
memory=12GB
processors=16
swap=16GB
localhostForwarding=true
```

改完在 Windows 执行 `wsl --shutdown`，再进 WSL 用 `free -h` 确认。

**源码必须放在 WSL 自己的文件系统里**（`/home/...`），不要放 `/mnt/c/...`：
跨文件系统访问极慢，编译会慢好几倍。

### 7.6 更新上游源码（进阶）

现在源码被**锁死**在一个 commit 上（`1cfeb3ed...`），这是故意的：
补丁和校验都是针对这个版本写的。要更新，按下面走：

1. 查最新 commit：

   ```bash
   git ls-remote https://github.com/immortalwrt/immortalwrt.git refs/heads/openwrt-25.12
   ```

2. 同时改**两个**文件里的 `REPO_COMMIT`：
   - `build_all.sh` 第 9 行
   - `.github/workflows/mt798x.yml` 的 `env: REPO_COMMIT`

3. 删掉本地旧源码（或 `cd openwrt && git fetch`）：

   ```bash
   rm -rf openwrt
   ```

4. 跑一次校验：

   ```bash
   cd /home/miunah/my_project/mt798x_build_2512
   bash build_all.sh    # 会先跑 validate_fur602.sh
   ```

5. **大概率要修的**（因为上游结构变了）：
   - `download-reliability.patch` 打不上 → 看上游 `scripts/download.pl` 的新写法，重新生成补丁；
   - FUR602 的 DTS / filogic.mk / 02_network 里的标记行找不到 → 调整插入位置；
   - `03_validate_packages.sh` 报缺包 → 上游改名或去掉了某个包。

> 经验：**不要频繁跟最新**。现在这套是验证过的；只有当你需要新功能或安全修复时才更新，
> 并且更新后一定要先在**一台**设备上真机验证启动、有线、无线、LuCI、sysupgrade。

### 7.7 清理与重编

| 想做什么 | 命令 |
|---|---|
| 只改了插件，重新编 | 直接重跑 `build_all.sh`（会重生成 `.config`） |
| 配置乱了想重来 | `rm -f openwrt/.config` 后重跑 |
| 某个包编坏了 | `rm -rf openwrt/build_dir/target-*/<包名>*` 后重跑 |
| 想彻底重编（保留源码） | `cd openwrt && make clean` |
| 彻底重来 | `rm -rf openwrt` 后重跑（会重新下载，几 GB） |

⚠️ 本地用 `BUILD_TARGET=all` 依次编多个分组时，`bin/targets/mediatek/filogic/`
里可能残留上一组的产物，收集脚本会把它们一起拷进 `artifacts/<组名>/`。
**建议一次只编一个分组**，或者每组之间执行 `rm -rf openwrt/bin/targets`。

---

## 8. 报错对照表

| 报错 | 原因 | 怎么办 |
|---|---|---|
| `未知的 mediatek/filogic 设备 profile：xxx` | `profiles.conf` 里的设备名和源码 `filogic.mk` 对不上 | 用 `grep -E '^define Device/' .../filogic.mk` 查正确名字 |
| `make defconfig 后目标 profile 没有被启用` | Kconfig 符号名写错 → 静默回退到默认设备 | 看脚本打印的"当前选中的 profile 行"，对比 04 脚本里的符号名 |
| `make defconfig 后，下面这些请求的包没有被启用：- xxx` | 包名错 / 25.12 没有这个包 / 依赖不满足 | 查正确包名（4.3 节）；确认是不是 23.05 的旧名字 |
| `缺少 tc、tc-tiny 或 tc-full` | SQM 的依赖被别的配置关掉了 | 检查有没有冲突的 QoS 包 |
| `luci-app-tailscale 不应被选中` | 有包把 Tailscale 当依赖拉进来了 | 找出是谁依赖它，在 `package.conf` 里排除 |
| `源码提交为 xxx，尚未审查；预期 yyy` | 本地源码不是锁定的那个版本 | 删掉 `openwrt/` 重新克隆，或按 7.6 更新 |
| `错误：下载器可靠性补丁与当前源码不匹配` | 上游 `download.pl` 改了 | 按 7.6 重新生成补丁 |
| `FUR602 适配校验失败：缺少文件 ...` | 上游目录结构变了 | 检查对应文件的新位置 |
| `bad interpreter: No such file or directory` | 脚本被存成了 CRLF（Windows 换行） | 确认 `.gitattributes` 生效；`dos2unix 脚本.sh` |
| `cc1plus: Killed` / `virtual memory exhausted` | WSL 内存不够（`JOBS` 太大） | 降 `JOBS`、加大 WSL 内存/swap |
| `No space left on device` | 磁盘不够 | 清理 `openwrt/dl`、`openwrt/build_dir`，或扩容 |
| GitHub Actions 编译超时 | 某个包下载卡死 / 编译太慢 | 看是下载还是编译阶段；下载问题已在补丁里缓解 |
| Release 创建失败 | 仓库没有写权限 | Settings > Actions > General > Workflow permissions |

---

## 9. 容易踩的坑

### 9.1 `.config` 每次都会被覆盖

`04_make_profile_config.sh` 用 `cat > "$config_file"` **整个重写** `.config`。
所以：

- ❌ 在 `make menuconfig` 里改的东西，下次跑 `build_all.sh` 就没了；
- ✅ 要加插件请改 `package.conf`；
- ✅ 要改配置项请改 `04_make_profile_config.sh` 的模板。

### 9.2 不要手改 `openwrt/` 里的文件

- `build_all.sh` 会重新克隆/复用源码树；
- `01_prepare.sh` 每次都会重新打补丁、覆盖文件；
- 你手改的东西要么被覆盖，要么导致校验失败。

**要改源码，就改包装仓库里的脚本/补丁**，让它每次自动帮你改。

### 9.3 Windows 换行符（CRLF）会毁掉所有脚本

在 Windows 上用记事本编辑过 `.sh` 文件，可能把 LF 变成 CRLF。
后果：`#!/bin/bash\r` 找不到解释器、`grep -Fqx` 整行匹配失败。
**编辑脚本请用 VS Code 并把右下角换行符设为 LF**（`.gitattributes` 已经做了兜底）。

### 9.4 `JOBS` 别乱调大

本地默认 `JOBS=2` 是有原因的：第一次编译要在 WSL 里编 LLVM/Clang，
内存不够会 OOM，症状是 `cc1plus` 被系统杀掉（看起来像"编译错误"，其实是内存不够）。
WSL 内存调到 12GB + swap 16GB 之后再考虑 `JOBS=4`。

### 9.5 两组连编时的产物残留

见 [7.7](#77-清理与重编) 最后一段。建议一次只编一个分组。

### 9.6 别把 `-install.7z` 里的东西当日常升级包

`-install.7z` 里的 `preloader` / `FIP` / `GPT` / `recovery` 是给"新刷/救砖/换启动链"用的。
刷错轻则开不了机，重则失去无线校准数据（Factory 分区被覆盖）。
**日常升级永远用普通包里的 `sysupgrade` 文件。**

### 9.7 跨大版本升级不保留配置

从 23.05 升到 25.12 时，无线驱动栈完全不同（23.05 是 MTK 私有栈，25.12 是官方
`mt7915e`），在 LuCI 的"系统 → 备份/升级"里上传 `sysupgrade.bin` 时**不要**勾选保留配置。

### 9.8 不要把 23.05 的 Wi-Fi 方案套到 25.12

23.05 用的是 `kmod-mt_wifi` / `mtwifi-cfg` / `luci-app-mtwifi-cfg` 这套 MTK 私有栈；
25.12 官方 `mediatek/filogic` 用的是 `kmod-mt7915e` + SoC firmware 包。
两套不能混，硬塞会编不过或者 Wi-Fi 起不来。

### 9.9 SQM 不要和其他 QoS 插件同时管一个接口

`luci-app-sqm`（CAKE）和别的 QoS 插件（比如某些流控插件）如果同时配置同一个接口，
会互相打架，表现为网速异常或规则失效。**一个接口只让一个 QoS 管。**

---

## 附：一页速查

```bash
# ── 我要加插件 ──────────────────────────────
vim package.conf          # 加一行包名
# → GitHub Actions 点编译

# ── 我要删插件 ──────────────────────────────
vim package.conf          # 删掉那行，或行首加 #

# ── 我要编某台设备 ──────────────────────────
# GitHub Actions: build_target=honor_fur-602

# ── 我要编一组设备 ──────────────────────────
# GitHub Actions: build_target=mt7981-ax3000

# ── 我要加新设备 ────────────────────────────
# 1. 确认源码里有：grep -E '^define Device/' openwrt/target/linux/mediatek/image/filogic.mk
# 2. profiles.conf 加一行
# 3. profile_groups.conf 里加进对应分组

# ── 我要改固件版本号 ────────────────────────
vim 04_make_profile_config.sh   # 改 CONFIG_VERSION_*

# ── 我要加出厂默认设置 ──────────────────────
vim 01_prepare.sh               # 参考 haproxy 那段，写 uci-defaults

# ── 我要更新上游源码 ────────────────────────
git ls-remote https://github.com/immortalwrt/immortalwrt.git refs/heads/openwrt-25.12
# 改 build_all.sh 和 .github/workflows/mt798x.yml 里的 REPO_COMMIT
rm -rf openwrt && bash build_all.sh   # 看校验能不能过

# ── 我要本地编 ──────────────────────────────
cd /home/miunah/my_project/mt798x_build_2512
BUILD_TARGET=mt7981-ax3000 JOBS=2 bash build_all.sh
```

---

*本文档基于 2026-09-08 时的仓库状态编写（最新提交 `9ae0e75 feat: replace tailscale with sqm`）。
脚本或配置改动后，请对照更新本文档。*
