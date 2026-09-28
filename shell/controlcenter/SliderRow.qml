import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Một dòng: icon (bấm được), thanh trượt, phần trăm, mũi tên sang trang
// chi tiết (tuỳ chọn).
RowLayout {
    id: root

    property string glyph
    property real value
    property bool dimmed: false
    property bool hasPage: false

    signal glyphClicked
    signal moved(real value)
    signal opened

    Layout.fillWidth: true
    spacing: 8

    HoverButton {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        onClicked: root.glyphClicked()

        Glyph {
            anchors.centerIn: parent
            text: root.glyph
            size: 18
            opacity: root.dimmed ? 0.6 : 1
        }
    }

    GlassSlider {
        Layout.fillWidth: true
        value: root.value
        dimmed: root.dimmed
        onMoved: v => root.moved(v)
    }

    Label {
        Layout.preferredWidth: 30
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100)
        opacity: root.dimmed ? 0.6 : 1
    }

    HoverButton {
        visible: root.hasPage
        Layout.preferredWidth: 24
        Layout.preferredHeight: 30
        onClicked: root.opened()

        Glyph {
            anchors.centerIn: parent
            text: Icons.forward
        }
    }
}
