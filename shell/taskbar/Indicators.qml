import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.components

// Âm lượng, pin, thông báo.
Row {
    id: root

    spacing: 1

    // Âm lượng: bấm để tắt/bật tiếng, lăn chuột để chỉnh.
    HoverButton {
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 32
        visible: Audio.sink !== null
        onClicked: Audio.toggleMute()
        onWheel: wheel => Audio.setVolume(Audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))

        Glyph {
            anchors.centerIn: parent
            text: Audio.glyph()
            size: 18
            opacity: Audio.muted ? 0.6 : 1
        }
    }

    // Pin: chỉ hiện trên laptop.
    Item {
        readonly property var battery: UPower.displayDevice
        readonly property bool charging: battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged || battery.state === UPowerDeviceState.PendingCharge
        readonly property int percent: Math.round(battery.percentage * 100)

        anchors.verticalCenter: parent.verticalCenter
        visible: battery.isLaptopBattery
        width: visible ? batteryRow.implicitWidth + 10 : 0
        height: 32

        Row {
            id: batteryRow
            anchors.centerIn: parent
            spacing: 2

            Glyph {
                text: Battery.glyph(parent.parent.percent, parent.parent.charging)
                size: 18
                color: parent.parent.percent <= 10 && !parent.parent.charging ? Theme.danger : Theme.textOnGlass
            }

            Label {
                text: parent.parent.percent + "%"
            }
        }
    }

    // Thông báo: chấm sáng khi có thông báo, bấm để bật/tắt không làm phiền.
    HoverButton {
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 32
        highlighted: Notifs.dnd
        onClicked: Notifs.dnd = !Notifs.dnd

        Glyph {
            anchors.centerIn: parent
            text: Notifs.dnd ? "\u{f009b}" : Notifs.history.length > 0 ? "\u{f116b}" : "\u{f009a}"
            size: 18
        }
    }
}
