#!/bin/sh
# Kiểm tra cú pháp các unit systemd user bằng systemd-analyze.
# Máy CI không cài hypridle/hyprpaper nên bỏ qua lỗi "not executable"
# của đúng các lệnh đó; mọi lỗi khác đều làm test thất bại.

set -eu

cd "$(dirname "$0")/.."

runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT

output=$(XDG_RUNTIME_DIR=$runtime systemd-analyze --user verify session/systemd/* 2>&1 || true)

unexpected=$(printf '%s\n' "$output" |
    grep -v -e '^$' \
        -e 'Failed to connect to system bus' \
        -e 'Command /usr/bin/hypridle is not executable' \
        -e 'Command /usr/bin/hyprpaper is not executable' || true)

if [ -n "$unexpected" ]; then
    printf '%s\n' "$unexpected" >&2
    exit 1
fi

echo "units: ok"
