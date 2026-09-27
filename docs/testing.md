# Test trên máy thật

Container phát triển không chạy được Hyprland hay SDDM. `make check` kiểm được cú pháp, bố cục cài đặt, chạy thử config Lua với một `hl` giả, và chạy glassd thật trên một session bus riêng (lệnh gsettings, hyprctl, systemctl được thay bằng stub). Hiển thị và phiên thật phải thử trên máy CachyOS.

Mục 0–9 là giai đoạn 1, mục 10 là giai đoạn 2 (glassd).

Gặp lỗi ở bước nào thì gửi lại: số bước, việc đã làm, và kết quả của các lệnh trong mục [Thu log](#thu-log).

## 0. Chuẩn bị

Mở sẵn một TTY dự phòng phòng khi màn hình đăng nhập không lên: `Ctrl + Alt + F3`, đăng nhập, rồi `Ctrl + Alt + F1` (hoặc F2) để quay lại.

## 1. Cài đặt

```sh
cd dotfile-glass/pkg
makepkg -si
glass-doctor
```

- [ ] `makepkg` cài đủ 4 gói: `glass-desktop`, `glass-session`, `glassd`, `glass-sddm`
- [ ] `glassd --version` in `(dữ liệu: /usr/share/glass)`
- [ ] `glass-doctor` không có lỗi (✗). Cảnh báo (!) về config chưa tạo là bình thường trước lần đăng nhập đầu.

## 2. Màn hình đăng nhập

Khởi động lại máy (hoặc `sudo systemctl restart sddm` từ TTY).

- [ ] SDDM hiện lên (lúc này greeter chạy Wayland trên weston)
- [ ] Có phiên **Glass** trong danh sách phiên

Nếu màn hình đen hoặc SDDM không lên, từ TTY dự phòng quay về X11:

```sh
printf '[General]\nDisplayServer=x11\n' | sudo tee /etc/sddm.conf.d/glass-x11.conf
sudo systemctl restart sddm
```

rồi báo lại (kèm `journalctl -b -u sddm`).

## 3. Vào phiên

Chọn **Glass**, đăng nhập.

- [ ] Vào được desktop, thấy hình nền Aero Sky
- [ ] Không có thanh báo lỗi config màu đỏ/vàng ở trên cùng (nếu có: `hyprctl configerrors`)
- [ ] `~/.config/glass/` có 4 file, `~/.config/kitty/kitty.conf` có dòng `include /usr/share/glass/...`
- [ ] Các dịch vụ đang chạy:

```sh
systemctl --user status glass-session.target glass-idle glass-wallpaper hyprpolkitagent
```

## 4. Giao diện kính

- [ ] `SUPER + Enter` mở kitty: nền trong suốt, blur hình nền phía sau, chữ vẫn nét
- [ ] Viền cửa sổ gradient xanh sáng dần lên trên, cửa sổ đang focus rõ hơn cửa sổ khác
- [ ] Có bóng đổ và vệt sáng mờ ở mép trong cửa sổ
- [ ] Mở 2–3 cửa sổ: tự xếp, kéo viền đổi được kích thước
- [ ] Mở cửa sổ có hiệu ứng "nở" nhẹ, đổi workspace có hiệu ứng trượt

## 5. Phím tắt

Đối chiếu [keybinds.md](keybinds.md). Tối thiểu:

- [ ] `SUPER + Q` và `ALT + F4` đóng cửa sổ
- [ ] `SUPER + 1..3` đổi workspace, `SUPER + SHIFT + 2` dời cửa sổ
- [ ] `ALT + Tab` chuyển cửa sổ
- [ ] `Print` chụp vùng: có thông báo góc trên, ảnh nằm trong `~/Pictures/Screenshots`, dán được vào app khác
- [ ] Phím âm lượng và độ sáng hoạt động
- [ ] `SUPER + R` mở hyprlauncher (nếu đã cài)

## 6. Khoá máy và khi rảnh

- [ ] `SUPER + L` hiện màn hình khoá Aero: nền là desktop bị làm mờ, tấm kính giữa, giờ, ngày, tên, ô mật khẩu
- [ ] Nhập sai mật khẩu: ô đỏ lên, báo lỗi; nhập đúng thì mở khoá
- [ ] Phím âm lượng vẫn chạy khi đang khoá

Thử hẹn giờ rảnh cho nhanh (glassd tự khởi động lại hypridle):

```sh
glassctl set idle.dim 10
glassctl set idle.lock 20
glassctl set idle.screen_off 30
```

Để yên máy:

- [ ] ~10 giây: tối màn hình; ~20 giây: khoá; ~30 giây: tắt màn hình; chạm chuột thì sáng lại
- [ ] Mở video toàn màn hình thì không tự khoá

Trả lại mặc định: `glassctl reset idle.dim`, `glassctl reset idle.lock`, `glassctl reset idle.screen_off`.

- [ ] Gập máy / `systemctl suspend`: thức dậy thấy màn hình khoá ngay, không lộ desktop

## 7. Xác thực, portal, keyring

- [ ] `pkexec true` hiện hộp thoại xác thực nổi giữa màn hình, xung quanh tối lại
- [ ] Mở hộp thoại chọn file từ trình duyệt (tải file lên): hộp thoại GTK nổi giữa màn hình
- [ ] Chia sẻ màn hình trong trình duyệt (vd. thử trên webrtc.github.io) hiện được hộp chọn màn hình của Hyprland
- [ ] Keyring tự mở khi đăng nhập: trình duyệt Chromium không hỏi mật khẩu keyring

## 8. Gõ tiếng Việt

- [ ] `fcitx5` đang chạy (`pgrep -a fcitx5`), không có thông báo "Wayland Diagnose" của fcitx hiện lên
- [ ] `CTRL + Space` bật tiếng Việt; gõ `tieengs vieetj` ra "tiếng việt", ô gợi ý hiện đúng chỗ con trỏ

Thử ở từng loại app, vì mỗi loại đi một đường khác nhau:

- [ ] kitty
- [ ] App GTK (vd. Firefox, hoặc ô tìm trong hộp chọn file)
- [ ] App Qt6 (vd. ô tìm kiếm trong `fcitx5-configtool`)
- [ ] Chromium hoặc app Electron (VS Code, Discord...): cần cờ IME. Nếu bạn đã có `~/.config/chromium-flags.conf` từ trước thì Glass không đụng vào, phải tự thêm `--enable-wayland-ime` và `--wayland-text-input-version=3` (`glass-doctor` sẽ nhắc)
- [ ] App XWayland (nếu có, vd. game hoặc app cũ): gõ qua XIM

## 9. Đăng xuất

- [ ] `SUPER + SHIFT + E`: hiện hộp "Đang đăng xuất...", app tự đóng, quay về SDDM
- [ ] Đăng nhập lại vào Glass lần hai vẫn bình thường
- [ ] Phiên "Hyprland" thường (nếu có) vẫn dùng config cũ trong `~/.config/hypr`, không bị Glass ảnh hưởng

### NVIDIA: màn hình đen khi đăng xuất

Nếu đăng xuất xong bị màn hình đen thay vì về SDDM, cho phép `chvt` chạy không cần mật khẩu rồi bảo Glass chuyển về VT của SDDM:

```sh
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/chvt" | sudo tee /etc/sudoers.d/chvt
sudo chmod 440 /etc/sudoers.d/chvt
```

rồi thêm vào `~/.config/glass/hyprland.lua`:

```lua
hl.env("GLASS_SHUTDOWN_VT", "1")
```

SDDM thường nằm ở VT1; nếu vẫn đen thì thử `"2"`.

## 10. glassd và settings

Trong phiên Glass:

- [ ] `systemctl --user status glassd` đang chạy; `glass-doctor` báo "glassd đang chạy"
- [ ] `~/.config/glass/settings.toml` đã có, đầy đủ comment
- [ ] `glassctl get` in đủ các khoá

Đổi palette, mọi thứ phải đổi màu ngay, không cần đăng xuất:

```sh
glassctl palettes
glassctl palette twilight
```

- [ ] Viền cửa sổ chuyển sang tím
- [ ] Kitty đang mở đổi màu ngay (chữ, nền)
- [ ] `SUPER + L`: màn hình khoá dùng màu tím
- [ ] `glassctl palette sky` đưa mọi thứ về như cũ

Các thứ khác:

- [ ] `glassctl wallpaper ~/Pictures/<hình bất kỳ>`: hình nền đổi ngay; `glassctl wallpaper default` trả lại
- [ ] `glassctl set appearance.color_scheme light`: app GTK4 (vd. Nautilus nếu có) và Firefox/Chromium chuyển sáng; đặt lại `dark`
- [ ] `glassctl set appearance.monospace_font "JetBrainsMono Nerd Font 14"`: chữ kitty to lên ngay
- [ ] `glassctl set idle.lock 20`, để yên máy 20 giây: khoá. Trả lại `glassctl reset idle.lock`
- [ ] Night light: `glassctl set night_light.start "$(date -d '-1 min' +%H:%M)"`, `glassctl set night_light.enabled true` → màn hình ấm lên; `glassctl set night_light.enabled false` → trở lại. Rồi `glassctl reset night_light.start`
- [ ] Mở `settings.toml` bằng trình soạn thảo, đổi `palette = "twilight"`, lưu: màu đổi ngay, comment còn nguyên
- [ ] Cố tình gõ sai (xoá một dấu `]`), lưu: `glassctl set idle.dim 100` báo lỗi file và không ghi đè; sửa lại thì chạy tiếp
- [ ] `glassctl watch` ở một terminal, đổi palette ở terminal khác: dòng `appearance.palette = ...` hiện ra
- [ ] Khởi động lại máy: palette, hình nền, thời gian khoá vẫn giữ như đã đặt

## Thu log

```sh
glass-doctor
hyprctl configerrors
hyprctl rollinglog | tail -n 100
journalctl --user -b -u glass-session.target -u glass-idle -u glass-wallpaper -u hyprpolkitagent
journalctl --user -b -u 'app-org.fcitx.Fcitx5@autostart.service'
journalctl --user -b -u glassd -u glass-nightlight
journalctl -b -u sddm | tail -n 100
```
