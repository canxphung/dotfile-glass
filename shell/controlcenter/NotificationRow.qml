import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.services
import qs.components

// Một thông báo trong lịch sử, gọn hơn popup. Bấm để mở (hành động mặc
// định), × để đóng hẳn.
Rectangle {
    id: root

    required property Notification modelData
    readonly property Notification n: modelData
    readonly property var defaultAction: Array.from(n.actions).find(a => a.identifier === "default") ?? null

    implicitHeight: layout.implicitHeight + 14
    radius: 5
    color: Qt.alpha(Theme.highlight, mouse.containsMouse ? 0.14 : 0.07)
    border.color: n.urgency === NotificationUrgency.Critical ? Theme.danger : Qt.alpha(Theme.highlight, 0.18)

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (root.defaultAction)
                root.defaultAction.invoke();
        }
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 4
        spacing: 8

        AppIcon {
            Layout.alignment: Qt.AlignTop
            icon: root.n.image || root.n.appIcon
            size: 28
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                Layout.fillWidth: true
                text: root.n.appName
                color: Theme.textMuted
                font.pointSize: Theme.fontSize * 0.85
            }

            Label {
                Layout.fillWidth: true
                text: root.n.summary
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.n.body.replace(/<[^>]*>/g, "")
                maximumLineCount: 2
                wrapMode: Text.Wrap
                opacity: 0.85
            }
        }

        HoverButton {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            glow: Theme.danger
            onClicked: root.n.dismiss()

            Glyph {
                anchors.centerIn: parent
                text: Icons.close
                size: 13
            }
        }
    }
}
