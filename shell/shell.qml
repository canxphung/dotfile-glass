//@ pragma ShellId glass
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP = 1

// Shell của Glass: taskbar, start menu, control center, thông báo, OSD,
// menu nguồn, hộp thoại mật khẩu Wi-Fi / ghép nối Bluetooth.
// Chạy bằng glass-shell (glass-shell.service); điều khiển bằng
// `glass-shell <target> <hàm>`, xem docs/ipc.md.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.taskbar
import qs.startmenu
import qs.controlcenter
import qs.notifications
import qs.osd
import qs.power
import qs.prompts

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

    ControlCenter {}

    PowerMenu {}

    NotificationPopups {}

    Osd {
        id: osd
    }

    PromptDialog {}

    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            Overlays.toggleControlCenter(null);
        }
        // Mở ở một trang: main, wifi, bluetooth, audio.
        function open(page: string): void {
            if (!Overlays.controlCenter || Overlays.page !== page)
                Overlays.openControlCenter(null, page);
        }
        function close(): void {
            Overlays.controlCenter = false;
        }
        function isOpen(): bool {
            return Overlays.controlCenter;
        }
        function page(): string {
            return Overlays.controlCenter ? Overlays.page : "";
        }
    }

    IpcHandler {
        target: "network"

        function status(): string {
            return Net.summary();
        }
        // Mạng Wi-Fi, mỗi dòng "tên<TAB>trạng thái<TAB>sóng %<TAB>khoá".
        function list(): string {
            return Net.networks.map(n => [n.name, Net.stateText(n), Math.round(n.signalStrength * 100), Net.secured(n) ? "khoá" : "mở"].join("\t")).join("\n");
        }
        function scan(on: bool): void {
            Net.scanning = on;
        }
        function wifi(on: bool): void {
            Net.setWifiEnabled(on);
        }
        function connect(name: string): void {
            Net.networks.find(n => n.name === name)?.connect();
        }
        function disconnect(name: string): void {
            Net.networks.find(n => n.name === name)?.disconnect();
        }
        function forget(name: string): void {
            Net.networks.find(n => n.name === name)?.forget();
        }
    }

    IpcHandler {
        target: "bluetooth"

        function status(): string {
            return Bt.summary();
        }
        // Thiết bị, mỗi dòng "tên<TAB>trạng thái".
        function list(): string {
            return Bt.devices.map(d => [d.name || d.address, Bt.stateText(d)].join("\t")).join("\n");
        }
        function power(on: bool): void {
            Bt.setEnabled(on);
        }
        function scan(on: bool): void {
            Bt.discovering = on;
        }
        function pair(name: string): void {
            const device = Bt.devices.find(d => d.name === name);
            if (device)
                Bt.pairAndConnect(device);
        }
        function connect(name: string): void {
            Bt.devices.find(d => d.name === name)?.connect();
        }
        function disconnect(name: string): void {
            Bt.devices.find(d => d.name === name)?.disconnect();
        }
        function forget(name: string): void {
            Bt.devices.find(d => d.name === name)?.forget();
        }
    }

    IpcHandler {
        target: "prompts"

        // Hộp thoại đang hiện (JSON), rỗng nếu không có.
        function current(): string {
            return Glassd.prompts.length > 0 ? JSON.stringify(Glassd.prompts[0]) : "";
        }
        function connected(): bool {
            return Glassd.connected;
        }
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
        target: "audio"

        // "loa<TAB>âm lượng %<TAB>bật|tắt tiếng", rỗng nếu chưa có loa.
        function status(): string {
            return Audio.sink ? [Audio.label(Audio.sink), Math.round(Audio.volume * 100), Audio.muted ? "tắt tiếng" : "bật"].join("\t") : "";
        }
        // Các loa, loa đang dùng đánh dấu "*".
        function sinks(): string {
            return Audio.sinks.map(n => (n === Audio.sink ? "* " : "  ") + Audio.label(n)).join("\n");
        }
        function setVolume(percent: int): void {
            Audio.setVolume(percent / 100);
        }
        function toggleMute(): void {
            Audio.toggleMute();
        }
        function setDefault(name: string): void {
            const node = Audio.sinks.find(n => Audio.label(n) === name);
            if (node)
                Audio.setDefault(node);
        }
    }

    IpcHandler {
        target: "osd"

        // Gọi sau khi đổi độ sáng (phím sáng/tối).
        function brightness(): void {
            Brightness.refresh(true);
        }
        function volume(): void {
            osd.showVolume();
        }
        function isVisible(): bool {
            return osd.shown;
        }
        // Mức (%) OSD đang hiện.
        function level(): int {
            return Math.round(osd.value * 100);
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
