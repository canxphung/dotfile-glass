pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Trạng thái các lớp phủ (start menu, menu nguồn) và màn hình đang dùng.
Singleton {
    id: root

    readonly property bool hyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    // Màn hình đang có focus: thông báo và OSD hiện ở đây.
    readonly property ShellScreen activeScreen: (hyprland ? Array.from(Quickshell.screens).find(s => s.name === Hyprland.focusedMonitor?.name) : null) ?? Quickshell.screens[0] ?? null

    property bool startMenu: false
    property bool powerMenu: false
    property ShellScreen screen: Quickshell.screens[0] ?? null

    function toggleStartMenu(on: ShellScreen): void {
        if (startMenu) {
            startMenu = false;
            return;
        }
        powerMenu = false;
        screen = on ?? activeScreen;
        startMenu = true;
    }

    function openPowerMenu(): void {
        startMenu = false;
        screen = activeScreen;
        powerMenu = true;
    }
}
