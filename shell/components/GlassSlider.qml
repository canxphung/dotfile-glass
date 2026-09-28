import QtQuick
import qs.services

// Thanh trượt kiểu Aero: rãnh tối lõm, phần đã chọn sáng dần, núm kính.
// Kéo, bấm hoặc lăn chuột để đổi; `moved(value)` báo giá trị mới (0..1).
Item {
    id: root

    property real value: 0
    property bool dimmed: false
    readonly property alias pressed: mouse.pressed

    signal moved(real value)

    implicitHeight: 22
    implicitWidth: 200

    function valueAt(x: real): real {
        return Math.max(0, Math.min(1, (x - knob.width / 2) / (width - knob.width)));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: knob.width / 2
        width: parent.width - knob.width
        height: 6
        radius: 3
        color: Qt.alpha(Theme.shadow, 0.6)
        border.color: Qt.alpha(Theme.edge, 0.8)

        Rectangle {
            width: parent.width * root.value
            height: parent.height
            radius: 3
            opacity: root.dimmed ? 0.35 : 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: Theme.accent
                }
                GradientStop {
                    position: 1
                    color: Theme.accentBright
                }
            }
        }
    }

    Rectangle {
        id: knob
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) * root.value
        width: 16
        height: 16
        radius: 8
        border.color: Qt.alpha(Theme.edge, 0.9)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: mouse.containsMouse || mouse.pressed ? "white" : Theme.tintLight
            }
            GradientStop {
                position: 1
                color: Theme.tint
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onPressed: m => root.moved(root.valueAt(m.x))
        onPositionChanged: m => {
            if (pressed)
                root.moved(root.valueAt(m.x));
        }
        onWheel: w => root.moved(Math.max(0, Math.min(1, root.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
