//@ pragma ShellId glass
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP = 1

// Shell của Glass: taskbar, start menu, thông báo, OSD, menu nguồn.
// Chạy bằng glass-shell (glass-shell.service); điều khiển bằng
// `glass-shell <target> <hàm>`, xem docs/ipc.md.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.taskbar
import qs.startmenu
import qs.notifications
import qs.osd
import qs.power

ShellRoot {
    // Shell cài trong /usr/share: không tự nạp lại khi file đổi giữa phiên.
    settings.watchFiles: Quickshell.env("GLASS_SHELL_WATCH") === "1"

    Variants {
        model: Quickshell.screens

        Taskbar {}
    }

    StartMenu {
        id: startMenu
    }

    PowerMenu {}

    NotificationPopups {}

    Osd {
        id: osd
    }

    IpcHandler {
        target: "startmenu"

        function toggle(): void {
            Overlays.toggleStartMenu(null);
        }
        function open(): void {
            if (!Overlays.startMenu)
                Overlays.toggleStartMenu(null);
        }
        function close(): void {
            Overlays.startMenu = false;
        }
        function isOpen(): bool {
            return Overlays.startMenu;
        }
        // Tên các app đang hiện trong danh sách, mỗi dòng một app.
        function entries(): string {
            return startMenu.entries.map(e => e.name).join("\n");
        }
    }

    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            if (Overlays.powerMenu)
                Overlays.powerMenu = false;
            else
                Overlays.openPowerMenu();
        }
        function open(): void {
            Overlays.openPowerMenu();
        }
        function close(): void {
            Overlays.powerMenu = false;
        }
        function isOpen(): bool {
            return Overlays.powerMenu;
        }
    }

    IpcHandler {
        target: "osd"

        // Gọi sau khi đổi độ sáng (phím sáng/tối).
        function brightness(): void {
            Brightness.refresh();
        }
        function volume(): void {
            osd.showVolume();
        }
        function isVisible(): bool {
            return osd.shown;
        }
    }

    IpcHandler {
        target: "notifications"

        function toggleDnd(): void {
            Notifs.dnd = !Notifs.dnd;
        }
        function dnd(): bool {
            return Notifs.dnd;
        }
        function dismissAll(): void {
            Notifs.dismissAll();
        }
        // Số popup đang hiện và số thông báo còn giữ.
        function popups(): int {
            return Notifs.popups.length;
        }
        function history(): int {
            return Notifs.history.length;
        }
    }

    IpcHandler {
        target: "shell"

        // Các nút trên taskbar, mỗi dòng "id số_cửa_sổ".
        function tasks(): string {
            return Tasks.groups.map(g => g.key + " " + g.windows.length).join("\n");
        }
        function palette(): string {
            return Theme.palette.name ?? "";
        }
        function tint(): string {
            return Theme.tint.toString();
        }
    }
}
