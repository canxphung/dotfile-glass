# Kiến trúc

## Thành phần

| Thành phần | Chọn | Trạng thái |
| --- | --- | --- |
| Compositor | Hyprland (config Lua, >= 0.56) | GĐ1 |
| Session | `start-hyprland` + systemd user target | GĐ1 |
| Lock / Idle | hyprlock / hypridle | GĐ1 |
| Hình nền | hyprpaper | GĐ1 |
| Portal | xdg-desktop-portal-hyprland + gtk | GĐ1 |
| Auth | hyprpolkitagent (tự làm sau) | GĐ1 |
| Secrets | gnome-keyring (Secret Service) | GĐ1 |
| Display manager | SDDM, greeter Wayland qua weston | GĐ1 (theme riêng ở GĐ5) |
| Terminal | kitty | GĐ1 |
| Bộ gõ | fcitx5 + Bamboo (tiếng Việt) | GĐ1 (theme Aero cho ô gợi ý ở GĐ5) |
| Core daemon | glassd (Rust): settings, theme runtime; agent NM/BlueZ ở GĐ4 | GĐ2 |
| IPC | D-Bus cho API công khai, unix socket cho shell ([ipc.md](ipc.md)) | GĐ2 |
| Night light | hyprsunset, glassd bật/tắt theo giờ | GĐ2 |
| Shell | Quickshell + QML | GĐ3–4 |
| Network / BT / Audio / Power | NetworkManager, BlueZ, PipeWire, UPower + power-profiles-daemon | GĐ4 |
| Theme | palette Aero cố định, GTK, Kvantum, color scheme KDE | GĐ5 |

## Luồng đăng nhập

```
SDDM (greeter Wayland trên weston)
 └─ glass.desktop → glass-session
     ├─ glass-setup --quiet          tạo file còn thiếu trong ~/.config/glass
     └─ start-hyprland -- --config ~/.config/glass/hyprland.lua
         ├─ Hyprland tự import biến môi trường vào systemd và bật
         │  hyprland-session.target + graphical-session.target
         └─ sự kiện hyprland.start → glass-session services
             └─ glass-session.target
                 ├─ glassd.service           render file state, rồi mới nhận tên D-Bus
                 ├─ glass-idle.service       hypridle --config ~/.config/glass/hypridle.conf
                 ├─ glass-wallpaper.service  hyprpaper --config ~/.config/glass/hyprpaper.conf
                 ├─ glass-nightlight.service hyprsunset (glassd bật khi night_light.enabled)
                 ├─ hyprpolkitagent.service
                 └─ xdg-desktop-autostart.target
                     └─ fcitx5 (qua /etc/xdg/autostart của gói fcitx5)
```

Bộ gõ: app GTK3/4 và Qt6 gõ qua giao thức text-input-v3 của Hyprland, nên Glass không đặt `GTK_IM_MODULE` (fcitx5 sẽ cảnh báo nếu có). `QT_IM_MODULE`, `XMODIFIERS`, `SDL_IM_MODULE` chỉ để dành cho app Qt5, app XWayland và game SDL2. Chromium/Electron cần cờ `--enable-wayland-ime --wayland-text-input-version=3`; Glass tạo sẵn `~/.config/chromium-flags.conf` và `~/.config/electron-flags.conf` nếu bạn chưa có.

Khi Hyprland thoát (đăng xuất qua `hyprshutdown`), nó tắt `graphical-session.target`; `glass-session.target` gắn `BindsTo` vào đó nên các dịch vụ của Glass tắt theo.

Config của phiên Glass nằm trong `~/.config/glass/` và được truyền bằng `--config`, nên config Hyprland khác trong `~/.config/hypr/` (ví dụ Noctalia của CachyOS) vẫn giữ nguyên cho phiên "Hyprland" thường. Vì thế Glass dùng dịch vụ riêng `glass-idle`/`glass-wallpaper` thay cho `hypridle.service`/`hyprpaper.service` của upstream.

## Config 3 lớp

1. **Mặc định** trong `/usr/share/glass/`, do gói quản lý.
2. **Của người dùng** trong `~/.config/glass/` và `~/.config/kitty/kitty.conf`. Mỗi file nạp mặc định trước (`require`, `source`, `include`) rồi tới phần người dùng viết. `glass-setup` tạo một lần, không ghi đè; `--force` sao lưu rồi thay. Riêng `settings.toml` do glassd tạo từ bản mẫu và ghi khi bạn đổi qua `glassctl` (giữ nguyên comment).
3. **Sinh ra** trong `~/.local/state/glass/`, do glassd ghi. Không sửa tay.

### File glassd sinh ra

| File trong `~/.local/state/glass/` | Nguồn | Ai đọc | Khi đổi, glassd làm |
| --- | --- | --- | --- |
| `theme/hyprland.lua` | palette | `hypr/modules/colors.lua` | `hyprctl reload` |
| `theme/hyprlock.conf` | palette, `appearance.font` | `hypr/hyprlock.conf` (`source`) | không cần; hyprlock đọc lúc khoá |
| `theme/kitty.conf` | palette, `appearance.monospace_font` | `kitty/glass.conf` (`include`) | gửi `SIGUSR1` cho kitty |
| `theme/shell.json` | palette, `appearance.*` | shell (GĐ3) | shell tự theo dõi file |
| `idle.conf` | `[idle]` | `hypr/hypridle.conf` (`source`) | khởi động lại `glass-idle` |
| `wallpaper.conf` | `[wallpaper]` | `hypr/hyprpaper.conf` (`source`) | đổi hình qua IPC của hyprpaper |
| `nightlight.conf` | `[night_light]` | `glass-nightlight.service` | bật, tắt, khởi động lại dịch vụ |

Ngoài ra `appearance.color_scheme`, `font`, `monospace_font` được ghi vào gsettings (`org.gnome.desktop.interface`), để app GTK, libadwaita và Chromium (qua portal) theo.

glassd chỉ ghi file khi nội dung thật sự khác, nên chỉ những gì liên quan mới bị nạp lại. Template nằm trong `/usr/share/glass/templates/` (repo: `theme/runtime/`).

Gói `glass-session` mang sẵn bản khởi tạo của các file này (`/usr/share/glass/state/`, đúng bằng những gì glassd render với settings mặc định; test Rust bảo đảm hai bên khớp). `glass-setup` chép bản khởi tạo vào `~/.local/state/glass/` nếu còn thiếu, nên hyprlock, hypridle, hyprpaper vẫn chạy được khi glassd chưa lên.

## Bản đồ cài đặt

| Nguồn trong repo | Cài vào | Gói |
| --- | --- | --- |
| `bin/*` | `/usr/bin/` | glass-session |
| `defaults/` | `/usr/share/glass/` | glass-session |
| `skel/` | `/usr/share/glass/skel/` | glass-session |
| `theme/palettes/` | `/usr/share/glass/palettes/` | glass-session |
| `wallpapers/*.jpg` | `/usr/share/glass/wallpapers/` | glass-session |
| `session/glass.desktop` | `/usr/share/wayland-sessions/` | glass-session |
| `session/systemd/*` | `/usr/lib/systemd/user/` | glass-session |
| `session/portals/*` | `/etc/xdg/xdg-desktop-portal/` | glass-session |
| `session/sddm/glass.conf` | `/usr/lib/sddm/sddm.conf.d/` | glass-sddm |
| `daemon/` (cargo) | `/usr/bin/glassd`, `/usr/bin/glassctl` | glassd |
| `theme/runtime/*.j2` | `/usr/share/glass/templates/` | glassd |
| `daemon/data/*.service` | `/usr/lib/systemd/user/`, `/usr/share/dbus-1/services/` | glassd |

Mọi đường dẫn cài chỉ định nghĩa trong `Makefile`; `pkg/PKGBUILD` gọi `make build` và `make install-*`. Chuỗi `@GLASS_DATADIR@`, `@BINDIR@` trong file nguồn được thay bằng đường dẫn thật lúc cài; glassd nhận thư mục dữ liệu lúc build (`glassd --version` in ra).

## glassd

```
daemon/
├── glass-core/   lib dùng chung: settings (toml_edit, giữ comment), palette, render (minijinja)
├── glassd/       daemon: service trung tâm, D-Bus, socket, theo dõi settings.toml, áp ra hệ thống
└── glassctl/     dòng lệnh, gọi glassd qua D-Bus
```

Mọi đường đổi settings (D-Bus, socket, sửa tay file) đi qua cùng một hàm trong `glassd/src/service.rs`: kiểm tra → ghi `settings.toml` → render file state → áp → phát sự kiện `Changed` cho cả D-Bus lẫn socket. glassd không đứng giữa dữ liệu hệ thống (âm lượng, mạng, pin): shell đọc thẳng các thứ đó qua Quickshell.

Nếu `settings.toml` bị sửa hỏng, glassd giữ settings cũ, phát sự kiện `FileError` và từ chối ghi đè file cho tới khi bạn sửa xong, để không làm mất phần đang sửa dở.

## Lộ trình

1. **Nền phiên** (xong): Hyprland, session, lock/idle/wallpaper, portal, SDDM, kitty, bộ gõ.
2. **glassd tối thiểu** (xong): `settings.toml`, D-Bus + socket, áp gsettings, render theme runtime, night light, `glassctl`, palette Sky và Twilight.
3. **Shell cơ bản**: taskbar, start menu, thông báo, OSD, power menu.
4. **Control center + agent**: Wi-Fi, Bluetooth, âm thanh, nguồn; hộp thoại mật khẩu Wi-Fi và ghép nối Bluetooth.
5. **Theme đầy đủ**: GTK3, đè màu GTK4/libadwaita, Kvantum, color scheme KDE, theme SDDM, cửa sổ Settings.
