# Test trên máy thật

Container phát triển không chạy được Hyprland hay SDDM. `make check` kiểm được cú pháp, bố cục cài đặt, chạy thử config Lua với một `hl` giả, và chạy glassd thật trên một session bus riêng (lệnh gsettings, hyprctl, systemctl được thay bằng stub). `make test-shell` chạy shell QML thật trên sway headless: gõ phím thật vào start menu, gửi thông báo thật, mở menu nguồn, đổi palette (CI chạy bước này trong container Arch và lưu ảnh chụp màn hình). Blur, phím SUPER, workspace thật, âm thanh, pin và phiên thật vẫn phải thử trên máy CachyOS.

Mục 0–9 là giai đoạn 1, mục 10 là giai đoạn 2 (glassd), mục 11 là giai đoạn 3 (shell).

Gặp lỗi ở bước nào thì gửi lại: số bước, việc đã làm, và kết quả của các lệnh trong mục [Thu log](#thu-log).

## 0. Chuẩn bị

Mở sẵn một TTY dự phòng phòng khi màn hình đăng nhập không lên: `Ctrl + Alt + F3`, đăng nhập, rồi `Ctrl + Alt + F1` (hoặc F2) để quay lại.

## 1. Cài đặt

```sh
cd dotfile-glass/pkg
makepkg -si
glass-doctor
```

- [ ] `makepkg` cài đủ 5 gói: `glass-desktop`, `glass-session`, `glassd`, `glass-shell`, `glass-sddm`
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
systemctl --user status glass-session.target glassd glass-shell glass-idle glass-wallpaper hyprpolkitagent
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
- [ ] `Print` chụp vùng: có thông báo góc dưới phải kèm ảnh vừa chụp, ảnh nằm trong `~/Pictures/Screenshots`, dán được vào app khác
- [ ] Phím âm lượng và độ sáng hoạt động, có OSD phía trên taskbar

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

- [ ] `SUPER + SHIFT + E` mở menu nguồn, chọn **Đăng xuất**: hiện hộp "Đang đăng xuất...", app tự đóng, quay về SDDM
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

## 11. Shell

Taskbar:

- [ ] Taskbar kính ở đáy mọi màn hình, blur hình nền phía sau; cửa sổ không bị taskbar che
- [ ] Nút Start (quả cầu) sáng lên khi rê chuột
- [ ] Có sẵn nút cho các app ghim đã cài (kitty, trình quản lý file, trình duyệt)
- [ ] Mở 2 cửa sổ kitty: một nút kitty có khung chồng phía sau; bấm vào hiện danh sách 2 cửa sổ, chọn được từng cái
- [ ] Chuột phải nút app: danh sách cửa sổ, "Mở cửa sổ mới", "Ghim/Bỏ ghim", "Đóng"; bấm ra ngoài thì menu đóng
- [ ] Bỏ ghim rồi ghim lại một app; đăng xuất/đăng nhập lại vẫn giữ
- [ ] Workspace: số đang dùng sáng hơn; bấm để chuyển; `SUPER + 3` thì ô số 3 sáng theo
- [ ] Khay: icon fcitx5 (và app khác nếu có: Discord, Steam...), chuột phải hiện menu của app
- [ ] Nhóm icon mạng / Bluetooth / loa / pin: lăn chuột đổi âm lượng, có OSD; bấm mở control center
- [ ] Laptop: icon pin và phần trăm, đổi icon khi cắm sạc
- [ ] Đồng hồ hai dòng; bấm hiện lịch tháng, có đánh dấu hôm nay, chuyển tháng được

Start menu:

- [ ] Nhấn rồi thả `SUPER`: start menu hiện ở góc dưới trái, kính mờ; nhấn lại thì đóng
- [ ] `SUPER + Q` (đóng cửa sổ) không làm start menu bật lên
- [ ] Gõ ngay "fire" (không cần bấm vào ô tìm): ra Firefox; `↓`, `Enter` mở app đang chọn
- [ ] Gõ không dấu "cai dat" ra các app có tên "Cài đặt" (nếu có)
- [ ] "Tất cả ứng dụng" hiện đủ app theo thứ tự tên; "Quay lại" về danh sách hay dùng
- [ ] Mở app vài lần: app đó lên đầu mục hay dùng
- [ ] Bấm "Tài liệu", "Ảnh"... mở đúng thư mục; "Cài đặt" mở `settings.toml`
- [ ] App mở từ start menu gõ được tiếng Việt (kiểm tra biến môi trường được chép vào systemd)
- [ ] `systemctl --user restart glass-shell`: taskbar biến mất rồi hiện lại, app đã mở từ start menu vẫn còn nguyên
- [ ] `systemd-cgls --user-unit app.slice` thấy mỗi app một scope `app-glass-...`

Thông báo, OSD, menu nguồn:

- [ ] `notify-send "Xin chào" "Thử thông báo"`: popup kính góc dưới phải, tự ẩn sau vài giây, rê chuột lên thì không ẩn
- [ ] `notify-send -u critical "Khẩn" "..."`: viền đỏ, không tự ẩn; bấm × để đóng
- [ ] Thông báo của app thật (vd. tải xong file trong trình duyệt), bấm vào thì mở app
- [ ] `SUPER + N` bật không làm phiền (icon chuông gạch chéo): thông báo thường không hiện popup; bật lại
- [ ] `glass-doctor` báo "thông báo do shell của Glass hiện"
- [ ] Phím độ sáng: OSD độ sáng
- [ ] `CTRL + ALT + Delete`: màn hình mờ tối, danh sách khoá / đăng xuất / ngủ / khởi động lại / tắt máy; `↑`/`↓`, `Enter` chọn được, `Esc` thoát
- [ ] Chọn "Ngủ": máy ngủ, thức dậy thấy màn hình khoá

Đổi theme:

- [ ] `glassctl palette twilight`: taskbar, start menu, thông báo chuyển sang tím ngay
- [ ] `glassctl set appearance.font "Noto Sans 12"`: chữ trên taskbar và start menu to lên

## 12. Control center, Wi-Fi, Bluetooth

Control center:

- [ ] `SUPER + A` hoặc bấm nhóm icon mạng/loa trên taskbar: bảng kính góc dưới phải trượt lên; bấm ra ngoài hoặc `Esc` thì đóng
- [ ] Ô Wi-Fi, Bluetooth ghi đúng mạng/thiết bị đang dùng; bấm ô thì bật/tắt, bấm `›` thì sang trang riêng; `Esc` ở trang con thì về trang chính
- [ ] "Không làm phiền", "Ánh sáng đêm", "Chế độ tối" bật/tắt được; `glassctl get night_light.enabled` đổi theo
- [ ] Laptop: "Tiết kiệm pin", dòng pin còn bao nhiêu phần trăm / bao lâu, ba nút chế độ nguồn (`powerprofilesctl get` đổi theo)
- [ ] Kéo thanh âm lượng, micro, độ sáng: đổi ngay, không bật OSD trùng; bấm icon loa/micro để tắt tiếng
- [ ] Trang âm thanh: chọn loa khác (vd. tai nghe HDMI/USB), âm thanh chuyển sang đó; đang phát nhạc thì có thanh âm lượng riêng cho app đó
- [ ] Thông báo cũ hiện trong bảng; bấm × xoá từng cái, "Xoá hết" xoá tất cả

Wi-Fi:

- [ ] Trang Wi-Fi quét và hiện các mạng xung quanh, mạng có mật khẩu có ổ khoá, mạng đang dùng in đậm lên đầu
- [ ] Nối mạng mới có mật khẩu: màn hình mờ đi, hộp thoại "Nhập mật khẩu Wi-Fi" hiện giữa màn hình, gõ được ngay (kể cả khi control center đang mở)
- [ ] Gõ sai mật khẩu: hộp thoại hiện lại với dòng "không đúng. Nhập lại"; gõ đúng thì nối được, icon trên taskbar đổi theo sóng
- [ ] `Esc` ở hộp thoại: huỷ nối, mạng hiện "Chưa nhập mật khẩu" khi mở rộng
- [ ] Mạng đã lưu: bấm "Ngắt kết nối", "Kết nối" lại không hỏi mật khẩu; "Quên" thì mạng mất khỏi danh sách đã lưu
- [ ] Tắt Wi-Fi bằng công tắc: danh sách trống, icon Wi-Fi gạch chéo; bật lại thì tự nối mạng quen
- [ ] Mạng doanh nghiệp (802.1X, nếu có): hộp thoại hỏi cả tên đăng nhập và mật khẩu
- [ ] `glass-doctor` không báo nm-applet/blueman tự chạy (nếu có thì làm theo hướng dẫn để tắt)

Bluetooth:

- [ ] Trang Bluetooth: thiết bị đã ghép nối ở trên, thiết bị tìm thấy ở dưới; đang mở trang thì máy luôn tìm thiết bị
- [ ] Ghép nối tai nghe/loa: hộp thoại hiện mã 6 số (hoặc hỏi cho phép), `Enter` đồng ý; xong thì tự kết nối, tai nghe hiện trong trang âm thanh
- [ ] Ghép nối bàn phím: hộp thoại hiện mã để gõ trên bàn phím; gõ xong thì hộp thoại tự đóng
- [ ] Từ chối ở hộp thoại: thiết bị báo ghép nối thất bại, không bị ghép nối
- [ ] Tai nghe có báo pin: trạng thái hiện "pin ...%"
- [ ] "Ngắt", "Huỷ ghép nối" hoạt động; tắt Bluetooth bằng công tắc thì thiết bị ngắt hết
- [ ] `systemctl restart bluetooth` (hoặc `NetworkManager`) rồi ghép nối/nối Wi-Fi lại: hộp thoại vẫn hiện (glassd tự đăng ký lại agent)

## Thu log

```sh
glass-doctor
hyprctl configerrors
hyprctl rollinglog | tail -n 100
journalctl --user -b -u glass-session.target -u glass-idle -u glass-wallpaper -u hyprpolkitagent
journalctl --user -b -u 'app-org.fcitx.Fcitx5@autostart.service'
journalctl --user -b -u glassd -u glass-nightlight
journalctl --user -b -u glass-shell
journalctl -b -u sddm | tail -n 100
```
