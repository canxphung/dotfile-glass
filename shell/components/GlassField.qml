import QtQuick
import QtQuick.Layouts
import qs.services

// Ô nhập chữ trên nền sáng/tối. `secret` để nhập mật khẩu, kèm nút hiện/ẩn.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property bool secret: false
    property bool reveal: false
    property alias input: input
    property alias validator: input.validator

    signal accepted

    implicitHeight: 32
    implicitWidth: 240
    radius: 3
    color: Qt.alpha(Theme.surface, 0.95)
    border.color: input.activeFocus ? Theme.accent : Qt.alpha(Theme.edge, 0.6)

    function focusInput(): void {
        input.forceActiveFocus();
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 4
        spacing: 4

        TextInput {
            id: input

            Layout.fillWidth: true
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.fontFamily
            font.pointSize: Theme.fontSize
            color: Theme.textOnSurface
            selectionColor: Theme.selection
            echoMode: root.secret && !root.reveal ? TextInput.Password : TextInput.Normal
            clip: true
            onAccepted: root.accepted()

            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: root.placeholder
                color: Theme.textOnSurface
                opacity: 0.5
                font.italic: true
            }
        }

        HoverButton {
            visible: root.secret
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            onClicked: root.reveal = !root.reveal

            Glyph {
                anchors.centerIn: parent
                text: root.reveal ? Icons.eyeOff : Icons.eye
                color: Theme.textOnSurface
                size: 15
            }
        }
    }
}
