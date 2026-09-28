-- Cách xếp cửa sổ và các hành vi chung.

local c = require("@GLASS_DATADIR@/hypr/modules/colors")

hl.config({
    general = {
        layout = "dwindle",
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        -- Tắt hình nền và logo mặc định của Hyprland; hình nền do hyprpaper vẽ.
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        -- Nền phía sau hình nền, thấy trong tích tắc lúc hyprpaper chưa lên.
        background_color         = c.background,
    },

    binds = {
        workspace_back_and_forth = true,
    },
})
