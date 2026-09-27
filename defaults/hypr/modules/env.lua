-- Biến môi trường cho app chạy trong phiên.
-- Biến của phiên (XDG_CURRENT_DESKTOP, GLASS_SESSION...) do glass-session đặt.
--
-- NVIDIA: không tự đặt LIBVA_DRIVER_NAME / __GLX_VENDOR_LIBRARY_NAME ở đây
-- vì sai trên máy lai iGPU + NVIDIA. `glass-doctor` sẽ nhắc nếu cần.

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Qt lấy style từ qt6ct (Kvantum được cấu hình ở giai đoạn 5).
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
