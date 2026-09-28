import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Một app trong start menu. Dạng đầy đủ có icon lớn và mô tả; dạng gọn
// (danh sách tất cả ứng dụng) một dòng.
Item {
    id: root

    property var entry: null
    property bool compact: false
    property bool selected: false
    property string glyph
    property string title: entry?.name ?? ""
    readonly property alias hovered: mouse.containsMouse

    signal activated

    implicitHeight: compact ? 30 : 42

    // Ô chọn xanh nhạt có viền như Windows 7.
    Rectangle {
        anchors.fill: parent
        visible: root.selected || root.hovered
        radius: 3
        border.color: Qt.alpha(Theme.accent, 0.7)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Theme.accentBright, 0.28)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Theme.accent, 0.38)
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 8

        AppIcon {
            visible: root.entry !== null
            icon: root.entry?.icon ?? ""
            size: root.compact ? 20 : 30
        }

        Glyph {
            visible: root.entry === null
            Layout.preferredWidth: 20
            text: root.glyph
            color: Theme.textOnSurface
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                Layout.fillWidth: true
                text: root.title
                color: Theme.textOnSurface
                font.bold: root.entry === null
            }

            Label {
                Layout.fillWidth: true
                visible: !root.compact && text !== ""
                text: root.entry?.genericName || root.entry?.comment || ""
                color: Theme.textOnSurface
                opacity: 0.6
                font.pointSize: Theme.fontSize * 0.9
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}
