import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs.services
import qs.components

// Một thông báo. Bấm vào thân để chạy hành động mặc định (thường là mở
// app), nút × để đóng hẳn. Rê chuột lên thì không tự ẩn.
GlassRect {
    id: root

    required property Notification modelData
    readonly property Notification n: modelData
    readonly property var buttons: Array.from(n.actions).filter(a => a.identifier !== "default")
    readonly property var defaultAction: Array.from(n.actions).find(a => a.identifier === "default") ?? null

    width: 364
    height: layout.implicitHeight + 20
    fill: 0.8
    border.color: n.urgency === NotificationUrgency.Critical ? Theme.danger : Qt.alpha(Theme.edge, 0.85)

    Timer {
        interval: Notifs.timeoutFor(root.n)
        running: interval > 0 && !hover.hovered
        onTriggered: Notifs.hide(root.n)
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton && root.defaultAction) {
                root.defaultAction.invoke();
                Notifs.hide(root.n);
            } else {
                Notifs.hide(root.n);
            }
        }
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        AppIcon {
            Layout.alignment: Qt.AlignTop
            icon: root.n.image || root.n.appIcon
            size: 40
            visible: icon !== ""
        }

        Glyph {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            visible: !root.n.image && !root.n.appIcon
            text: root.n.urgency === NotificationUrgency.Critical ? "\u{f0026}" : "\u{f009a}"
            color: root.n.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.tintLight
            size: 30
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                Label {
                    Layout.fillWidth: true
                    text: root.n.appName
                    color: Theme.textMuted
                    font.pointSize: Theme.fontSize * 0.9
                }

                HoverButton {
                    implicitWidth: 22
                    implicitHeight: 22
                    glow: Theme.danger
                    onClicked: root.n.dismiss()

                    Glyph {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        size: 14
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.n.summary
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
            }

            Label {
                Layout.fillWidth: true
                visible: text !== ""
                // Bỏ <img>: không để thông báo tự tải ảnh từ mạng.
                text: root.n.body.replace(/<img[^>]*>/gi, "")
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 5
                opacity: 0.9
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.buttons.length > 0
                spacing: 6

                Repeater {
                    model: root.buttons

                    HoverButton {
                        required property NotificationAction modelData

                        width: actionLabel.implicitWidth + 20
                        height: 26
                        active: true
                        onClicked: {
                            modelData.invoke();
                            Notifs.hide(root.n);
                        }

                        Label {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: parent.modelData.text
                        }
                    }
                }
            }
        }
    }
}
