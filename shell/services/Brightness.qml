pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Độ sáng màn hình qua brightnessctl. Phím sáng/tối do Hyprland gọi
// brightnessctl rồi báo shell (`glass-shell osd brightness`) để hiện OSD.
Singleton {
    id: root

    property real level: 0
    property bool available: false

    signal changed

    function refresh(): void {
        query.running = true;
    }

    function set(value: real): void {
        const percent = Math.round(Math.max(0.01, Math.min(1, value)) * 100);
        Quickshell.execDetached(["brightnessctl", "--quiet", "set", percent + "%"]);
        level = percent / 100;
        changed();
    }

    // brightnessctl -m: "intel_backlight,backlight,1200,50%,2400"
    Process {
        id: query
        command: ["brightnessctl", "--machine-readable", "--class=backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(",");
                if (fields.length >= 5 && Number(fields[4]) > 0) {
                    root.level = Number(fields[2]) / Number(fields[4]);
                    root.available = true;
                    root.changed();
                }
            }
        }
    }
}
