#!/usr/bin/env bash
set -euo pipefail

controller="${1:?用法：validate_scutclient.sh <scutclient.lua>}"

fail() {
  echo "scutclient 兼容校验失败：$*" >&2
  exit 1
}

[ -f "$controller" ] || fail "缺少控制器文件 $controller"

grep -Fq 'local http = require "luci.http"' "$controller" || fail "http 不是局部变量"
grep -Fq 'local sys = require "luci.sys"' "$controller" || fail "sys 不是局部变量"
grep -Fq 'local luci_template = require "luci.template"' "$controller" || \
  fail "luci.template 不是局部变量"
grep -Fq 'local function file_exists(path)' "$controller" || fail "缺少文件检查函数"
grep -Fq 'local client_log' "$controller" || fail "client_log 不是局部变量"
grep -Fq 'template("scutclient/logs")' "$controller" || fail "日志页面路由缺失"

! grep -Fq 'require "nixio.fs"' "$controller" || fail "仍依赖 25.12 不应使用的 nixio.fs"
! grep -Eq '(^|[^[:alnum:]_])fs\.' "$controller" || fail "仍有 fs 全局调用"
! grep -Eq '^[[:space:]]*luci\.(http|sys|template)\.' "$controller" || \
  fail "仍直接使用不可靠的 luci 全局变量"
! grep -Fq 'local template = require "luci.template"' "$controller" || \
  fail "局部变量遮蔽了 LuCI dispatcher 的 template 路由函数"

echo "scutclient 现代 LuCI 兼容校验通过。"
