-- Phần "kính": viền, bo góc, bóng, blur.
--
-- Hướng (a) đã chốt: không có titlebar. Khung Aero được giả lập bằng
-- viền dày gradient + vệt sáng mép trong (glow) + bóng đổ + blur phía sau
-- các app có nền trong suốt.

local c = require("@GLASS_DATADIR@/hypr/modules/colors")

hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 12,
        border_size = c.border,

        col = {
            active_border   = c.border_active,
            inactive_border = c.border_inactive,
        },

        -- Kéo viền để đổi kích thước, như cửa sổ thường.
        resize_on_border        = true,
        extend_border_grab_area = 12,
        hover_icon_on_border    = true,
    },

    decoration = {
        rounding       = c.radius,
        rounding_power = 2,

        -- Giữ chữ rõ: độ trong suốt chỉnh ở từng app (vd. kitty),
        -- không làm mờ cả cửa sổ.
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled        = true,
            range          = 24,
            render_power   = 3,
            offset         = { 0, 6 },
            color          = c.shadow,
            color_inactive = c.shadow_inactive,
        },

        glow = {
            enabled        = true,
            range          = 8,
            render_power   = 3,
            color          = c.glow,
            color_inactive = c.glow_inactive,
        },

        blur = {
            enabled           = true,
            size              = c.blur_size,
            passes            = c.blur_passes,
            noise             = 0.02,
            contrast          = 1.0,
            brightness        = 1.05,
            vibrancy          = 0.25,
            vibrancy_darkness = 0.1,
            new_optimizations = true,
            -- xray = false: kính thấy cả cửa sổ phía sau, đúng chất Aero
            -- nhưng tốn GPU hơn. Máy yếu thì đặt true trong file của bạn.
            xray              = false,
            popups            = true,
            -- Ô gợi ý của bộ gõ (fcitx5) cũng là kính.
            input_methods     = true,
            special           = false,
        },

        dim_special = 0.25,
    },
})
