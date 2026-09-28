# Glass

Desktop phong cách Aero (kính mờ kiểu Windows 7) chạy trên Hyprland, tối ưu cho CachyOS.

Glass không phải một bộ dotfile để chép tay: nó được đóng gói bằng pacman, có phiên đăng nhập riêng ("Glass" trong SDDM) và không đụng vào config Hyprland khác bạn đang có.

## Trạng thái

**Xong giai đoạn 3** trên 5. Đăng nhập được vào phiên Glass với:

- Hyprland (config Lua) có khung cửa sổ kính kiểu Aero: viền gradient, vệt sáng mép trong, bóng đổ, blur
- Màn hình khoá (hyprlock), xử lý khi rảnh (hypridle), hình nền (hyprpaper)
- Phiên chạy qua systemd, có portal, polkit agent, keyring
- SDDM chạy greeter trên Wayland
- Kitty trong suốt theo palette Aero Sky
- Gõ tiếng Việt bằng fcitx5 + Bamboo (Telex), bật/tắt bằng `CTRL + Space`
- **glassd**: daemon settings viết bằng Rust. Đổi palette (Aero Sky, Aero Twilight), hình nền, font, chế độ sáng/tối, thời gian khoá máy, night light bằng `glassctl` hoặc sửa `settings.toml`; mọi thứ đổi ngay, không cần đăng xuất
- **Shell** (Quickshell): taskbar kính kiểu Windows 7 với nút Start, app ghim và cửa sổ gộp theo app, workspace, khay hệ thống, âm lượng, pin, đồng hồ + lịch; start menu hai cột, tìm app không cần gõ dấu; thông báo; OSD âm lượng/độ sáng; menu khoá / đăng xuất / ngủ / tắt máy

Chưa có control center (Wi-Fi, Bluetooth, âm thanh chi tiết) và theme cho app GTK/Qt. Xem lộ trình trong [docs/architecture.md](docs/architecture.md).

## Cài đặt (CachyOS / Arch)

Cần Hyprland 0.56 và Quickshell 0.3 trở lên.

```sh
git clone https://github.com/canxphung/dotfile-glass
cd dotfile-glass/pkg
makepkg -si
glass-doctor
```

Sau đó đăng xuất, chọn phiên **Glass** ở màn hình đăng nhập. Lần đăng nhập đầu, Glass tạo config của bạn trong `~/.config/glass/`.

Trước khi dùng hằng ngày, nên chạy qua [docs/testing.md](docs/testing.md).

## Tuỳ chỉnh

Phần lớn chỉnh qua `glassctl` (hoặc sửa `~/.config/glass/settings.toml`, glassd tự đọc lại):

```sh
glassctl get                        # xem mọi settings
glassctl palette twilight           # đổi palette
glassctl wallpaper ~/Pictures/a.jpg # đổi hình nền
glassctl set idle.lock 600          # khoá máy sau 10 phút
glassctl set night_light.enabled true
```

Danh sách đầy đủ và API cho app khác: [docs/ipc.md](docs/ipc.md).

Shell điều khiển được từ dòng lệnh hay phím tắt riêng của bạn:

```sh
glass-shell startmenu toggle
glass-shell powermenu open
glass-shell notifications toggleDnd
glass-shell ipc show                # mọi lệnh
```

Ghim/bỏ ghim app trên taskbar bằng chuột phải vào nút app.

Config chia 3 lớp:

| Lớp | Vị trí | Ai sửa |
| --- | --- | --- |
| Mặc định | `/usr/share/glass/` | Gói; cập nhật theo phiên bản |
| Của bạn | `~/.config/glass/`, `~/.config/kitty/kitty.conf`, `~/.config/fcitx5/profile`, cờ Chromium/Electron | Bạn; Glass tạo một lần, không bao giờ ghi đè |
| Sinh ra | `~/.local/state/glass/` | glassd (theme, state) và shell (app ghim, số lần mở); không cần sửa tay |

Các file trong `~/.config/glass/` và `kitty.conf` nạp mặc định trước, rồi mới tới phần bạn viết, nên chỉ cần ghi những gì muốn khác. Profile fcitx5 và cờ Chromium/Electron chỉ là giá trị ban đầu, sau đó app tự quản. Ví dụ trong `~/.config/glass/hyprland.lua`:

```lua
local glass = require("/usr/share/glass/hypr/glass")

hl.monitor({ output = "eDP-1", mode = "2560x1600@165", position = "0x0", scale = 1.25 })
hl.config({ decoration = { blur = { passes = 2 } } })
```

Phím tắt: [docs/keybinds.md](docs/keybinds.md).

## Phát triển

```sh
make             # build glassd, glassctl
make check       # shellcheck, luac, desktop-file-validate, systemd-analyze, cargo fmt/clippy/test, test tích hợp
make test-shell  # chạy shell QML thật trên sway headless (cần quickshell, sway, wtype, notify-send)
```

- Test Lua chạy thử toàn bộ config Hyprland với một `hl` giả để bắt lỗi runtime, phím tắt trùng, và biến môi trường chưa được chép vào systemd.
- Test glassd chạy daemon thật trên một session bus riêng, đổi settings qua `glassctl`, socket và sửa tay file, rồi kiểm tra file sinh ra và lệnh được gọi (gsettings, hyprctl, systemctl thay bằng stub).
- Test shell chạy Quickshell trên sway headless (không cần GPU) với IPC Hyprland giả (`tests/fake-hyprland.py`): gõ phím thật vào start menu, gửi thông báo thật, mở menu nguồn, đổi palette, và không cho phép cảnh báo QML nào. `GLASS_SMOKE_SHOTS=thư-mục` để lưu ảnh chụp từng bước. Thiếu công cụ thì `make check` bỏ qua bước này; CI chạy nó trong container Arch.
- Blur, phím SUPER, phiên thật chỉ kiểm được trên máy có Hyprland: [docs/testing.md](docs/testing.md).

Sửa shell tại chỗ: `GLASS_SHELL_DIR=$PWD/shell GLASS_SHELL_WATCH=1 glass-shell` (dừng `glass-shell.service` trước) để shell tự nạp lại khi lưu file QML.

Sửa template trong `theme/runtime/` thì chạy `GLASS_UPDATE_STATE=1 cargo test --manifest-path daemon/Cargo.toml` để cập nhật bản khởi tạo trong `defaults/state/`.

## Giấy phép

MIT. Hình nền trong `wallpapers/` do `wallpapers/make-aero.py` vẽ ra, không dùng tài sản nào của Microsoft.
