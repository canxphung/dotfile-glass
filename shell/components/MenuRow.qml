import QtQuick
import QtQuick.Layouts
import qs.services

// Một dòng trong menu kính: icon, chữ, nút đóng tuỳ chọn.
Item {
    id: root

    property string glyph
    property alias text: label.text
    property bool closable: false

    signal triggered
    signal closeRequested

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 16

    HoverButton {
        anchors.fill: parent
        onClicked: root.triggered()
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 4
        spacing: 8

        Glyph {
            Layout.preferredWidth: 18
            text: root.glyph
        }

        Label {
            id: label
            Layout.fillWidth: true
        }

        HoverButton {
            visible: root.closable
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            glow: Theme.danger
            onClicked: root.closeRequested()

            Glyph {
                anchors.centerIn: parent
                text: "\u{f0156}"
                size: 14
            }
        }
    }
}
