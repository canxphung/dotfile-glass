#!/bin/sh
# Cài vào prefix tạm rồi chạy thử config Lua với `hl` giả.

set -eu

cd "$(dirname "$0")/.."

lua=${LUA:-lua}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make -s install-session PREFIX="$tmp/prefix" SYSCONFDIR="$tmp/etc" >/dev/null
"$lua" tests/lua-smoke.lua "$tmp/prefix/share/glass/skel/glass/hyprland.lua"
