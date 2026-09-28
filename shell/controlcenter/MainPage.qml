import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.components

// Trang chính: công tắc nhanh, thanh trượt, pin, thông báo.
ColumnLayout {
    id: root

    spacing: 10

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8

        QuickTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: Net.glyph()
            title: "Wi-Fi"
            subtitle: Net.summary()
            checked: Net.wifiEnabled && Net.available
            hasPage: true
            onToggled: Net.setWifiEnabled(!Net.wifiEnabled)
            onOpened: Overlays.page = "wifi"
        }

        QuickTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: Bt.glyph()
            title: "Bluetooth"
            subtitle: Bt.summary()
            checked: Bt.enabled
            hasPage: true
            onToggled: Bt.setEnabled(!Bt.enabled)
            onOpened: Overlays.page = "bluetooth"
        }

        QuickTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: Notifs.dnd ? Icons.bellOff : Icons.bell
            title: "Không làm phiền"
            subtitle: Notifs.dnd ? "Đang bật" : "Tắt"
            checked: Notifs.dnd
            onToggled: Notifs.dnd = !Notifs.dnd
        }

        QuickTile {
            readonly property bool on: Glassd.settings["night_light.enabled"] === true

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: Glassd.connected
            opacity: enabled ? 1 : 0.5
            glyph: Icons.nightLight
            title: "Ánh sáng đêm"
            subtitle: on ? "Từ " + (Glassd.settings["night_light.start"] ?? "") : "Tắt"
            checked: on
            onToggled: Glassd.set("night_light.enabled", !on)
        }

        QuickTile {
            readonly property bool dark: Glassd.settings["appearance.color_scheme"] !== "light"

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: Glassd.connected
            opacity: enabled ? 1 : 0.5
            glyph: Icons.darkMode
            title: "Chế độ tối"
            subtitle: dark ? "Bật" : "Tắt"
            checked: dark
            onToggled: Glassd.set("appearance.color_scheme", dark ? "light" : "dark")
        }

        QuickTile {
            readonly property bool saver: Power.profile === PowerProfile.PowerSaver

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: Power.hasBattery
            glyph: Icons.powerSaver
            title: "Tiết kiệm pin"
            subtitle: saver ? "Bật" : "Tắt"
            checked: saver
            onToggled: Power.setProfile(saver ? PowerProfile.Balanced : PowerProfile.PowerSaver)
        }
    }

    // Âm lượng, micro, độ sáng.
    SliderRow {
        glyph: Audio.glyph()
        value: Audio.volume
        dimmed: Audio.muted
        visible: Audio.sink !== null
        hasPage: true
        onGlyphClicked: Audio.toggleMute()
        onMoved: v => Audio.setVolume(v)
        onOpened: Overlays.page = "audio"
    }

    SliderRow {
        glyph: Audio.micMuted ? Icons.microphoneOff : Icons.microphone
        value: Audio.micVolume
        dimmed: Audio.micMuted
        visible: Audio.source !== null
        onGlyphClicked: Audio.toggleMicMute()
        onMoved: v => Audio.setMicVolume(v)
    }

    SliderRow {
        glyph: Icons.brightness
        value: Brightness.level
        visible: Brightness.available
        onMoved: v => Brightness.set(v)
    }

    // Pin và chế độ nguồn.
    RowLayout {
        Layout.fillWidth: true
        visible: Power.hasBattery
        spacing: 8

        Glyph {
            text: Battery.glyph(Power.percent, Power.charging || Power.full)
            size: 20
        }

        Label {
            Layout.fillWidth: true
            text: "Pin " + Power.percent + "%" + (Power.timeText() ? " · " + Power.timeText() : "")
        }
    }

    // Chế độ nguồn (power-profiles-daemon): hiện trên laptop, hoặc máy bàn
    // có chế độ hiệu năng.
    RowLayout {
        Layout.fillWidth: true
        visible: Power.hasBattery || Power.hasPerformance
        spacing: 4

        Repeater {
            model: [
                { profile: PowerProfile.PowerSaver, glyph: Icons.powerSaver, text: "Tiết kiệm" },
                { profile: PowerProfile.Balanced, glyph: Icons.balanced, text: "Cân bằng" },
                { profile: PowerProfile.Performance, glyph: Icons.performance, text: "Hiệu năng" }
            ].filter(p => p.profile !== PowerProfile.Performance || Power.hasPerformance)

            HoverButton {
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 30
                active: true
                highlighted: Power.profile === modelData.profile
                onClicked: Power.setProfile(modelData.profile)

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Glyph {
                        text: parent.parent.modelData.glyph
                    }
                    Label {
                        text: parent.parent.modelData.text
                    }
                }
            }
        }
    }

    // Thông báo.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4

        SectionLabel {
            text: Notifs.history.length > 0 ? "Thông báo (" + Notifs.history.length + ")" : "Không có thông báo"
        }

        HoverButton {
            visible: Notifs.history.length > 0
            Layout.preferredWidth: clearLabel.implicitWidth + 36
            Layout.preferredHeight: 26
            onClicked: Notifs.dismissAll()

            Row {
                anchors.centerIn: parent
                spacing: 4

                Glyph {
                    text: Icons.clearAll
                    size: 14
                }
                Label {
                    id: clearLabel
                    text: "Xoá hết"
                }
            }
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 260)
        visible: count > 0
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: [...Notifs.history].reverse()
        }

        delegate: NotificationRow {
            width: ListView.view.width
        }
    }

    // Lối tắt.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 4

        Item {
            Layout.fillWidth: true
        }

        HoverButton {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 30
            onClicked: {
                Overlays.controlCenter = false;
                Glass.openPath(Glass.settingsFile);
            }

            Glyph {
                anchors.centerIn: parent
                text: "\u{f0493}"
            }
        }

        HoverButton {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 30
            glow: Theme.danger
            onClicked: Overlays.openPowerMenu()

            Glyph {
                anchors.centerIn: parent
                text: "\u{f0425}"
            }
        }
    }
}
