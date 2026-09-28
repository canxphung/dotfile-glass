import QtQuick
import Quickshell
import qs.services

// Các nút app trên taskbar, chỉ có icon (xem Tasks).
Item {
    id: root

    required property var window

    Row {
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - 4
        spacing: 2

        Repeater {
            model: ScriptModel {
                values: Tasks.groups
                objectProp: "key"
            }

            TaskButton {
                window: root.window
                height: parent.height
            }
        }
    }
}
