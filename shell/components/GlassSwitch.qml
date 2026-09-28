import QtQuick
import qs.services

// Công tắc bật/tắt nhỏ. Bấm thì phát `toggled(!checked)`; trạng thái thật
// do nơi dùng quyết định (vd. Wi-Fi chỉ bật khi NetworkManager bật xong).
Item {
    id: root

    property bool checked: false

    signal toggled(bool on)

    implicitWidth: 40
    implicitHeight: 22
    opacity: enabled ? 1 : 0.5

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        border.color: Qt.alpha(Theme.edge, 0.9)
        color: root.checked ? Theme.accent : Qt.alpha(Theme.shadow, 0.6)

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    Rectangle {
        x: root.checked ? parent.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: parent.height - 6
        height: width
        radius: width / 2
        color: "white"
        opacity: 0.95

        Behavior on x {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
