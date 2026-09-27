-- Mặc định: mọi màn hình chạy độ phân giải ưu tiên, tự xếp, tự scale.
-- Khai báo màn hình cụ thể trong ~/.config/glass/hyprland.lua, ví dụ:
--   hl.monitor({ output = "eDP-1", mode = "2560x1600@165", position = "0x0", scale = 1.25 })

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})
