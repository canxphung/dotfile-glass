-- Luật cho cửa sổ và layer.

-- Bỏ qua yêu cầu tự phóng to của app; layout quyết định kích thước.
hl.window_rule({
    name  = "glass-suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Sửa lỗi kéo thả với vài app XWayland.
hl.window_rule({
    name  = "glass-fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- Đang xem video/chơi game toàn màn hình thì không tự khoá máy.
hl.window_rule({
    name  = "glass-idle-inhibit-fullscreen",
    match = { class = ".*" },
    idle_inhibit = "fullscreen",
})

-- Hộp thoại xác thực: nổi giữa màn hình, làm tối xung quanh như UAC.
hl.window_rule({
    name  = "glass-polkit",
    match = { class = "^hyprpolkitagent$" },
    float      = true,
    center     = true,
    pin        = true,
    dim_around = true,
})

-- Hộp thoại chọn file của portal GTK.
hl.window_rule({
    name  = "glass-file-chooser",
    match = { class = "^xdg-desktop-portal-gtk$" },
    float  = true,
    center = true,
    size   = { "monitor_w*0.6", "monitor_h*0.65" },
})

-- Picture-in-picture của trình duyệt: nổi, ghim, góc dưới phải.
hl.window_rule({
    name  = "glass-pip",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float             = true,
    pin               = true,
    keep_aspect_ratio = true,
    size              = { "monitor_w*0.25", "monitor_h*0.25" },
    move              = { "monitor_w*0.73", "monitor_h*0.72" },
})

-- Các bề mặt của shell Glass (giai đoạn 3) đặt namespace "glass-*":
-- blur phía sau, bỏ qua vùng gần như trong suốt.
hl.layer_rule({
    name  = "glass-shell-blur",
    match = { namespace = "^glass-" },
    blur         = true,
    ignore_alpha = 0.2,
})
