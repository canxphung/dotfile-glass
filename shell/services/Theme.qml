pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Màu, font, kích thước của shell.
//
// Màu lấy từ ~/.local/state/glass/theme/shell.json do glassd sinh ra từ
// palette đang chọn; file đổi là shell đổi theo ngay. Chưa có file (glassd
// chưa chạy lần nào) thì dùng Aero Sky có sẵn dưới đây.
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glass"

    property var data: ({})
    readonly property var palette: data.palette ?? fallback

    readonly property bool dark: (data.color_scheme ?? "dark") !== "light"

    readonly property color tint: palette.glass.tint
    readonly property color tintLight: palette.glass.tint_light
    readonly property color tintDeep: palette.glass.tint_deep
    readonly property color edge: palette.glass.edge
    readonly property color highlight: palette.glass.highlight
    readonly property color shadow: palette.glass.shadow

    readonly property color textOnGlass: palette.text.on_dark
    readonly property color textMuted: palette.text.muted
    readonly property color textOnLight: palette.text.on_glass

    readonly property color surface: dark ? palette.surface.dark : palette.surface.light
    readonly property color textOnSurface: dark ? palette.text.on_dark : palette.text.on_glass

    readonly property color accent: palette.accent.normal
    readonly property color accentBright: palette.accent.bright
    readonly property color selection: palette.accent.selection

    readonly property color danger: palette.state.danger
    readonly property color warning: palette.state.warning
    readonly property color success: palette.state.success

    readonly property int radius: palette.shape.radius

    readonly property string fontFamily: data.font_family ?? "Noto Sans"
    readonly property real fontSize: data.font_size ?? 10
    readonly property string monoFamily: data.monospace_family ?? "JetBrainsMono Nerd Font"
    // Icon dạng chữ: Material Design trong Symbols Nerd Font.
    readonly property string iconFamily: "Symbols Nerd Font"

    readonly property int barHeight: 42

    // Kính: nền pha màu tint, đậm dần xuống dưới như thanh taskbar Aero.
    function glass(alpha: real): color {
        return Qt.alpha(Qt.tint(palette.surface.dark, Qt.alpha(tintDeep, 0.35)), alpha);
    }

    FileView {
        path: root.stateDir + "/theme/shell.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed.palette?.glass)
                    root.data = parsed;
            } catch (e) {
                console.warn("Theme: shell.json hỏng, giữ màu cũ:", e);
            }
        }
    }

    // Aero Sky, giống theme/palettes/sky.toml.
    readonly property var fallback: ({
        name: "sky",
        glass: {
            tint: "#74b8fc",
            tint_light: "#cfeaff",
            tint_deep: "#3a7fd0",
            inactive_light: "#a9c3dd",
            inactive_deep: "#6f8fb0",
            edge: "#0e2a47",
            highlight: "#ffffff",
            shadow: "#0a1a2e"
        },
        text: {
            on_glass: "#0b1a2b",
            on_dark: "#eaf4ff",
            muted: "#8aa4c0"
        },
        surface: {
            dark: "#0c1726",
            light: "#f3f8fd"
        },
        accent: {
            normal: "#2b8ce6",
            bright: "#8fd3ff",
            selection: "#2b5c8f"
        },
        state: {
            danger: "#e5534b",
            warning: "#e8c46a",
            success: "#6cc070"
        },
        shape: {
            radius: 8,
            border: 4,
            blur_size: 6,
            blur_passes: 3
        }
    })
}
