import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Trang Bluetooth: bật/tắt, thiết bị đã ghép nối, tìm thiết bị mới.
ColumnLayout {
    id: root

    signal back

    property var selected: null

    spacing: 8

    Component.onCompleted: Bt.discovering = true
    Component.onDestruction: Bt.discovering = false

    PageHeader {
        Layout.fillWidth: true
        title: "Bluetooth"
        hasSwitch: Bt.available
        checked: Bt.enabled
        onBack: root.back()
        onToggled: on => Bt.setEnabled(on)
    }

    Label {
        Layout.fillWidth: true
        visible: !Bt.available
        text: "Không thấy bộ Bluetooth (hoặc bluetooth.service chưa chạy)."
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    SectionLabel {
        visible: Bt.enabled
        text: Bt.paired.length > 0 ? "Thiết bị của bạn" : "Chưa ghép nối thiết bị nào"
    }

    Repeater {
        model: ScriptModel {
            values: Bt.enabled ? Bt.paired : []
        }

        BluetoothRow {
            Layout.fillWidth: true
            expanded: root.selected === modelData
            onClicked: root.selected = expanded ? null : modelData
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: Bt.enabled

        SectionLabel {
            text: "Thiết bị gần đây"
        }

        Label {
            visible: Bt.adapter?.discovering ?? false
            text: "đang tìm…"
            color: Theme.textMuted
            font.pointSize: Theme.fontSize * 0.85
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 240)
        visible: Bt.enabled && count > 0
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: Bt.nearby
        }

        delegate: BluetoothRow {
            width: ListView.view.width
            expanded: root.selected === modelData
            onClicked: root.selected = expanded ? null : modelData
        }
    }
}
