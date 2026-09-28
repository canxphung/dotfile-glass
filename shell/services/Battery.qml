pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property var levels: ["\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}", "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"]
    readonly property var charging: ["\u{f089c}", "\u{f0086}", "\u{f0087}", "\u{f0088}", "\u{f089d}", "\u{f0089}", "\u{f089e}", "\u{f008a}", "\u{f008b}", "\u{f0085}"]

    function glyph(percent: int, isCharging: bool): string {
        const i = Math.max(0, Math.min(9, Math.ceil(percent / 10) - 1));
        return (isCharging ? charging : levels)[i];
    }
}
