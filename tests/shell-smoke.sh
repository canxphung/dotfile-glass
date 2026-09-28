#!/bin/sh
# Chạy shell QML thật trên sway headless (không cần GPU), với session bus
# riêng, HOME tạm và IPC Hyprland giả (tests/fake-hyprland.py). Gõ phím
# thật bằng wtype, gửi thông báo thật bằng notify-send, rồi kiểm tra trạng
# thái qua IPC của shell. Lệnh bên ngoài (systemd-run, systemctl,
# brightnessctl, xdg-open) được thay bằng stub ghi lại lời gọi.
#
# Thiếu quickshell, sway, wtype... thì bỏ qua, trừ khi đặt
# GLASS_SHELL_SMOKE_REQUIRED=1 (make test-shell, CI).
#
# Biến môi trường:
#   QS                  lệnh quickshell (mặc định qs)
#   GLASS_SMOKE_SHOTS   thư mục lưu ảnh chụp màn hình từng bước (cần grim)
#   GLASS_SMOKE_LOG=1   in log của shell khi xong

# wait_for nhận biểu thức để eval mỗi lần thử, nên các biến trong nháy đơn
# là cố ý.
# shellcheck disable=SC2016

set -eu

cd "$(dirname "$0")/.."
repo=$(pwd)

if [ -z "${GLASS_SMOKE_INNER-}" ]; then
    missing=
    for cmd in "${QS:-qs}" sway wtype notify-send dbus-run-session python3; do
        command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
    done
    if [ -n "$missing" ]; then
        if [ -n "${GLASS_SHELL_SMOKE_REQUIRED-}" ]; then
            printf 'FAIL: thiếu%s\n' "$missing" >&2
            exit 1
        fi
        printf 'shell: bỏ qua (thiếu%s)\n' "$missing"
        exit 0
    fi
    exec env GLASS_SMOKE_INNER=1 dbus-run-session -- "$0" "$@"
fi

tmp=$(mktemp -d)
pids=
cleanup() {
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
    rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    [ -f "$tmp/shell.log" ] && sed 's/^/  shell: /' "$tmp/shell.log" >&2
    exit 1
}

wait_for() {
    i=0
    until eval "$1"; do
        i=$((i + 1))
        [ "$i" -lt 100 ] || fail "hết giờ chờ: $2"
        sleep 0.1
    done
}

# Cài giống gói vào prefix tạm.
prefix=$tmp/prefix
make -s install-session install-shell PREFIX="$prefix" SYSCONFDIR="$tmp/etc" >/dev/null

# Stub: ghi lại lời gọi vào calls.log.
stubs=$tmp/stubs
mkdir -p "$stubs"
for cmd in systemd-run systemctl xdg-open; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$cmd" "$tmp" >"$stubs/$cmd"
done
cat >"$stubs/brightnessctl" <<EOF
#!/bin/sh
echo "brightnessctl \$*" >> "$tmp/calls.log"
case "\$*" in *info*) echo "intel_backlight,backlight,1680,70%,2400" ;; esac
EOF
# glass-shell gọi "qs"; cho phép thay bằng bản build riêng qua biến QS.
if [ -n "${QS-}" ]; then
    printf '#!/bin/sh\nexec %s "$@"\n' "$QS" >"$stubs/qs"
fi
chmod +x "$stubs"/*
: >"$tmp/calls.log"

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="$tmp/run"
export PATH="$stubs:$prefix/bin:$PATH"
export HYPRLAND_INSTANCE_SIGNATURE=glass-test
export QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software LC_ALL=C.UTF-8
unset WAYLAND_DISPLAY DISPLAY
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

glass-setup --quiet

# Một app để tìm và mở từ start menu, ghim sẵn trên taskbar.
mkdir -p "$XDG_DATA_HOME/applications" "$XDG_STATE_HOME/glass/shell"
cat >"$XDG_DATA_HOME/applications/glass-test.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Trình duyệt thử
GenericName=Trình duyệt web
Exec=glass-test-app --url %U
Icon=web-browser
EOF
printf '{"launches": {}, "pinned": ["glass-test"]}\n' >"$XDG_STATE_HOME/glass/shell/apps.json"

# Compositor: sway không cần GPU, không cần thiết bị nhập.
cat >"$tmp/sway.conf" <<'EOF'
output HEADLESS-1 resolution 1280x720 bg #000000 solid_color
default_border none
xwayland disable
EOF
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
    sway --config "$tmp/sway.conf" >"$tmp/sway.log" 2>&1 &
pids="$pids $!"
wait_for '[ -S "$XDG_RUNTIME_DIR/wayland-1" ]' "sway chạy"
export WAYLAND_DISPLAY=wayland-1

python3 tests/fake-hyprland.py HEADLESS-1 "$tmp/dispatch.log" >"$tmp/hyprland.log" 2>&1 &
pids="$pids $!"
wait_for '[ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" ]' "IPC Hyprland giả"

glass-shell >"$tmp/shell.log" 2>&1 &
pids="$pids $!"
wait_for 'grep -q "Configuration Loaded" "$tmp/shell.log"' "shell nạp xong"

call() { glass-shell "$@" 2>/dev/null; }
called() { grep -qF -- "$1" "$tmp/calls.log"; }

shot() {
    if [ -n "${GLASS_SMOKE_SHOTS-}" ] && command -v grim >/dev/null 2>&1; then
        mkdir -p "$GLASS_SMOKE_SHOTS"
        sleep 0.4
        grim "$GLASS_SMOKE_SHOTS/$1.png"
    fi
}

# wtype mở một bàn phím ảo mới mỗi lần chạy, và phím gõ ngay lúc app đang
# nhận keymap mới hay bị mất, nên luôn mở đầu bằng một phím Shift vô hại
# rồi chờ một chút.
type_keys() { wtype -k Shift_L -s 300 "$@"; }

# 1. Taskbar: app ghim có mặt, workspace của Hyprland giả được đọc.
wait_for '[ "$(call shell tasks)" = "glass-test 0" ]' "taskbar có app ghim"
[ "$(call shell palette)" = sky ] || fail "palette ban đầu không phải sky"
shot 1-taskbar

# 2. Start menu: gõ không dấu tìm ra app có dấu, Enter mở app qua
#    glass-session run → systemd-run trong scope riêng.
call startmenu open
wait_for '[ "$(call startmenu isOpen)" = true ]' "start menu mở"
type_keys "trinh duyet"
wait_for '[ "$(call startmenu entries)" = "Trình duyệt thử" ]' "tìm thấy app"
shot 2-startmenu
type_keys -k Return
wait_for 'called "glass-test-app"' "mở app từ start menu"
called "systemd-run --user --scope --quiet --collect --slice=app.slice --unit=app-glass-glass\\x2dtest-" ||
    fail "app không chạy trong scope riêng: $(cat "$tmp/calls.log")"
called "-- glass-test-app --url" || fail "lệnh mở app sai (field code %U phải bị bỏ): $(cat "$tmp/calls.log")"
wait_for '[ "$(call startmenu isOpen)" = false ]' "start menu đóng sau khi mở app"
wait_for 'grep -q "\"glass-test\": 1" "$XDG_STATE_HOME/glass/shell/apps.json"' "đếm số lần mở"

# 3. Không tìm thấy gì thì danh sách rỗng; Esc đóng menu.
call startmenu open
wait_for '[ "$(call startmenu isOpen)" = true ]' "start menu mở lại"
type_keys "khongcoappnay"
wait_for '[ -z "$(call startmenu entries)" ]' "tìm không ra"
type_keys -k Escape
wait_for '[ "$(call startmenu isOpen)" = false ]' "Esc đóng start menu"

# 4. Thông báo: hiện popup, giữ trong lịch sử, không làm phiền thì không hiện.
notify-send --app-name Test "Xin chào" "Nội dung <b>đậm</b>"
wait_for '[ "$(call notifications popups)" = 1 ]' "popup thông báo"
notify-send --urgency critical --app-name Pin "Pin yếu" "Còn 5%"
wait_for '[ "$(call notifications popups)" = 2 ]' "popup thông báo khẩn"
shot 3-notifications
call notifications toggleDnd
notify-send --app-name Test "Lúc không làm phiền"
wait_for '[ "$(call notifications history)" = 3 ]' "thông báo vào lịch sử"
[ "$(call notifications popups)" = 2 ] || fail "đang không làm phiền mà vẫn hiện popup"
call notifications toggleDnd
call notifications dismissAll
wait_for '[ "$(call notifications history)" = 0 ] && [ "$(call notifications popups)" = 0 ]' "đóng hết thông báo"

# 5. OSD độ sáng: đọc mức từ brightnessctl.
call osd brightness
wait_for 'called "brightnessctl --machine-readable --class=backlight info"' "đọc độ sáng"
wait_for '[ "$(call osd isVisible)" = true ]' "hiện OSD"
shot 4-osd

# 6. Menu nguồn: phím mũi tên + Enter chọn "Ngủ".
call powermenu open
wait_for '[ "$(call powermenu isOpen)" = true ]' "menu nguồn mở"
shot 5-powermenu
type_keys -k Down -k Down -k Return
wait_for 'called "systemctl suspend"' "chọn Ngủ trong menu nguồn"
wait_for '[ "$(call powermenu isOpen)" = false ]' "menu nguồn đóng"

# 7. Đổi palette: glassd ghi lại shell.json, shell đổi màu ngay.
python3 - "$XDG_STATE_HOME/glass/theme/shell.json" "$repo/theme/palettes/twilight.toml" <<'EOF'
import json, os, sys, tomllib
path, palette = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding="utf-8"))
with open(palette, "rb") as f:
    twilight = tomllib.load(f)
for section in ("glass", "text", "surface", "accent", "state"):
    data["palette"][section].update(twilight[section])
data["palette"]["name"] = "twilight"
with open(path + ".tmp", "w", encoding="utf-8") as f:
    json.dump(data, f)
os.replace(path + ".tmp", path)
EOF
wait_for '[ "$(call shell palette)" = twilight ]' "shell đổi palette"
[ "$(call shell tint)" = "#8b78e6" ] || fail "màu kính chưa đổi: $(call shell tint)"

# 8. Cửa sổ thật trên taskbar (nếu có foot).
if command -v foot >/dev/null 2>&1; then
    foot --app-id foot --title "Cửa sổ thử" >/dev/null 2>&1 &
    pids="$pids $!"
    wait_for 'call shell tasks | grep -qx "[^ ]*foot[^ ]* 1"' "cửa sổ foot hiện trên taskbar"
    shot 6-window
elif [ -n "${GLASS_SHELL_SMOKE_REQUIRED-}" ]; then
    fail "thiếu foot để thử cửa sổ trên taskbar"
fi

# 9. Log không có cảnh báo nào của QML. Bỏ qua các cảnh báo do môi trường
#    test: không có PipeWire, không có system bus (UPower), sway không có
#    giao thức riêng của Hyprland; và cảnh báo nội bộ của QtWayland khi
#    focus bàn phím chuyển giữa các bề mặt.
problems=$(grep -E ' (WARN|ERROR|CRIT|FATAL)' "$tmp/shell.log" |
    grep -v -e 'quickshell.service.pipewire' \
        -e 'quickshell.service.upower' \
        -e 'hyprland-toplevel-mapping' \
        -e 'qt.qpa.wayland.textinput' || true)
if [ -n "$problems" ]; then
    fail "shell ghi cảnh báo:
$problems"
fi

[ -n "${GLASS_SMOKE_LOG-}" ] && sed 's/^/  shell: /' "$tmp/shell.log"
echo "shell: ok"
