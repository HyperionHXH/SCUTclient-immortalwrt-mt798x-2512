#!/bin/bash
set -e -o pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt.git}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-25.12}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$SCRIPT_DIR/openwrt}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$SCRIPT_DIR/artifacts}"
PROFILES_CONF="${PROFILES_CONF:-$SCRIPT_DIR/profiles.conf}"
PROFILE_GROUPS_CONF="${PROFILE_GROUPS_CONF:-$SCRIPT_DIR/profile_groups.conf}"
JOBS="${JOBS:-2}"
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-8}"
BUILD_TARGET="${BUILD_TARGET:-${BUILD_PROFILE:-all}}"

clone_openwrt() {
  if [ -d "$OPENWRT_DIR/.git" ]; then
    echo "使用已有源码树：$OPENWRT_DIR"
    return
  fi

  git clone --depth=1 -b "$REPO_BRANCH" "$REPO_URL" "$OPENWRT_DIR"
}

read_profiles() {
  awk -F'|' '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    NF < 2 { printf("profiles.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      if ($1 == "" || $2 == "") { printf("profiles.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
      print $1 "|" $2
    }
  ' "$PROFILES_CONF"
}

read_groups() {
  awk -F'|' '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    NF < 3 { printf("profile_groups.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      gsub(/^[ \t]+|[ \t]+$/, "", $3)
      if ($1 == "" || $2 == "" || $3 == "") { printf("profile_groups.conf 行格式无效：%s\n", $0) > "/dev/stderr"; exit 1 }
      print $1 "|" $2 "|" $3
    }
  ' "$PROFILE_GROUPS_CONF"
}

resolve_targets() {
  if [ "$BUILD_TARGET" = "all" ]; then
    read_groups
    return
  fi

  local group_line
  group_line="$(read_groups | awk -F'|' -v p="$BUILD_TARGET" '$1 == p { print; found=1 } END { if (!found) exit 1 }' || true)"
  if [ -n "$group_line" ]; then
    printf '%s\n' "$group_line"
    return
  fi

  local artifact_subdir
  artifact_subdir="$(read_profiles | awk -F'|' -v p="$BUILD_TARGET" '$1 == p { print $2; found=1 } END { if (!found) exit 1 }' || true)"
  if [ -z "$artifact_subdir" ]; then
    echo "未知的编译目标：$BUILD_TARGET" >&2
    echo "请使用 profile_groups.conf 里的分组名、profiles.conf 里的 profile，或 all。" >&2
    exit 1
  fi
  printf '%s|%s|%s\n' "$BUILD_TARGET" "$artifact_subdir" "$BUILD_TARGET"
}

echo "========================================="
echo "  ImmortalWrt MT798x 25.12 编译"
echo "  源码: $REPO_URL $REPO_BRANCH"
echo "  开始时间: $(date)"
echo "========================================="

clone_openwrt

cd "$OPENWRT_DIR"
bash "$SCRIPT_DIR/01_prepare.sh"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

while IFS='|' read -r target artifact_subdir profiles; do
  echo ""
  echo "========== $target =========="
  echo "开始时间: $(date)"

  bash "$SCRIPT_DIR/05_validate_profile.sh" "$profiles"
  bash "$SCRIPT_DIR/04_make_profile_config.sh" "$profiles" .config
  bash "$SCRIPT_DIR/02_add_package.sh"
  make defconfig
  bash "$SCRIPT_DIR/06_validate_target_config.sh" "$profiles"
  bash "$SCRIPT_DIR/03_validate_packages.sh"

  make download -j"$DOWNLOAD_JOBS"
  make -j"$JOBS"

  profile_artifact_dir="$ARTIFACT_DIR/$target"
  mkdir -p "$profile_artifact_dir"
  find "bin/targets/$artifact_subdir" -maxdepth 1 -type f \
    \( -name '*initramfs*' -o -name '*squashfs*' -o -name '*factory*' -o -name '*sysupgrade*' -o -name '*preloader*' -o -name '*bl31*' -o -name '*fip*' -o -name '*gpt*' -o -name '*.manifest' \) \
    -exec cp -f {} "$profile_artifact_dir/" \;
  (
    cd "$profile_artifact_dir"
    find . -maxdepth 1 -type f ! -name sha256sums -printf '%P\0' | sort -z | xargs -0 sha256sum > sha256sums
  )

  count="$(find "$profile_artifact_dir" -type f | wc -l)"
  if [ "$count" -eq 0 ]; then
    echo "没有为 $target 收集到产物" >&2
    exit 1
  fi

  echo "完成 $target：$count 个文件"
done < <(resolve_targets)

echo ""
echo "========================================="
echo "  全部完成：$(date)"
echo "========================================="
find "$ARTIFACT_DIR" -mindepth 1 -maxdepth 2 -type f | sort
du -sh "$ARTIFACT_DIR"
