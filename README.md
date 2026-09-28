# Glass

Desktop phong cách Aero (kính mờ kiểu Windows 7) chạy trên Hyprland, tối ưu cho CachyOS.

Glass không phải một bộ dotfile để chép tay: nó được đóng gói bằng pacman, có phiên đăng nhập riêng ("Glass" trong SDDM) và không đụng vào config Hyprland khác bạn đang có.

## Trạng thái

**Xong giai đoạn 2** trên 5. Đăng nhập được vào phiên Glass với:

- Hyprland (config Lua) có khung cửa sổ kính kiểu Aero: viền gradient, vệt sáng mép trong, bóng đổ, blur
- Màn hình khoá (hyprlock), xử lý khi rảnh (hypridle), hình nền (hyprpaper)
- Phiên chạy qua systemd, có portal, polkit agent, keyring
- SDDM chạy greeter trên Wayland
- Kitty trong suốt theo palette Aero Sky
- Gõ tiếng Việt bằng fcitx5 + Bamboo (Telex), bật/tắt bằng `CTRL + Space`
- **glassd**: daemon settings viết bằng Rust. Đổi palette (Aero Sky, Aero Twilight), hình nền, font, chế độ sáng/tối, thời gian khoá máy, night light bằng `glassctl` hoặc sửa `settings.toml`; mọi thứ đổi ngay, không cần đăng xuất

Chưa có shell (taskbar, start menu, thông báo, control center). Xem lộ trình trong [docs/architecture.md](docs/architecture.md).

## Cài đặt (CachyOS / Arch)

Cần Hyprland 0.56 trở lên.

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

Config chia 3 lớp:

| Lớp | Vị trí | Ai sửa |
| --- | --- | --- |
| Mặc định | `/usr/share/glass/` | Gói; cập nhật theo phiên bản |
| Của bạn | `~/.config/glass/`, `~/.config/kitty/kitty.conf`, `~/.config/fcitx5/profile`, cờ Chromium/Electron | Bạn; Glass tạo một lần, không bao giờ ghi đè |
| Sinh ra | `~/.local/state/glass/` | glassd; không sửa tay |

Các file trong `~/.config/glass/` và `kitty.conf` nạp mặc định trước, rồi mới tới phần bạn viết, nên chỉ cần ghi những gì muốn khác. Profile fcitx5 và cờ Chromium/Electron chỉ là giá trị ban đầu, sau đó app tự quản. Ví dụ trong `~/.config/glass/hyprland.lua`:

```lua
local glass = require("/usr/share/glass/hypr/glass")

hl.monitor({ output = "eDP-1", mode = "2560x1600@165", position = "0x0", scale = 1.25 })
hl.config({ decoration = { blur = { passes = 2 } } })
```

Phím tắt: [docs/keybinds.md](docs/keybinds.md).

## Phát triển

```sh
make          # build glassd, glassctl
make check    # shellcheck, luac, desktop-file-validate, systemd-analyze, cargo fmt/clippy/test, test tích hợp
```

- Test Lua chạy thử toàn bộ config Hyprland với một `hl` giả để bắt lỗi runtime và phím tắt trùng.
- Test glassd chạy daemon thật trên một session bus riêng, đổi settings qua `glassctl`, socket và sửa tay file, rồi kiểm tra file sinh ra và lệnh được gọi (gsettings, hyprctl, systemctl thay bằng stub).
- Phần hiển thị thật chỉ kiểm được trên máy có Hyprland: [docs/testing.md](docs/testing.md).

Sửa template trong `theme/runtime/` thì chạy `GLASS_UPDATE_STATE=1 cargo test --manifest-path daemon/Cargo.toml` để cập nhật bản khởi tạo trong `defaults/state/`.

## Giấy phép

MIT. Hình nền trong `wallpapers/` do `wallpapers/make-aero.py` vẽ ra, không dùng tài sản nào của Microsoft.
