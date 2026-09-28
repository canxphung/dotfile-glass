import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Một thiết bị Bluetooth. Mở rộng thì hiện nút: ghép nối (thiết bị mới),
// kết nối / ngắt, quên.
Rectangle {
    id: root

    required property var modelData
    readonly property var device: modelData
    property bool expanded: false

    signal clicked

    implicitHeight: column.implicitHeight + 12
    radius: 5
    color: Qt.alpha(Theme.highlight, expanded ? 0.14 : mouse.containsMouse ? 0.08 : 0)
    border.color: expanded ? Qt.alpha(Theme.highlight, 0.25) : "transparent"

    MouseArea {
        id: mouse
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: header.height + 12
        hoverEnabled: true
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 6

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 8

            Glyph {
                Layout.preferredWidth: 24
                text: Icons.device(root.device.icon)
                size: 18
                color: root.device.connected ? Theme.accentBright : Theme.textOnGlass
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    text: root.device.name || root.device.address
                    font.bold: root.device.connected
                }

                Label {
                    Layout.fillWidth: true
                    text: Bt.stateText(root.device)
                    opacity: 0.75
                    font.pointSize: Theme.fontSize * 0.85
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6

            Item {
                Layout.fillWidth: true
            }

            HoverButton {
                visible: root.device.paired
                Layout.preferredWidth: forgetLabel.implicitWidth + 24
                Layout.preferredHeight: 28
                active: true
                glow: Theme.danger
                onClicked: root.device.forget()

                Label {
                    id: forgetLabel
                    anchors.centerIn: parent
                    text: "Quên"
                }
            }

            HoverButton {
                Layout.preferredWidth: actionLabel.implicitWidth + 24
                Layout.preferredHeight: 28
                active: true
                highlighted: !root.device.connected
                onClicked: {
                    if (root.device.pairing)
                        root.device.cancelPair();
                    else if (!root.device.paired)
                        Bt.pairAndConnect(root.device);
                    else if (root.device.connected)
                        root.device.disconnect();
                    else
                        root.device.connect();
                }

                Label {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: root.device.pairing ? "Huỷ ghép nối" : !root.device.paired ? "Ghép nối" : root.device.connected ? "Ngắt kết nối" : "Kết nối"
                }
            }
        }
    }
}
