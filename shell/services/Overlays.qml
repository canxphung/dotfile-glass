pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Trạng thái các lớp phủ (start menu, control center, menu nguồn) và màn
// hình đang dùng. Mở cái này thì đóng cái kia.
Singleton {
    id: root

    readonly property bool hyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    // Màn hình đang có focus: thông báo và OSD hiện ở đây.
    readonly property ShellScreen activeScreen: (hyprland ? Array.from(Quickshell.screens).find(s => s.name === Hyprland.focusedMonitor?.name) : null) ?? Quickshell.screens[0] ?? null

    property bool startMenu: false
    property bool controlCenter: false
    property bool powerMenu: false
    property ShellScreen screen: Quickshell.screens[0] ?? null

    // Trang của control center: "main", "wifi", "bluetooth", "audio".
    property string page: "main"

    function closeAll(): void {
        startMenu = false;
        controlCenter = false;
        powerMenu = false;
    }

    function toggleStartMenu(on: ShellScreen): void {
        if (startMenu) {
            startMenu = false;
            return;
        }
        closeAll();
        screen = on ?? activeScreen;
        startMenu = true;
    }

    // Mở control center ở một trang ("main" nếu bỏ trống).
    function openControlCenter(on: ShellScreen, which: string): void {
        closeAll();
        screen = on ?? activeScreen;
        page = which || "main";
        controlCenter = true;
    }

    // Như khay của Windows: đang mở (trang nào cũng vậy) thì đóng.
    function toggleControlCenter(on: ShellScreen): void {
        if (controlCenter)
            controlCenter = false;
        else
            openControlCenter(on, "main");
    }

    function openPowerMenu(): void {
        closeAll();
        screen = activeScreen;
        powerMenu = true;
    }
}
