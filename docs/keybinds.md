# Phím tắt

`SUPER` là phím Windows. Đổi phím trong `~/.config/glass/hyprland.lua` bằng `hl.unbind(...)` rồi `hl.bind(...)`. Xem danh sách đang chạy: `hyprctl binds`.

## Ứng dụng

| Phím | Việc |
| --- | --- |
| `SUPER` (nhấn rồi thả) | Mở/đóng start menu |
| `SUPER + R` | Mở start menu để tìm app |
| `SUPER + Enter` | Mở terminal (kitty) |

Trong start menu: gõ để tìm (không cần dấu: "trinh duyet" ra "Trình duyệt"), `↑`/`↓` chọn, `Enter` mở, `Esc` đóng.

## Cửa sổ

| Phím | Việc |
| --- | --- |
| `SUPER + Q`, `ALT + F4` | Đóng cửa sổ |
| `ALT + Tab` | Chuyển cửa sổ |
| `SUPER + ←↑→↓` | Chuyển focus |
| `SUPER + SHIFT + ←↑→↓` | Dời cửa sổ |
| `SUPER + V` | Bật/tắt nổi |
| `SUPER + F` | Toàn màn hình |
| `SUPER + M` | Phóng to |
| `SUPER + P` | Pseudotile |
| `SUPER + J` | Đổi hướng chia |
| `SUPER + chuột trái` (giữ) | Kéo cửa sổ |
| `SUPER + chuột phải` (giữ) | Đổi kích thước |

Kéo viền cửa sổ cũng đổi được kích thước.

## Workspace

| Phím | Việc |
| --- | --- |
| `SUPER + 1..0` | Sang workspace 1..10 |
| `SUPER + SHIFT + 1..0` | Dời cửa sổ sang workspace |
| `SUPER + CTRL + ←/→`, `SUPER + lăn chuột` | Workspace trước/kế |
| `` SUPER + ` `` | Hiện/ẩn scratchpad |
| `` SUPER + SHIFT + ` `` | Dời cửa sổ vào scratchpad |
| Vuốt 3 ngón ngang | Đổi workspace |

## Bộ gõ (fcitx5 + Bamboo)

| Phím | Việc |
| --- | --- |
| `CTRL + Space` | Bật/tắt tiếng Việt |
| `Shift trái` (khi đang bật) | Tạm chuyển sang gõ tiếng Anh |

Mặc định gõ kiểu Telex. Đổi sang VNI, bảng mã hay phím tắt khác trong `fcitx5-configtool` (Bamboo → Cấu hình).

## Phiên

| Phím | Việc |
| --- | --- |
| `SUPER + L` | Khoá máy |
| `SUPER + SHIFT + E`, `CTRL + ALT + Delete` | Menu nguồn: khoá, đăng xuất, ngủ, khởi động lại, tắt máy (`↑`/`↓`, `Enter`, `Esc`) |
| `SUPER + N` | Bật/tắt không làm phiền (vẫn hiện thông báo khẩn) |

## Chụp màn hình

Ảnh lưu vào `~/Pictures/Screenshots` và chép sẵn vào clipboard.

| Phím | Việc |
| --- | --- |
| `Print`, `SUPER + SHIFT + S` | Chụp vùng |
| `SHIFT + Print` | Chụp mọi màn hình |

## Phím media

Âm lượng, tắt tiếng, mic, độ sáng, phát/dừng, bài trước/kế. Chạy cả khi đang khoá máy. Đổi âm lượng hay độ sáng thì hiện OSD phía trên taskbar.

## Chuột trên taskbar

| Chỗ | Chuột | Việc |
| --- | --- | --- |
| Nút Start | trái | Mở/đóng start menu |
| Nút app | trái | Chưa chạy: mở. Một cửa sổ: đưa lên. Nhiều cửa sổ: chọn cửa sổ |
| Nút app | giữa | Mở thêm cửa sổ mới |
| Nút app | phải | Danh sách cửa sổ, ghim/bỏ ghim, đóng |
| Workspace | trái / lăn | Sang workspace đó / workspace kế bên |
| Loa | trái / lăn | Tắt/bật tiếng / chỉnh âm lượng |
| Chuông | trái | Bật/tắt không làm phiền |
| Đồng hồ | trái | Lịch tháng |
| Icon khay | trái / giữa / phải | Mở app / thao tác phụ / menu của app |

Nhấn rồi thả `SUPER` chỉ mở start menu khi không kèm phím nào; `SUPER + Q` và các phím tắt khác không mở menu. Riêng khi giữ `SUPER` để kéo cửa sổ bằng chuột, thả `SUPER` có thể mở menu; bấm `Esc` để đóng.
