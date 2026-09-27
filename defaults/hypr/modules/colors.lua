-- Màu và thông số kính cho Hyprland.
--
-- Giai đoạn 1: giá trị chép tay từ theme/palettes/sky.toml.
-- Từ giai đoạn 2, glassd render file theme runtime; nếu file đó tồn tại
-- thì dùng nó thay cho bảng mặc định bên dưới.

local state_home = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
local runtime = state_home .. "/glass/theme/hyprland.lua"

local f = io.open(runtime, "r")
if f then
    f:close()
    local ok, theme = pcall(dofile, runtime)
    if ok and type(theme) == "table" then
        return theme
    end
end

return {
    radius      = 8,
    border      = 4,
    blur_size   = 6,
    blur_passes = 3,

    -- Khung kính: sáng ở trên, đậm dần xuống dưới như khung Aero.
    border_active   = { colors = { "rgba(cfeaffdd)", "rgba(74b8fcbb)", "rgba(3a7fd0cc)" }, angle = 90 },
    border_inactive = { colors = { "rgba(a9c3dd66)", "rgba(6f8fb055)" }, angle = 90 },

    -- Vệt sáng mờ ở mép trong cửa sổ.
    glow          = "rgba(ffffff26)",
    glow_inactive = "rgba(ffffff0f)",

    shadow          = "rgba(0a1a2e70)",
    shadow_inactive = "rgba(0a1a2e38)",
}
