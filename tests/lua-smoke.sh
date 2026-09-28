#!/bin/sh
# Cài vào prefix tạm rồi chạy thử config Lua với `hl` giả, hai lần:
# khi chưa có file theme do glassd sinh (dùng bảng dự phòng) và khi đã có.

set -eu

cd "$(dirname "$0")/.."

lua=${LUA:-lua}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make -s install-session PREFIX="$tmp/prefix" SYSCONFDIR="$tmp/etc" >/dev/null
entry=$tmp/prefix/share/glass/skel/glass/hyprland.lua

# Danh sách biến glass-session chép vào systemd (xem session_env trong đó).
GLASS_SESSION_ENV=$(sed -n '/^session_env="/,/"$/p' bin/glass-session | tr -d '"' | sed 's/^session_env=//')
export GLASS_SESSION_ENV

HOME=$tmp/home XDG_STATE_HOME=$tmp/home/.local/state "$lua" tests/lua-smoke.lua "$entry"

mkdir -p "$tmp/home/.local/state"
cp -r "$tmp/prefix/share/glass/state" "$tmp/home/.local/state/glass"
HOME=$tmp/home XDG_STATE_HOME=$tmp/home/.local/state "$lua" tests/lua-smoke.lua "$entry"
