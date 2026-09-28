pragma Singleton

import QtQuick
import Quickshell

// Mã icon (Material Design trong Symbols Nerd Font) dùng ở nhiều chỗ.
Singleton {
    readonly property string wifiOff: "\u{f092d}"
    readonly property string wifiDisabled: "\u{f05aa}"
    readonly property string wifiLimited: "\u{f092b}"
    readonly property var wifiStrength: ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"]
    readonly property string ethernet: "\u{f0200}"
    readonly property string ethernetOff: "\u{f0319}"
    readonly property string lock: "\u{f033e}"
    readonly property string eye: "\u{f0208}"
    readonly property string eyeOff: "\u{f0209}"

    readonly property string bluetooth: "\u{f00af}"
    readonly property string bluetoothOff: "\u{f00b2}"
    readonly property string bluetoothConnected: "\u{f00b1}"

    readonly property string speaker: "\u{f04c3}"
    readonly property string headphones: "\u{f02cb}"
    readonly property string microphone: "\u{f036c}"
    readonly property string microphoneOff: "\u{f036d}"
    readonly property string brightness: "\u{f00df}"

    readonly property string nightLight: "\u{f0594}"
    readonly property string darkMode: "\u{f050e}"
    readonly property string bell: "\u{f009a}"
    readonly property string bellOff: "\u{f009b}"
    readonly property string clearAll: "\u{f05e9}"

    readonly property string powerSaver: "\u{f032a}"
    readonly property string balanced: "\u{f05d1}"
    readonly property string performance: "\u{f04c5}"

    readonly property string back: "\u{f0141}"
    readonly property string forward: "\u{f0142}"
    readonly property string check: "\u{f012c}"
    readonly property string close: "\u{f0156}"
    readonly property string refresh: "\u{f0450}"

    // Icon chung của thiết bị Bluetooth theo tên icon BlueZ báo.
    function device(icon: string): string {
        if (icon.startsWith("audio-headset") || icon.startsWith("audio-headphones"))
            return headphones;
        if (icon.startsWith("audio"))
            return speaker;
        if (icon.startsWith("input-keyboard"))
            return "\u{f030c}";
        if (icon.startsWith("input-mouse") || icon.startsWith("input-tablet"))
            return "\u{f037d}";
        if (icon.startsWith("input-gaming"))
            return "\u{f0297}";
        if (icon.startsWith("phone"))
            return "\u{f011c}";
        if (icon.startsWith("computer"))
            return "\u{f0322}";
        if (icon.startsWith("video-display"))
            return "\u{f0379}";
        if (icon.startsWith("printer"))
            return "\u{f042a}";
        return bluetooth;
    }
}
