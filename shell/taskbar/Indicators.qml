import QtQuick
import Quickshell
import qs.services
import qs.components

// Mạng, Bluetooth, âm lượng, pin: gộp một nút, bấm để mở control center,
// lăn chuột để chỉnh âm lượng. Chuông thông báo bên cạnh.
Row {
    id: root

    required property var screen

    spacing: 1

    HoverButton {
        anchors.verticalCenter: parent.verticalCenter
        width: icons.implicitWidth + 14
        height: 32
        highlighted: Overlays.controlCenter && Overlays.screen === root.screen
        onClicked: Overlays.toggleControlCenter(root.screen)
        onWheel: wheel => Audio.setVolume(Audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))

        Row {
            id: icons
            anchors.centerIn: parent
            spacing: 6

            Glyph {
                text: Net.glyph()
                size: 17
                opacity: Net.available && (Net.activeWifi || Net.wiredConnected) ? 1 : 0.6
            }

            Glyph {
                visible: Bt.available && Bt.enabled
                text: Bt.glyph()
                size: 17
                opacity: Bt.connected.length > 0 ? 1 : 0.6
            }

            Glyph {
                visible: Audio.sink !== null
                text: Audio.glyph()
                size: 18
                opacity: Audio.muted ? 0.6 : 1
            }

            Row {
                visible: Power.hasBattery
                spacing: 2

                Glyph {
                    text: Battery.glyph(Power.percent, Power.charging || Power.full)
                    size: 18
                    color: Power.percent <= 10 && !Power.charging ? Theme.danger : Theme.textOnGlass
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Power.percent + "%"
                }
            }
        }
    }

    // Chuông: chấm sáng khi có thông báo, gạch chéo khi không làm phiền.
    HoverButton {
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 32
        highlighted: Notifs.dnd
        onClicked: Overlays.toggleControlCenter(root.screen)

        Glyph {
            anchors.centerIn: parent
            text: Notifs.dnd ? Icons.bellOff : Notifs.history.length > 0 ? "\u{f116b}" : Icons.bell
            size: 18
        }
    }
}
