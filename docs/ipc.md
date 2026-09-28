# glassd: API

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

## Socket cho shell

- Đường dẫn: `$XDG_RUNTIME_DIR/glass/glassd.sock` (thư mục `0700`, socket `0600`)
- Mỗi tin nhắn là một object JSON trên một dòng, cả hai chiều.

Khi kết nối, glassd gửi ngay:

```json
{"event":"hello","version":"0.2.0","settings":{"appearance.palette":"sky", "...": "..."},"palettes":["sky","twilight"]}
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

Màu và font để vẽ giao diện nằm trong `~/.local/state/glass/theme/shell.json` (palette đầy đủ, `color_scheme`, `font_family`, `monospace_family`); glassd ghi lại file này khi đổi palette hay font.

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
