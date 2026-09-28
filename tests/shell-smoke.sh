#!/bin/sh
# Chạy shell QML thật trên sway headless (không cần GPU), với session bus
# và system bus riêng, HOME tạm và IPC Hyprland giả (tests/fake-hyprland.py).
# Gõ phím thật bằng wtype, gửi thông báo thật bằng notify-send, rồi kiểm tra
# trạng thái qua IPC của shell. Lệnh bên ngoài (systemd-run, systemctl,
# brightnessctl, xdg-open, hyprctl, gsettings) được thay bằng stub ghi lại
# lời gọi.
#
# Có thêm các phần sau thì test luôn phần đó:
#   - glassd (build bằng cargo) và python dbus-next: NetworkManager và BlueZ
#     giả trên system bus riêng (tests/fake-networkmanager.py,
#     tests/fake-bluez.py), hộp thoại mật khẩu Wi-Fi và ghép nối Bluetooth
#     qua agent của glassd;
#   - pipewire, wireplumber: loa ảo, âm lượng, OSD.
#
# Thiếu quickshell, sway, wtype... (hay các phần trên) thì bỏ qua, trừ khi
# đặt GLASS_SHELL_SMOKE_REQUIRED=1 (make test-shell, CI).
#
# Biến môi trường:
#   QS                  lệnh quickshell (mặc định qs)
#   GLASSD              file glassd có sẵn (mặc định build bằng cargo)
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
    if [ -z "${GLASSD-}" ] && command -v cargo >/dev/null 2>&1; then
        cargo build -q --locked --manifest-path daemon/Cargo.toml
        GLASSD=${CARGO_TARGET_DIR:-$repo/daemon/target}/debug/glassd
    fi
    exec env GLASS_SMOKE_INNER=1 GLASSD="${GLASSD-}" dbus-run-session -- "$0" "$@"
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
    for log in sway hyprland glassd nm bluez shell; do
        [ -s "$tmp/$log.log" ] && sed "s/^/  $log: /" "$tmp/$log.log" >&2
    done
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

# Phần nào có thì test phần đó (xem đầu file).
optional() {
    if [ -n "${GLASS_SHELL_SMOKE_REQUIRED-}" ]; then
        fail "thiếu $1"
    fi
    printf 'shell: bỏ qua phần %s (thiếu %s)\n' "$2" "$1"
}
agents=
if [ -z "${GLASSD-}" ] || [ ! -x "$GLASSD" ]; then
    optional "glassd (cần cargo)" "Wi-Fi/Bluetooth"
elif ! python3 -c 'import dbus_next' 2>/dev/null; then
    optional "python dbus-next" "Wi-Fi/Bluetooth"
else
    agents=1
fi
pipewire=
if command -v pipewire >/dev/null 2>&1 && command -v wireplumber >/dev/null 2>&1; then
    pipewire=1
else
    optional "pipewire, wireplumber" "âm thanh"
fi

# Cài giống gói vào prefix tạm.
prefix=$tmp/prefix
make -s install-session install-shell PREFIX="$prefix" SYSCONFDIR="$tmp/etc" >/dev/null
install -Dm644 -t "$prefix/share/glass/templates" theme/runtime/*.j2

# Stub: ghi lại lời gọi vào calls.log.
stubs=$tmp/stubs
mkdir -p "$stubs"
for cmd in systemd-run systemctl xdg-open hyprctl gsettings; do
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
# Tên socket (wayland-0, wayland-1...) tuỳ phiên bản libwayland.
wayland_socket() {
    for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]; do
        if [ -S "$s" ]; then
            echo "${s##*/}"
            return 0
        fi
    done
    return 1
}
wait_for 'wayland_socket >/dev/null' "sway chạy"
WAYLAND_DISPLAY=$(wayland_socket)
export WAYLAND_DISPLAY

python3 tests/fake-hyprland.py HEADLESS-1 "$tmp/dispatch.log" >"$tmp/hyprland.log" 2>&1 &
pids="$pids $!"
wait_for '[ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" ]' "IPC Hyprland giả"

# System bus riêng cho NetworkManager, BlueZ giả và agent của glassd.
DBUS_SYSTEM_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address=1 --print-pid=3 3>"$tmp/sysbus.pid" 2>/dev/null)
export DBUS_SYSTEM_BUS_ADDRESS
pids="$pids $(cat "$tmp/sysbus.pid")"

if [ -n "$agents" ]; then
    python3 tests/fake-networkmanager.py "$tmp/nm.log" >"$tmp/nm.out" 2>&1 &
    pids="$pids $!"
    python3 tests/fake-bluez.py "$tmp/bluez.log" >"$tmp/bluez.out" 2>&1 &
    pids="$pids $!"
    GLASS_DATADIR="$prefix/share/glass" GLASSD_LOG=debug "$GLASSD" >"$tmp/glassd.log" 2>&1 &
    pids="$pids $!"
    wait_for '[ -S "$XDG_RUNTIME_DIR/glass/glassd.sock" ]' "glassd mở socket"
    wait_for 'grep -qx "agent io.github.canxphung.glass" "$tmp/nm.log" 2>/dev/null' "glassd đăng ký agent với NetworkManager"
    wait_for 'grep -qx "default agent" "$tmp/bluez.log" 2>/dev/null' "glassd đăng ký agent với BlueZ"
fi

if [ -n "$pipewire" ]; then
    pipewire >"$tmp/pipewire.log" 2>&1 &
    pids="$pids $!"
    wait_for '[ -S "$XDG_RUNTIME_DIR/pipewire-0" ]' "PipeWire chạy"
    wireplumber >"$tmp/wireplumber.log" 2>&1 &
    pids="$pids $!"
    pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=loa-thu node.description="Loa thử" media.class=Audio/Sink object.linger=true audio.position=[FL FR] }' >/dev/null
fi

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

# 9. Control center: mở từ IPC, sang trang con, Esc lùi về rồi đóng.
call controlcenter open main
wait_for '[ "$(call controlcenter isOpen)" = true ]' "control center mở"
shot 7-controlcenter
call controlcenter open audio
wait_for '[ "$(call controlcenter page)" = audio ]' "sang trang âm thanh"
type_keys -k Escape
wait_for '[ "$(call controlcenter page)" = main ]' "Esc về trang chính"
type_keys -k Escape
wait_for '[ "$(call controlcenter isOpen)" = false ]' "Esc đóng control center"

# 10. Âm thanh qua PipeWire thật: shell thấy loa ảo, đổi âm lượng thật
#     (wpctl đọc lại được), tắt tiếng, hiện OSD.
if [ -n "$pipewire" ]; then
    wait_for '[ "$(call audio sinks)" = "* Loa thử" ]' "shell thấy loa PipeWire"
    # OSD bỏ qua các lần đổi ngay sau khi có loa mới.
    sleep 2
    call audio setVolume 35
    wait_for 'wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -qx "Volume: 0.35"' "đặt âm lượng PipeWire"
    wait_for '[ "$(call osd isVisible)" = true ]' "OSD âm lượng"
    [ "$(call osd level)" = 35 ] || fail "OSD hiện mức $(call osd level), không phải 35"
    shot 8-volume
    call audio toggleMute
    wait_for 'wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED' "tắt tiếng"
    call audio toggleMute
fi

# 11. Wi-Fi qua NetworkManager giả và agent của glassd: mở trang Wi-Fi (bật
#     quét), nối mạng có mật khẩu, gõ sai thì được hỏi lại, gõ đúng thì
#     nối được; Esc huỷ thì NetworkManager báo thiếu mật khẩu.
if [ -n "$agents" ]; then
    wait_for '[ "$(call prompts connected)" = true ]' "shell nối với glassd"
    call controlcenter open wifi
    wait_for 'call network list | grep -q "^Nhà Mình"' "thấy mạng khi quét"
    call network connect "Nhà Mình"
    wait_for 'call prompts current | grep -q "\"ssid\":\"Nhà Mình\""' "hộp thoại mật khẩu Wi-Fi"
    shot 9-wifi-password
    type_keys "sai-roi" -k Return
    wait_for 'call prompts current | grep -q "\"retry\":true"' "hỏi lại khi sai mật khẩu"
    type_keys "matkhau123" -k Return
    wait_for '[ "$(call network status)" = "Nhà Mình" ]' "nối Wi-Fi"
    grep -qx "secrets Nhà Mình flags=3" "$tmp/nm.log" || fail "lần hỏi lại thiếu cờ REQUEST_NEW"
    shot 10-wifi-connected

    call network connect "Hàng Xóm"
    wait_for 'call prompts current | grep -q "Hàng Xóm"' "hộp thoại mật khẩu mạng thứ hai"
    type_keys -k Escape
    wait_for 'grep -qx "failed Hàng Xóm reason=7" "$tmp/nm.log"' "Esc huỷ kết nối"
    wait_for '[ -z "$(call prompts current)" ]' "hộp thoại đóng"

    # 12. Bluetooth qua BlueZ giả: tìm thiết bị, ghép nối có xác nhận mã
    #     (Enter), rồi tin cậy và kết nối luôn; thiết bị cần gõ mã thì hộp
    #     thoại hiện mã tự đóng khi ghép nối xong.
    call controlcenter open bluetooth
    wait_for 'call bluetooth list | grep -q "^Loa Phòng Khách"' "tìm thấy thiết bị Bluetooth"
    call bluetooth pair "Loa Phòng Khách"
    wait_for 'call prompts current | grep -q "\"code\":\"123456\""' "hộp thoại xác nhận mã"
    shot 11-bluetooth-confirm
    type_keys -k Return
    wait_for 'grep -qx "connected Loa Phòng Khách" "$tmp/bluez.log"' "ghép nối rồi kết nối"
    grep -qx "trusted Loa Phòng Khách yes" "$tmp/bluez.log" || fail "không tin cậy thiết bị sau khi ghép nối"
    call bluetooth pair "Bàn phím Glass"
    wait_for 'call prompts current | grep -q "\"code\":\"654321\""' "hộp thoại hiện mã"
    wait_for 'grep -qx "paired Bàn phím Glass" "$tmp/bluez.log"' "ghép nối bàn phím"
    wait_for '[ -z "$(call prompts current)" ]' "hộp thoại hiện mã tự đóng"
    shot 12-bluetooth
    # Như khay của Windows: đang ở trang con, bật/tắt lần nữa là đóng.
    call controlcenter toggle
    wait_for '[ "$(call controlcenter isOpen)" = false ]' "toggle đóng control center từ trang con"
fi

# 13. Log không có cảnh báo nào của QML. Bỏ qua các cảnh báo do môi trường
#     test: không có UPower, power-profiles-daemon (hay PipeWire), sway
#     không có giao thức riêng của Hyprland; và cảnh báo nội bộ của
#     QtWayland khi sway chuyển focus bàn phím giữa các bề mặt.
[ -n "$pipewire" ] || no_pipewire='quickshell.service.pipewire'
problems=$(grep -E ' (WARN|ERROR|CRIT|FATAL)' "$tmp/shell.log" |
    grep -v -e "${no_pipewire:-^$}" \
        -e 'quickshell.service.upower' \
        -e 'quickshell.service.powerprofiles' \
        -e 'Could not launch service org.freedesktop.UPower' \
        -e 'hyprland-toplevel-mapping' \
        -e 'qt.qpa.wayland.textinput' \
        -e 'Ignoring unexpected wl_keyboard.leave event' || true)
if [ -n "$problems" ]; then
    fail "shell ghi cảnh báo:
$problems"
fi

[ -n "${GLASS_SMOKE_LOG-}" ] && sed 's/^/  shell: /' "$tmp/shell.log"
echo "shell: ok"
