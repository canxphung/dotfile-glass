import QtQuick
import qs.services

// Nút kiểu taskbar Windows 7: không viền khi thường, hiện khung kính sáng
// khi rê chuột, quầng màu (glow) ở đáy lấy theo màu icon.
Item {
    id: root

    property bool active: false
    property bool highlighted: false
    property color glow: Theme.accentBright
    property int radius: 4
    property alias hovered: mouse.containsMouse
    property alias pressed: mouse.pressed
    property alias cursorShape: mouse.cursorShape

    signal clicked(var mouse)
    signal wheel(var wheel)

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.active || root.hovered || root.highlighted
        opacity: root.pressed ? 0.75 : 1
        border.width: 1
        border.color: Qt.alpha(Theme.highlight, root.hovered || root.highlighted ? 0.55 : 0.3)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Theme.highlight, root.hovered || root.highlighted ? 0.32 : 0.16)
            }
            GradientStop {
                position: 0.48
                color: Qt.alpha(Theme.highlight, root.hovered || root.highlighted ? 0.14 : 0.06)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(root.glow, root.hovered ? 0.5 : root.highlighted ? 0.3 : 0.12)
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => root.clicked(m)
        onWheel: w => root.wheel(w)
    }
}
