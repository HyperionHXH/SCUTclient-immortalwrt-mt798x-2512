#!/bin/bash
set -e -o pipefail

CONFIG_FILE="${CONFIG_FILE:-.config}"
PACKAGE_CONF="${PACKAGE_CONF:-../package.conf}"

declare -A seen=()

while IFS= read -r pkg || [ -n "$pkg" ]; do
  pkg="${pkg%$'\r'}"
  pkg="${pkg%%#*}"
  pkg="${pkg#"${pkg%%[![:space:]]*}"}"
  pkg="${pkg%"${pkg##*[![:space:]]}"}"

  [ -z "$pkg" ] && continue

  if [[ "$pkg" =~ [[:space:]] ]] || ! [[ "$pkg" =~ ^[A-Za-z0-9_.+@-]+$ ]]; then
    echo "Invalid package.conf entry: '$pkg'" >&2
    exit 1
  fi

  if [[ -n "${seen[$pkg]:-}" ]]; then
    echo "Duplicate package.conf entry: '$pkg'" >&2
    exit 1
  fi
  seen[$pkg]=1

  echo "CONFIG_PACKAGE_${pkg}=y"
done < "$PACKAGE_CONF" >> "$CONFIG_FILE"
