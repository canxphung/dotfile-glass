pragma Singleton

import QtQuick
import Quickshell

// Chạy chương trình và thao tác phiên, qua glass-session.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: Quickshell.env("USER") || home.split("/").pop()
    readonly property string terminal: "kitty"
    readonly property string settingsFile: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/glass/settings.toml"

    // Mỗi app chạy trong một scope systemd riêng (app-glass-<id>-<số>.scope),
    // nên khởi động lại shell không kéo app theo, và systemd-oomd, systemd-cgls
    // thấy từng app.
    function run(id: string, command: var): void {
        Quickshell.execDetached(["glass-session", "run", id, ...command]);
    }

    function openPath(path: string): void {
        run("xdg-open", ["xdg-open", path]);
    }

    // lock, logout, suspend, reboot, poweroff
    function session(action: string): void {
        Quickshell.execDetached(["glass-session", action]);
    }
}
