import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Đầu trang con: nút quay lại, tiêu đề, công tắc (tuỳ chọn).
RowLayout {
    id: root

    property string title
    property bool hasSwitch: false
    property bool checked: false

    signal back
    signal toggled(bool on)

    spacing: 8

    HoverButton {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        onClicked: root.back()

        Glyph {
            anchors.centerIn: parent
            text: Icons.back
            size: 18
        }
    }

    Label {
        Layout.fillWidth: true
        text: root.title
        font.pointSize: Theme.fontSize * 1.3
    }

    GlassSwitch {
        visible: root.hasSwitch
        checked: root.checked
        onToggled: on => root.toggled(on)
    }
}
