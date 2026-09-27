-- Glass: điểm vào của cấu hình Hyprland mặc định.
--
-- File này do gói quản lý (@GLASS_DATADIR@/hypr/glass.lua) và sẽ bị
-- thay khi cập nhật gói. Đừng sửa ở đây; chỉnh riêng trong
-- ~/.config/glass/hyprland.lua (file đó nạp file này trước).
--
-- Mỗi module được require riêng, nên một module lỗi không làm hỏng
-- các module còn lại.

local modules = "@GLASS_DATADIR@/hypr/modules/"

require(modules .. "env")
require(modules .. "monitors")
require(modules .. "input")
require(modules .. "decoration")
require(modules .. "animations")
require(modules .. "layout")
require(modules .. "binds")
require(modules .. "rules")
require(modules .. "autostart")

-- Trả về các thiết lập chung để file của người dùng dùng lại, ví dụ:
--   local glass = require("@GLASS_DATADIR@/hypr/glass")
--   hl.bind(glass.mod .. " + B", hl.dsp.exec_cmd("firefox"))
return require(modules .. "settings")
