-- Sinh bởi glassd từ palette "sky". Đừng sửa: file sẽ bị ghi đè.
-- Cấu trúc khớp bảng dự phòng trong hypr/modules/colors.lua của Glass.

return {
    radius      = 8,
    border      = 4,
    blur_size   = 6,
    blur_passes = 3,

    border_active   = { colors = { "rgba(cfeaffdd)", "rgba(74b8fcbb)", "rgba(3a7fd0cc)" }, angle = 90 },
    border_inactive = { colors = { "rgba(a9c3dd66)", "rgba(6f8fb055)" }, angle = 90 },

    glow          = "rgba(ffffff26)",
    glow_inactive = "rgba(ffffff0f)",

    shadow          = "rgba(0a1a2e70)",
    shadow_inactive = "rgba(0a1a2e38)",

    background = "rgba(0c1726ff)",
}
