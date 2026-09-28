pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Pin (UPower) và chế độ nguồn (power-profiles-daemon; trên CachyOS nó còn
// đổi chế độ của bộ lập lịch scx).
Singleton {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property int percent: Math.round((battery?.percentage ?? 0) * 100)
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: hasBattery && battery.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery

    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    function setProfile(p: int): void {
        PowerProfiles.profile = p;
    }

    // "Còn 2 giờ 15 phút" / "Đầy sau 40 phút".
    function timeText(): string {
        if (!hasBattery || full)
            return full ? "Đã đầy" : "";
        const seconds = charging ? battery.timeToFull : battery.timeToEmpty;
        if (!seconds || seconds <= 0)
            return charging ? "Đang sạc" : "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        const text = (h > 0 ? h + " giờ " : "") + m + " phút";
        return charging ? "Đầy sau " + text : "Còn " + text;
    }
}
