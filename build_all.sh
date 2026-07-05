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
JOBS="${JOBS:-2}"
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-8}"
BUILD_PROFILE="${BUILD_PROFILE:-all}"

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

while IFS='|' read -r profile artifact_subdir; do
  if [ "$BUILD_PROFILE" != "all" ] && [ "$BUILD_PROFILE" != "$profile" ]; then
    continue
  fi

  echo ""
  echo "========== $profile =========="
  echo "开始时间: $(date)"

  bash "$SCRIPT_DIR/05_validate_profile.sh" "$profile"
  bash "$SCRIPT_DIR/04_make_profile_config.sh" "$profile" .config
  bash "$SCRIPT_DIR/02_add_package.sh"
  make defconfig
  bash "$SCRIPT_DIR/06_validate_target_config.sh" "$profile"
  bash "$SCRIPT_DIR/03_validate_packages.sh"

  make download -j"$DOWNLOAD_JOBS"
  make -j"$JOBS"

  profile_artifact_dir="$ARTIFACT_DIR/$profile"
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
    echo "没有为 $profile 收集到产物" >&2
    exit 1
  fi

  echo "完成 $profile：$count 个文件"
done < <(read_profiles)

echo ""
echo "========================================="
echo "  全部完成：$(date)"
echo "========================================="
find "$ARTIFACT_DIR" -mindepth 1 -maxdepth 2 -type f | sort
du -sh "$ARTIFACT_DIR"
