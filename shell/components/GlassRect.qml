import QtQuick
import qs.services

// Mặt kính Aero: nền trong mờ pha màu palette, vệt sáng ở nửa trên, viền
// tối bên ngoài và viền sáng bên trong. Blur phía sau do Hyprland làm
// (layer rule cho namespace "glass-*").
Rectangle {
    id: root

    // Độ đục của nền. Hyprland chỉ blur chỗ có alpha trên 0.2.
    property real fill: 0.6
    property bool shine: true

    radius: Theme.radius
    color: Theme.glass(fill)
    border.color: Qt.alpha(Theme.edge, 0.85)
    border.width: 1

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.color: Qt.alpha(Theme.highlight, 0.22)
        border.width: 1
    }

    Rectangle {
        visible: root.shine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 2
        height: Math.min(parent.height * 0.5, 60)
        radius: Math.max(0, root.radius - 2)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Theme.highlight, 0.16)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Theme.highlight, 0.03)
            }
        }
    }
}
