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
  echo "The following requested packages were not enabled after make defconfig:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Check package names, branch support, and dependencies for ImmortalWrt 25.12." >&2
  exit 1
fi

echo "Validated $requested requested packages; all are enabled."
