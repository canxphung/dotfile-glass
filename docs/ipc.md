# API và IPC

- [glassd](#d-bus): settings của Glass, qua D-Bus, socket và `glassctl`.
- [Shell](#shell): điều khiển taskbar, start menu, thông báo... qua `glass-shell`.

glassd có hai cửa vào, cùng một mô hình settings:

- **D-Bus** (session bus): API công khai cho `glassctl`, script và app khác.
- **Unix socket**: kênh cho shell, vì Quickshell không gọi D-Bus tuỳ ý được.

Settings là các khoá dạng `mục.khoá` (ví dụ `appearance.palette`), mỗi khoá một giá trị đơn: chuỗi, số nguyên, số thực hoặc bool. Danh sách khoá và ý nghĩa nằm trong bản mẫu [`defaults/settings.toml`](../defaults/settings.toml).

| Khoá | Kiểu | Mặc định |
| --- | --- | --- |
| `version` | số nguyên (chỉ đọc) | `1` |
| `appearance.palette` | chuỗi, tên palette | `"sky"` |
| `appearance.color_scheme` | `"dark"`, `"light"`, `"default"` | `"dark"` |
| `appearance.font` | chuỗi, "Tên font cỡ" | `"Noto Sans 10"` |
| `appearance.monospace_font` | chuỗi | `"JetBrainsMono Nerd Font 11"` |
| `wallpaper.path` | chuỗi, rỗng là hình mặc định | `""` |
| `wallpaper.fit` | `"cover"`, `"contain"`, `"tile"`, `"fill"` | `"cover"` |
| `idle.dim`, `idle.lock`, `idle.screen_off`, `idle.suspend` | số nguyên (giây, 0 = bỏ bước) | `150`, `300`, `330`, `1800` |
| `night_light.enabled` | bool | `false` |
| `night_light.temperature` | số nguyên 1000..6500 | `4500` |
| `night_light.start`, `night_light.end` | chuỗi `HH:MM` | `"20:00"`, `"06:30"` |

Giá trị sai kiểu, sai miền, palette không tồn tại hay file hình nền không có đều bị từ chối kèm thông báo; settings giữ nguyên.

## D-Bus

- Tên: `io.github.canxphung.Glass1`
- Object: `/io/github/canxphung/Glass1`
- Interface: `io.github.canxphung.Glass1.Settings`

glassd được kích hoạt qua D-Bus (`glassd.service`), nên gọi vào là tự chạy nếu chưa chạy.

| Thành viên | Chữ ký | Việc |
| --- | --- | --- |
| `Get(key)` | `s → v` | Giá trị một khoá |
| `GetAll()` | `→ a{sv}` | Mọi khoá |
| `Set(key, value)` | `sv →` | Đổi một khoá, ghi `settings.toml` và áp ngay |
| `Reset(key)` | `s →` | Đưa khoá về mặc định |
| `ListPalettes()` | `→ as` | Tên các palette có thể chọn |
| `Reload()` | `→` | Đọc lại `settings.toml` ngay |
| `Version` | thuộc tính `s` | Phiên bản glassd |
| `Changed(key, value)` | tín hiệu `sv` | Một khoá vừa đổi, từ bất kỳ nguồn nào |
| `FileError(message)` | tín hiệu `s` | `settings.toml` vừa sửa tay bị lỗi |

Số nguyên gửi vào có thể là bất kỳ kiểu số nguyên nào của D-Bus; glassd trả về `x` (int64).

Ví dụ với `busctl`:

```sh
busctl --user call io.github.canxphung.Glass1 /io/github/canxphung/Glass1 \
    io.github.canxphung.Glass1.Settings Set sv idle.lock x 600
busctl --user call io.github.canxphung.Glass1 /io/github/canxphung/Glass1 \
    io.github.canxphung.Glass1.Settings Get s appearance.palette
```

### Agent trên system bus

glassd còn đăng ký hai agent trên system bus, và đăng ký lại mỗi khi NetworkManager hay bluetoothd khởi động lại:

| Dịch vụ | Object | Việc |
| --- | --- | --- |
| NetworkManager | `/org/freedesktop/NetworkManager/SecretAgent` (`org.freedesktop.NetworkManager.SecretAgent`, tên `io.github.canxphung.glass`) | Hỏi mật khẩu Wi-Fi (WPA/WPA3-PSK, WEP, 802.1X) khi NetworkManager cần; mật khẩu được NetworkManager lưu như bình thường |
| BlueZ | `/io/github/canxphung/Glass1/BluetoothAgent` (`org.bluez.Agent1`, capability `KeyboardDisplay`, agent mặc định) | Xác nhận mã ghép nối, nhập PIN/mã số, hiện mã để gõ trên bàn phím, cho phép thiết bị dùng dịch vụ |

Cả hai hỏi người dùng qua socket (xem [Hộp thoại](#hộp-thoại)). Chưa có shell nào nhận hiện hộp thoại thì agent trả lời ngay là không có mật khẩu / từ chối, để NetworkManager và BlueZ hỏi agent khác (như `nm-applet`) nếu có. `GLASSD_NO_AGENTS=1` tắt cả hai.

## Socket cho shell

- Đường dẫn: `$XDG_RUNTIME_DIR/glass/glassd.sock` (thư mục `0700`, socket `0600`)
- Mỗi tin nhắn là một object JSON trên một dòng, cả hai chiều.

Khi kết nối, glassd gửi ngay:

```json
{"event":"hello","version":"0.4.0","settings":{"appearance.palette":"sky", "...": "..."},"palettes":["sky","twilight"]}
```

Yêu cầu có `method`, tuỳ chọn `id` (trả lại nguyên trong phản hồi), `key`, `value`:

```json
{"id":1,"method":"set","key":"appearance.palette","value":"twilight"}
```

| `method` | Cần | Kết quả |
| --- | --- | --- |
| `ping` | | `"pong"` |
| `get_all` | | object `khoá → giá trị` |
| `get` | `key` | giá trị |
| `set` | `key`, `value` | `null` |
| `reset` | `key` | `null` |
| `palettes` | | mảng tên |
| `reload` | | `null` |

Phản hồi:

```json
{"id":1,"ok":true,"result":null}
{"id":2,"ok":false,"error":"idle.lock cần kiểu số nguyên, nhận chuỗi"}
```

Sự kiện được đẩy tới mọi kết nối, không cần đăng ký:

```json
{"event":"changed","key":"appearance.palette","value":"twilight"}
{"event":"file_error","message":"settings.toml lỗi: ..."}
```

Shell nên cập nhật giao diện theo sự kiện `changed` chứ không theo phản hồi của `set`, vì settings còn đổi được từ `glassctl` hay từ việc sửa tay file.

### Hộp thoại

Agent của glassd cần hỏi người dùng thì gửi yêu cầu qua socket. Một client (shell của Glass) nhận vai hiện hộp thoại bằng `handle_prompts`; ngay sau phản hồi, glassd gửi lại các hộp thoại đang mở, rồi mỗi hộp thoại mới:

```json
{"event":"prompt","id":1,"wait":true,"kind":"wifi_secrets","ssid":"Nhà Mình","security":"psk","fields":["psk"],"retry":false}
{"event":"prompt","id":2,"wait":true,"kind":"bluetooth","action":"confirm","device":"/org/bluez/hci0/dev_00_1A_7D_DA_71_02","name":"Loa","code":"123456"}
{"event":"prompt_closed","id":1}
```

- `wait: false` là hộp thoại chỉ để xem (hiện mã để gõ trên thiết bị), không cần trả lời; đóng bằng `prompt_cancel`.
- `wifi_secrets`: `security` là `psk`, `wep` hay `enterprise`; `fields` là các ô cần điền (`psk`, `wep-key0`, `identity`, `password`); `retry` là `true` khi NetworkManager hỏi lại vì mật khẩu trước sai.
- `bluetooth`: `action` là `confirm` (so mã `code`), `authorize` (cho ghép nối), `authorize_service` (cho dùng dịch vụ `service`), `pin`, `passkey` (người dùng nhập), `display_pin`, `display_passkey` (hiện `code`). `code` và `service` chỉ có khi cần.
- `prompt_closed` đến khi hộp thoại được trả lời, bị huỷ, hết giờ, hay NetworkManager/BlueZ tự huỷ yêu cầu.

| `method` | Cần | Kết quả |
| --- | --- | --- |
| `handle_prompts` | | `null`; kết nối này nhận sự kiện `prompt`, `prompt_closed` |
| `prompt_reply` | `prompt`, `value` | `true` nếu hộp thoại còn mở |
| `prompt_cancel` | `prompt` | `true` nếu hộp thoại còn mở |

`value` là object chuỗi → chuỗi: `{"psk": "..."}` (theo `fields`) cho Wi-Fi, `{"accept": "true"}` hay `{"accept": "false"}` cho xác nhận, `{"value": "..."}` cho PIN và mã số.

```json
{"id":5,"method":"prompt_reply","prompt":1,"value":{"psk":"matkhau123"}}
{"id":6,"method":"prompt_cancel","prompt":2}
```

Màu và font để vẽ giao diện nằm trong `~/.local/state/glass/theme/shell.json` (palette đầy đủ, `color_scheme`, `font_family`, `font_size` tính bằng pt, `monospace_family`); glassd ghi lại file này khi đổi palette hay font, và shell của Glass theo dõi file này để đổi màu ngay.

## glassctl

```sh
glassctl get                           # mọi khoá
glassctl get appearance.palette        # một khoá, in giá trị thô cho script
glassctl set idle.lock 600             # kiểu lấy theo khoá: số, chuỗi, true/false
glassctl reset idle.lock
glassctl palettes                      # dấu * là palette đang dùng
glassctl palette twilight
glassctl wallpaper ~/Pictures/a.jpg    # "default" để về hình mặc định
glassctl reload
glassctl watch                         # in thay đổi khi chúng xảy ra
```

## Shell

Shell (Quickshell) nhận lệnh qua IPC của Quickshell. `glass-shell TARGET HÀM [THAM SỐ]` gọi vào shell đang chạy; `glass-shell ipc show` liệt kê đủ. Hàm trả về giá trị thì in ra để script dùng.

| Target | Hàm | Việc |
| --- | --- | --- |
| `startmenu` | `toggle`, `open`, `close` | Mở/đóng start menu (trên màn hình đang focus) |
| | `isOpen` | `true`/`false` |
| | `entries` | Tên các app đang hiện trong danh sách, mỗi dòng một app |
| `powermenu` | `toggle`, `open`, `close`, `isOpen` | Menu khoá / đăng xuất / ngủ / khởi động lại / tắt máy |
| `controlcenter` | `toggle`, `close`, `isOpen` | Control center (Wi-Fi, Bluetooth, âm thanh, độ sáng, thông báo) |
| | `open PAGE` | Mở ở trang `main`, `wifi`, `bluetooth` hay `audio` |
| | `page` | Trang đang mở, rỗng nếu đang đóng |
| `network` | `status` | Mạng đang dùng, hay "Chưa kết nối", "Wi-Fi đang tắt"... |
| | `list` | Mạng Wi-Fi, mỗi dòng "tên⇥trạng thái⇥sóng %⇥khoá/mở" (mạng lạ chỉ hiện khi đang quét) |
| | `scan BOOL`, `wifi BOOL` | Bật/tắt quét, bật/tắt Wi-Fi |
| | `connect TÊN`, `disconnect TÊN`, `forget TÊN` | Nối (cần mật khẩu thì hiện hộp thoại), ngắt, quên mạng |
| `bluetooth` | `status`, `list` | Tóm tắt; thiết bị, mỗi dòng "tên⇥trạng thái" |
| | `power BOOL`, `scan BOOL` | Bật/tắt Bluetooth, tìm thiết bị |
| | `pair TÊN` | Ghép nối, rồi tin cậy và kết nối |
| | `connect TÊN`, `disconnect TÊN`, `forget TÊN` | Kết nối, ngắt, huỷ ghép nối |
| `audio` | `status` | "loa⇥âm lượng %⇥bật/tắt tiếng" |
| | `sinks` | Các loa, `*` là loa đang dùng |
| | `setVolume PHẦN_TRĂM`, `toggleMute`, `setDefault TÊN` | Đổi âm lượng, tắt tiếng, đổi loa |
| `prompts` | `current` | Hộp thoại đang hiện (JSON như sự kiện `prompt`), rỗng nếu không có |
| | `connected` | Shell có đang nối với glassd không |
| `osd` | `brightness` | Đọc lại độ sáng và hiện OSD (gọi sau `brightnessctl`) |
| | `volume` | Hiện OSD âm lượng (âm lượng đổi thì OSD tự hiện, không cần gọi) |
| | `isVisible`, `level` | OSD đang hiện không, mức đang hiện (%) |
| `notifications` | `toggleDnd`, `dnd` | Bật/tắt, xem chế độ không làm phiền |
| | `dismissAll` | Đóng mọi thông báo |
| | `popups`, `history` | Số popup đang hiện, số thông báo đang giữ |
| `shell` | `tasks` | Các nút trên taskbar, mỗi dòng "id số_cửa_sổ" |
| | `palette`, `tint` | Palette và màu kính shell đang dùng |

```sh
glass-shell startmenu toggle
glass-shell controlcenter open wifi
glass-shell network connect "Nhà Mình"
glass-shell audio setVolume 40
glass-shell notifications toggleDnd
brightnessctl set 50% && glass-shell osd brightness
glass-shell log -f          # log của shell đang chạy
```

Trạng thái riêng của shell nằm trong `~/.local/state/glass/shell/apps.json`: `pinned` là danh sách app ghim trên taskbar (id của desktop entry, hoặc tên class của cửa sổ như `foot`), `launches` là số lần mở từng app để xếp mục "hay dùng" trong start menu. Sửa tay được; shell tự đọc lại.
