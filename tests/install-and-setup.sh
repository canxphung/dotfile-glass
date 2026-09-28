#!/bin/sh
# Cài Glass vào một prefix tạm rồi chạy glass-setup với HOME tạm.
# Kiểm tra: thay biến đường dẫn đủ, mọi đường dẫn tham chiếu đều tồn tại,
# glass-setup không ghi đè file người dùng, --force có sao lưu.

set -eu

cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

prefix=$tmp/prefix
glassdir=$prefix/share/glass
home=$tmp/home
mkdir -p "$home"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Chỉ phần không cần build Rust; glassd có test riêng (glassd-smoke.sh).
make -s install-session install-sddm PREFIX="$prefix" SYSCONFDIR="$tmp/etc" >/dev/null

# 1. Không còn placeholder nào.
if grep -rl '@GLASS_DATADIR@' "$prefix" "$tmp/etc"; then
    fail "còn @GLASS_DATADIR@ chưa thay"
fi

# 2. Mọi đường dẫn tới $glassdir được nhắc trong file cài đều tồn tại.
#    require("x") của Lua có thể bỏ đuôi .lua.
refs=$(grep -rhoE "$glassdir/[A-Za-z0-9_./-]*" "$prefix" "$tmp/etc" | sort -u)
for ref in $refs; do
    [ -e "$ref" ] || [ -e "$ref.lua" ] || fail "đường dẫn không tồn tại: $ref"
done

setup() {
    HOME=$home XDG_CONFIG_HOME=$home/.config XDG_STATE_HOME=$home/.local/state \
        "$prefix/bin/glass-setup" "$@"
}

# 3. Lần đầu tạo đủ file; file phân lớp phải nạp mặc định của Glass.
#    Riêng chromium-flags.conf đã có sẵn (file khởi tạo) thì giữ im lặng.
mkdir -p "$home/.config"
printf -- '--force-dark-mode\n' >"$home/.config/chromium-flags.conf"
out=$(setup)
case $out in *"bỏ qua 0"*) ;; *) fail "file khởi tạo có sẵn bị báo là lạ: $out" ;; esac
[ "$(cat "$home/.config/chromium-flags.conf")" = "--force-dark-mode" ] || fail "file khởi tạo có sẵn bị ghi đè"
for f in glass/hyprland.lua glass/hyprlock.conf glass/hypridle.conf glass/hyprpaper.conf kitty/kitty.conf; do
    [ -f "$home/.config/$f" ] || fail "glass-setup không tạo $f"
    grep -qF "$glassdir/" "$home/.config/$f" || fail "$f không nạp mặc định"
done
grep -q '^DefaultIM=bamboo$' "$home/.config/fcitx5/profile" || fail "profile fcitx5 không đặt Bamboo"
for f in idle.conf wallpaper.conf nightlight.conf theme/hyprland.lua theme/hyprlock.conf theme/kitty.conf theme/shell.json; do
    [ -f "$home/.local/state/glass/$f" ] || fail "glass-setup không chép file state $f"
done
grep -qF "$glassdir/wallpapers/aero-sky.jpg" "$home/.local/state/glass/wallpaper.conf" || fail "wallpaper.conf chưa thay đường dẫn"
grep -q -- '--enable-wayland-ime' "$home/.config/electron-flags.conf" || fail "thiếu cờ IME cho Electron"

# 4. Chạy lại không đổi gì, kể cả file người dùng đã sửa.
echo "-- sửa của người dùng" >>"$home/.config/glass/hyprland.lua"
before=$(cat "$home/.config/glass/hyprland.lua")
out=$(setup)
case $out in *"tạo 0, giữ 8"*) ;; *) fail "lần chạy thứ hai không idempotent: $out" ;; esac
[ "$(cat "$home/.config/glass/hyprland.lua")" = "$before" ] || fail "glass-setup ghi đè file đã sửa"

# 5. File lạ được giữ nguyên nếu không có --force.
printf 'font_size 14\n' >"$home/.config/kitty/kitty.conf"
out=$(setup)
case $out in *"bỏ qua 1"*) ;; *) fail "không báo file lạ: $out" ;; esac
[ "$(cat "$home/.config/kitty/kitty.conf")" = "font_size 14" ] || fail "file lạ bị sửa"

# 6. --force sao lưu rồi thay; không ghi xuyên symlink.
printf 'của dotfiles khác\n' >"$tmp/other-kitty.conf"
ln -sf "$tmp/other-kitty.conf" "$home/.config/kitty/kitty.conf"
setup --force >/dev/null
[ ! -L "$home/.config/kitty/kitty.conf" ] || fail "--force không thay symlink"
grep -qF "$glassdir/" "$home/.config/kitty/kitty.conf" || fail "--force không chép bản mẫu"
[ "$(cat "$tmp/other-kitty.conf")" = "của dotfiles khác" ] || fail "--force ghi xuyên symlink"
ls "$home/.local/state/glass/backup/"*/kitty/kitty.conf >/dev/null 2>&1 || fail "--force không sao lưu"

echo "install + glass-setup: ok"
