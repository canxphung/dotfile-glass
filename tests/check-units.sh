#!/bin/sh
# Kiểm tra cú pháp các unit systemd user bằng systemd-analyze.
# Máy CI không cài hypridle, hyprpaper, hyprsunset, glassd, glass-shell nên
# bỏ qua lỗi "not executable" của đúng các lệnh đó; mọi lỗi khác đều làm
# test thất bại.

set -eu

cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Vài unit có @BINDIR@, thay giống lúc cài.
mkdir -p "$tmp/units" "$tmp/run"
for f in session/systemd/* daemon/data/glassd.service daemon/data/glass-nightlight.service; do
    sed 's|@BINDIR@|/usr/bin|g' "$f" >"$tmp/units/${f##*/}"
done

output=$(XDG_RUNTIME_DIR=$tmp/run systemd-analyze --user verify "$tmp"/units/* 2>&1 || true)

unexpected=$(printf '%s\n' "$output" |
    grep -v -e '^$' \
        -e 'Failed to connect to system bus' \
        -e 'Command /usr/bin/hypridle is not executable' \
        -e 'Command /usr/bin/hyprpaper is not executable' \
        -e 'Command /usr/bin/hyprsunset is not executable' \
        -e 'Command /usr/bin/glassd is not executable' \
        -e 'Command /usr/bin/glass-shell is not executable' || true)

if [ -n "$unexpected" ]; then
    printf '%s\n' "$unexpected" >&2
    exit 1
fi

echo "units: ok"
