#!/bin/bash
set -e -o pipefail

CONFIG_FILE="${CONFIG_FILE:-.config}"
PACKAGE_CONF="${PACKAGE_CONF:-../package.conf}"

missing=()
requested=0

while IFS= read -r pkg || [ -n "$pkg" ]; do
  pkg="${pkg%$'\r'}"
  pkg="${pkg%%#*}"
  pkg="${pkg#"${pkg%%[![:space:]]*}"}"
  pkg="${pkg%"${pkg##*[![:space:]]}"}"
  [ -z "$pkg" ] && continue
  ((requested += 1))

  if ! grep -Fqx "CONFIG_PACKAGE_${pkg}=y" "$CONFIG_FILE"; then
    missing+=("$pkg")
  fi
done < "$PACKAGE_CONF"

if (( ${#missing[@]} > 0 )); then
  echo "make defconfig 后，下面这些请求的包没有被启用：" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "请检查包名、ImmortalWrt 25.12 分支支持情况和依赖关系。" >&2
  exit 1
fi

echo "已验证 $requested 个请求的包，全部已启用。"
