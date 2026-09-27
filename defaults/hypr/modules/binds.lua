-- Phím tắt. Danh sách đầy đủ: docs/keybinds.md
-- Đổi phím trong file của bạn: hl.unbind("SUPER + Q") rồi hl.bind(...) lại.

local s   = require("@GLASS_DATADIR@/hypr/modules/settings")
local mod = s.mod

local function bind(keys, action, description, flags)
    flags = flags or {}
    flags.description = description
    return hl.bind(keys, action, flags)
end

---- Ứng dụng ----
bind(mod .. " + Return", hl.dsp.exec_cmd(s.terminal), "Mở terminal")
bind(mod .. " + R",      hl.dsp.exec_cmd(s.launcher), "Mở launcher")

---- Cửa sổ ----
bind(mod .. " + Q", hl.dsp.window.close(), "Đóng cửa sổ")
bind("ALT + F4",    hl.dsp.window.close(), "Đóng cửa sổ")
bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }), "Bật/tắt nổi")
bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Toàn màn hình")
bind(mod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }), "Phóng to")
bind(mod .. " + P", hl.dsp.window.pseudo(), "Pseudotile")
bind(mod .. " + J", hl.dsp.layout("togglesplit"), "Đổi hướng chia")

bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end, "Chuyển cửa sổ")

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    bind(mod .. " + " .. dir,           hl.dsp.focus({ direction = dir }),       "Chuyển focus " .. dir)
    bind(mod .. " + SHIFT + " .. dir,   hl.dsp.window.move({ direction = dir }), "Dời cửa sổ " .. dir)
end

-- Giữ SUPER + chuột trái để kéo, chuột phải để đổi kích thước.
bind(mod .. " + mouse:272", hl.dsp.window.drag(),   "Kéo cửa sổ",  { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), "Đổi kích thước", { mouse = true })

---- Workspace ----
for i = 1, 10 do
    local key = i % 10 -- phím 0 là workspace 10
    bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }),       "Sang workspace " .. i)
    bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), "Dời cửa sổ sang workspace " .. i)
end

bind(mod .. " + CTRL + right", hl.dsp.focus({ workspace = "e+1" }), "Workspace kế tiếp")
bind(mod .. " + CTRL + left",  hl.dsp.focus({ workspace = "e-1" }), "Workspace trước")
bind(mod .. " + mouse_down",   hl.dsp.focus({ workspace = "e+1" }), "Workspace kế tiếp")
bind(mod .. " + mouse_up",     hl.dsp.focus({ workspace = "e-1" }), "Workspace trước")

-- Scratchpad
bind(mod .. " + grave",         hl.dsp.workspace.toggle_special("scratch"),           "Hiện/ẩn scratchpad")
bind(mod .. " + SHIFT + grave", hl.dsp.window.move({ workspace = "special:scratch" }), "Dời cửa sổ vào scratchpad")

---- Phiên ----
bind(mod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"), "Khoá máy")
bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("glass-session logout"),  "Đăng xuất")

---- Chụp màn hình ----
bind("Print",               hl.dsp.exec_cmd("glass-screenshot region"), "Chụp vùng")
bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd("glass-screenshot region"), "Chụp vùng")
bind("SHIFT + Print",       hl.dsp.exec_cmd("glass-screenshot screen"), "Chụp màn hình")

---- Phím media (chạy cả khi đang khoá) ----
local held = { locked = true, repeating = true }
local once = { locked = true }

bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), "Tăng âm lượng", held)
bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      "Giảm âm lượng", held)
bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     "Tắt tiếng", once)
bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   "Tắt mic", once)
bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  "Tăng độ sáng", held)
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  "Giảm độ sáng", held)
bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"),                           "Phát/dừng", once)
bind("XF86AudioPause",        hl.dsp.exec_cmd("playerctl play-pause"),                           "Phát/dừng", once)
bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),                                 "Bài kế", once)
bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),                             "Bài trước", once)
