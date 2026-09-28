import QtQuick
import QtQuick.Layouts
import qs.services

// Ô công tắc nhanh trong control center: bấm phần trái để bật/tắt, mũi tên
// bên phải (nếu có) để mở trang chi tiết.
Item {
    id: root

    property string glyph
    property string title
    property string subtitle
    property bool checked: false
    property bool hasPage: false

    signal toggled
    signal opened

    implicitHeight: 52

    Rectangle {
        anchors.fill: parent
        radius: 6
        border.color: root.checked ? Qt.alpha(Theme.accentBright, 0.8) : Qt.alpha(Theme.highlight, 0.25)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.checked ? Qt.alpha(Theme.accentBright, 0.55) : Qt.alpha(Theme.highlight, 0.12)
            }
            GradientStop {
                position: 1
                color: root.checked ? Qt.alpha(Theme.accent, 0.7) : Qt.alpha(Theme.highlight, 0.04)
            }
        }
    }

    HoverButton {
        id: main
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: root.hasPage ? arrow.left : parent.right
        radius: 6
        onClicked: root.toggled()

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 4
            spacing: 8

            Glyph {
                text: root.glyph
                size: 20
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    text: root.title
                    font.bold: true
                }

                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.subtitle
                    opacity: 0.8
                    font.pointSize: Theme.fontSize * 0.85
                }
            }
        }
    }

    HoverButton {
        id: arrow
        visible: root.hasPage
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.hasPage ? 26 : 0
        radius: 6
        onClicked: root.opened()

        Glyph {
            anchors.centerIn: parent
            text: Icons.forward
        }
    }
}
