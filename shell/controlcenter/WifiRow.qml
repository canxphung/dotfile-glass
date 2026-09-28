import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.services
import qs.components

// Một mạng Wi-Fi. Mở rộng thì hiện nút; nếu kết nối thất bại vì thiếu mật
// khẩu mà không có glassd để hỏi, hiện ô nhập mật khẩu ngay tại đây.
Rectangle {
    id: root

    required property var modelData
    readonly property var network: modelData
    property bool expanded: false
    property bool askPassword: false
    property string failure: ""

    signal clicked

    implicitHeight: column.implicitHeight + 12
    radius: 5
    color: Qt.alpha(Theme.highlight, expanded ? 0.14 : mouse.containsMouse ? 0.08 : 0)
    border.color: expanded ? Qt.alpha(Theme.highlight, 0.25) : "transparent"

    onExpandedChanged: {
        if (!expanded) {
            askPassword = false;
            failure = "";
        }
    }

    Connections {
        target: root.network

        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets && !Glassd.connected) {
                root.askPassword = true;
                root.failure = "";
                password.focusInput();
            } else if (reason === ConnectionFailReason.NoSecrets) {
                root.failure = "Chưa nhập mật khẩu.";
            } else {
                root.failure = "Không kết nối được. Thử lại hoặc quên mạng rồi nhập lại mật khẩu.";
            }
        }

        function onConnectedChanged() {
            if (root.network.connected) {
                root.askPassword = false;
                root.failure = "";
            }
        }
    }

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

            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                Glyph {
                    anchors.centerIn: parent
                    text: Net.strengthGlyph(root.network.signalStrength)
                    size: 18
                    color: root.network.connected ? Theme.accentBright : Theme.textOnGlass
                }

                Glyph {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: Net.secured(root.network)
                    text: Icons.lock
                    size: 10
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    text: root.network.name
                    font.bold: root.network.connected
                }

                Label {
                    Layout.fillWidth: true
                    text: Net.stateText(root.network)
                    opacity: 0.75
                    font.pointSize: Theme.fontSize * 0.85
                }
            }
        }

        GlassField {
            id: password
            Layout.fillWidth: true
            visible: root.expanded && root.askPassword
            secret: true
            placeholder: "Mật khẩu"
            onAccepted: connectButton.clicked(null)
        }

        Label {
            Layout.fillWidth: true
            visible: root.expanded && root.failure !== ""
            text: root.failure
            color: Theme.warning
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6

            Item {
                Layout.fillWidth: true
            }

            HoverButton {
                visible: root.network.known
                Layout.preferredWidth: forgetLabel.implicitWidth + 24
                Layout.preferredHeight: 28
                active: true
                glow: Theme.danger
                onClicked: root.network.forget()

                Label {
                    id: forgetLabel
                    anchors.centerIn: parent
                    text: "Quên"
                }
            }

            HoverButton {
                id: connectButton
                Layout.preferredWidth: connectLabel.implicitWidth + 24
                Layout.preferredHeight: 28
                active: true
                highlighted: !root.network.connected
                onClicked: {
                    root.failure = "";
                    if (root.network.connected)
                        root.network.disconnect();
                    else if (root.askPassword && password.text !== "")
                        root.network.connectWithPsk(password.text);
                    else
                        root.network.connect();
                }

                Label {
                    id: connectLabel
                    anchors.centerIn: parent
                    text: root.network.connected ? "Ngắt kết nối" : root.network.stateChanging ? "Đang kết nối…" : "Kết nối"
                }
            }
        }
    }
}
