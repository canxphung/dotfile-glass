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
| Core daemon | glassd (Rust): settings, theme, agent NM/BlueZ | GĐ2 |
| IPC | D-Bus cho API công khai, unix socket cho shell | GĐ2 |
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
                 ├─ glass-idle.service       hypridle --config ~/.config/glass/hypridle.conf
                 ├─ glass-wallpaper.service  hyprpaper --config ~/.config/glass/hyprpaper.conf
                 ├─ hyprpolkitagent.service
                 └─ xdg-desktop-autostart.target
                     └─ fcitx5 (qua /etc/xdg/autostart của gói fcitx5)
```

Bộ gõ: app GTK3/4 và Qt6 gõ qua giao thức text-input-v3 của Hyprland, nên Glass không đặt `GTK_IM_MODULE` (fcitx5 sẽ cảnh báo nếu có). `QT_IM_MODULE`, `XMODIFIERS`, `SDL_IM_MODULE` chỉ để dành cho app Qt5, app XWayland và game SDL2. Chromium/Electron cần cờ `--enable-wayland-ime --wayland-text-input-version=3`; Glass tạo sẵn `~/.config/chromium-flags.conf` và `~/.config/electron-flags.conf` nếu bạn chưa có.

Khi Hyprland thoát (đăng xuất qua `hyprshutdown`), nó tắt `graphical-session.target`; `glass-session.target` gắn `BindsTo` vào đó nên các dịch vụ của Glass tắt theo.

Config của phiên Glass nằm trong `~/.config/glass/` và được truyền bằng `--config`, nên config Hyprland khác trong `~/.config/hypr/` (ví dụ Noctalia của CachyOS) vẫn giữ nguyên cho phiên "Hyprland" thường. Vì thế Glass dùng dịch vụ riêng `glass-idle`/`glass-wallpaper` thay cho `hypridle.service`/`hyprpaper.service` của upstream.

## Config 3 lớp

1. **Mặc định** trong `/usr/share/glass/`, do gói quản lý.
2. **Của người dùng** trong `~/.config/glass/` và `~/.config/kitty/kitty.conf`. Mỗi file nạp mặc định trước (`require`, `source`, `include`) rồi tới phần người dùng viết. `glass-setup` tạo một lần, không ghi đè; `--force` sao lưu rồi thay.
3. **Sinh ra** trong `~/.local/state/glass/`, do glassd ghi (từ GĐ2). `colors.lua` đã đọc `~/.local/state/glass/theme/hyprland.lua` nếu có.

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

Mọi đường dẫn cài chỉ định nghĩa trong `Makefile`; `pkg/PKGBUILD` gọi `make install-*`. Chuỗi `@GLASS_DATADIR@` trong file nguồn được thay bằng đường dẫn thật lúc cài.

## Lộ trình

1. **Nền phiên** (xong): Hyprland, session, lock/idle/wallpaper, portal, SDDM, kitty.
2. **glassd tối thiểu**: `settings.toml`, D-Bus + socket, áp gsettings, render theme runtime, `glassctl`.
3. **Shell cơ bản**: taskbar, start menu, thông báo, OSD, power menu.
4. **Control center + agent**: Wi-Fi, Bluetooth, âm thanh, nguồn; hộp thoại mật khẩu Wi-Fi và ghép nối Bluetooth.
5. **Theme đầy đủ**: GTK3, đè màu GTK4/libadwaita, Kvantum, color scheme KDE, theme SDDM, cửa sổ Settings.
