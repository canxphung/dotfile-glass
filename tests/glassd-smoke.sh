#!/bin/sh
# Chạy glassd thật trên một session bus riêng, với HOME tạm. Các lệnh
# gsettings, hyprctl, systemctl, pkill được thay bằng stub ghi lại lời gọi,
# để kiểm tra glassd áp settings ra hệ thống đúng lúc, đúng lệnh.
# GLASS_SMOKE_LOG=1 để in log của glassd khi xong.

set -eu

cd "$(dirname "$0")/.."
repo=$(pwd)

if [ -z "${GLASS_SMOKE_INNER-}" ]; then
    cargo build -q --locked --manifest-path daemon/Cargo.toml
    exec env GLASS_SMOKE_INNER=1 dbus-run-session -- "$0" "$@"
fi

target=${CARGO_TARGET_DIR:-$repo/daemon/target}/debug
tmp=$(mktemp -d)
glassd_pid=
cleanup() {
    if [ -n "$glassd_pid" ]; then
        kill "$glassd_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    [ -f "$tmp/glassd.log" ] && sed 's/^/  glassd: /' "$tmp/glassd.log" >&2
    exit 1
}

# Dữ liệu cài đặt giống hệt gói, trong prefix tạm.
make -s install-session PREFIX="$tmp/prefix" SYSCONFDIR="$tmp/etc" >/dev/null
install -Dm644 -t "$tmp/prefix/share/glass/templates" theme/runtime/*.j2

# Stub: ghi lại lời gọi vào calls.log.
mkdir -p "$tmp/stubs"
for cmd in gsettings hyprctl systemctl pkill; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$cmd" "$tmp" >"$tmp/stubs/$cmd"
    chmod +x "$tmp/stubs/$cmd"
done
: >"$tmp/calls.log"

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="$tmp/run"
export GLASS_DATADIR="$tmp/prefix/share/glass"
export HYPRLAND_INSTANCE_SIGNATURE=test
export PATH="$tmp/stubs:$PATH"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

state=$XDG_STATE_HOME/glass
settings=$XDG_CONFIG_HOME/glass/settings.toml
ctl=$target/glassctl

GLASSD_LOG=debug "$target/glassd" >"$tmp/glassd.log" 2>&1 &
glassd_pid=$!

# Chờ glassd lấy được tên D-Bus.
i=0
until "$ctl" get version >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 50 ] || fail "glassd không lên sau 5 giây"
    kill -0 "$glassd_pid" 2>/dev/null || fail "glassd thoát sớm"
    sleep 0.1
done

called() { grep -qF -- "$1" "$tmp/calls.log"; }

# wait_for nhận biểu thức để eval mỗi lần thử, nên truyền trong nháy đơn.
wait_for() {
    i=0
    until eval "$1"; do
        i=$((i + 1))
        [ "$i" -lt 30 ] || fail "hết giờ chờ: $2"
        sleep 0.1
    done
}

# 1. Khởi động: tạo settings.toml từ bản mẫu, render file state, áp gsettings.
grep -q '^# Cài đặt của Glass' "$settings" || fail "settings.toml không lấy từ bản mẫu có comment"
for f in idle.conf wallpaper.conf nightlight.conf theme/hyprland.lua theme/hyprlock.conf theme/kitty.conf theme/shell.json; do
    [ -f "$state/$f" ] || fail "thiếu file state $f"
done
called "gsettings set org.gnome.desktop.interface color-scheme prefer-dark" || fail "không áp color-scheme"
called "systemctl --user stop glass-nightlight.service" || fail "không tắt night light lúc khởi động"
[ "$("$ctl" get appearance.palette)" = sky ] || fail "palette mặc định không phải sky"

# 2. Đổi palette: render lại theme, nạp lại Hyprland và kitty, giữ comment.
: >"$tmp/calls.log"
"$ctl" palette twilight
grep -q 'rgba(8b78e6bb)' "$state/theme/hyprland.lua" || fail "theme Hyprland chưa đổi sang twilight"
grep -q '^palette = "twilight"' "$settings" || fail "settings.toml chưa ghi palette"
grep -q '^# Palette màu Aero' "$settings" || fail "mất comment khi ghi settings.toml"
called "hyprctl reload" || fail "không nạp lại Hyprland"
called "pkill -USR1 -x -U" || fail "không báo kitty nạp lại"
if called "systemctl --user try-restart glass-idle.service"; then
    fail "đổi palette không được khởi động lại hypridle"
fi

# 3. Đổi thời gian khoá: chỉ đụng tới hypridle.
: >"$tmp/calls.log"
"$ctl" set idle.lock 600
grep -q 'timeout = 600' "$state/idle.conf" || fail "idle.conf chưa đổi"
called "systemctl --user try-restart glass-idle.service" || fail "không khởi động lại hypridle"
if called "hyprctl reload"; then fail "đổi idle không được nạp lại Hyprland"; fi

# 4. Giá trị sai bị từ chối, settings giữ nguyên.
if "$ctl" set idle.lock abc 2>/dev/null; then fail "nhận giá trị sai kiểu"; fi
if "$ctl" palette khong-co 2>/dev/null; then fail "nhận palette không tồn tại"; fi
if "$ctl" wallpaper /khong/co.jpg 2>/dev/null; then fail "nhận hình nền không tồn tại"; fi
[ "$("$ctl" get idle.lock)" = 600 ] || fail "giá trị cũ bị mất sau lần đặt sai"

# 5. Hình nền: đổi qua IPC của hyprpaper.
: >"$tmp/calls.log"
cp wallpapers/aero-sky.jpg "$tmp/hinh nen.jpg"
"$ctl" wallpaper "$tmp/hinh nen.jpg"
grep -qF "path = $tmp/hinh nen.jpg" "$state/wallpaper.conf" || fail "wallpaper.conf chưa đổi"
called "hyprctl hyprpaper wallpaper ,$tmp/hinh nen.jpg,cover" || fail "không đổi hình nền qua IPC"

# 6. Sửa tay settings.toml: glassd tự đọc lại.
: >"$tmp/calls.log"
sed -i 's/^enabled = false/enabled = true/' "$settings"
# shellcheck disable=SC2016 # eval trong wait_for mới mở rộng biến
wait_for '[ "$("$ctl" get night_light.enabled)" = true ]' "glassd đọc lại night_light.enabled"
wait_for 'called "systemctl --user restart glass-nightlight.service" || called "systemctl --user start glass-nightlight.service"' "bật night light"

# 7. File sửa hỏng: giữ settings cũ, từ chối ghi đè; sửa lại thì chạy tiếp.
cp "$settings" "$tmp/settings.good"
printf 'version = 1\n[appearance\n' >"$settings"
sleep 0.5
[ "$("$ctl" get idle.lock)" = 600 ] || fail "settings cũ bị mất khi file hỏng"
if "$ctl" set idle.dim 10 2>/dev/null; then fail "ghi đè file người dùng đang sửa hỏng"; fi
cp "$tmp/settings.good" "$settings"
sleep 0.5
"$ctl" set idle.dim 10 || fail "không đổi được sau khi sửa file"

# 8. Socket cho shell: hello, set, sự kiện changed.
python3 - "$XDG_RUNTIME_DIR/glass/glassd.sock" <<'EOF' || fail "socket không đúng giao thức"
import json, socket, sys

sock = socket.socket(socket.AF_UNIX)
sock.settimeout(5)
sock.connect(sys.argv[1])
f = sock.makefile("rw", encoding="utf-8")

hello = json.loads(f.readline())
assert hello["event"] == "hello", hello
assert hello["settings"]["appearance.palette"] == "twilight", hello
assert "sky" in hello["palettes"], hello

f.write(json.dumps({"id": 7, "method": "set", "key": "appearance.color_scheme", "value": "light"}) + "\n")
f.flush()
seen = {}
while "reply" not in seen or "event" not in seen:
    msg = json.loads(f.readline())
    if msg.get("id") == 7:
        assert msg["ok"], msg
        seen["reply"] = msg
    elif msg.get("event") == "changed":
        assert msg == {"event": "changed", "key": "appearance.color_scheme", "value": "light"}, msg
        seen["event"] = msg

f.write(json.dumps({"id": 8, "method": "set", "key": "idle.lock", "value": "abc"}) + "\n")
f.flush()
msg = json.loads(f.readline())
assert msg["id"] == 8 and not msg["ok"] and msg["error"], msg
EOF
called "gsettings set org.gnome.desktop.interface color-scheme prefer-light" || fail "không áp color-scheme light"

# 9. Bản thứ hai phải thoát ngay, không đụng vào socket của bản đang chạy.
if "$target/glassd" >"$tmp/second.log" 2>&1; then fail "glassd thứ hai không thoát"; fi
grep -q "đang chạy rồi" "$tmp/second.log" || fail "glassd thứ hai không báo đúng lý do: $(cat "$tmp/second.log")"
python3 - "$XDG_RUNTIME_DIR/glass/glassd.sock" <<'EOF' || fail "socket hỏng sau khi chạy glassd thứ hai"
import json, socket, sys
sock = socket.socket(socket.AF_UNIX)
sock.settimeout(5)
sock.connect(sys.argv[1])
assert json.loads(sock.makefile().readline())["event"] == "hello"
EOF

# 10. Dừng gọn: xoá socket.
kill "$glassd_pid"
wait "$glassd_pid" 2>/dev/null || true
glassd_pid=
[ ! -e "$XDG_RUNTIME_DIR/glass/glassd.sock" ] || fail "còn socket sau khi dừng"
if grep -q 'ERROR' "$tmp/glassd.log"; then
    sed 's/^/  glassd: /' "$tmp/glassd.log" >&2
    fail "glassd ghi log ERROR"
fi

[ -n "${GLASS_SMOKE_LOG-}" ] && sed 's/^/  glassd: /' "$tmp/glassd.log"
echo "glassd: ok"
