-- Hyprland tự bật hyprland-session.target và graphical-session.target.
-- Glass gắn thêm glass-session.target (glass-idle, glass-wallpaper,
-- polkit agent, app autostart) qua systemd, nên không có lệnh exec lẻ
-- nào ở đây.

hl.on("hyprland.start", function()
    hl.exec_cmd("glass-session services")
end)
