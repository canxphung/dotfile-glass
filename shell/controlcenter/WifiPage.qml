import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.services
import qs.components

// Trang Wi-Fi: bật/tắt, mạng dây, danh sách mạng. Bấm một mạng để hiện
// nút kết nối / ngắt / quên.
ColumnLayout {
    id: root

    signal back

    // Mạng đang mở rộng (hiện nút).
    property var selected: null

    spacing: 8

    Component.onCompleted: Net.scanning = true
    Component.onDestruction: Net.scanning = false

    PageHeader {
        Layout.fillWidth: true
        title: "Wi-Fi"
        hasSwitch: Net.available && Net.wifi !== null
        checked: Net.wifiEnabled
        onBack: root.back()
        onToggled: on => Net.setWifiEnabled(on)
    }

    Label {
        Layout.fillWidth: true
        visible: !Net.available
        text: "NetworkManager không chạy (sudo systemctl enable --now NetworkManager)."
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    RowLayout {
        Layout.fillWidth: true
        visible: Net.wired !== null
        spacing: 8

        Glyph {
            Layout.preferredWidth: 24
            text: Net.wiredConnected ? Icons.ethernet : Icons.ethernetOff
            size: 18
        }

        Label {
            Layout.fillWidth: true
            text: "Mạng dây: " + (Net.wiredConnected ? "đã kết nối" : "chưa cắm")
        }
    }

    Label {
        Layout.fillWidth: true
        visible: Net.available && Net.wifi === null
        text: "Không có thiết bị Wi-Fi."
        opacity: 0.8
    }

    Label {
        Layout.fillWidth: true
        visible: Net.wifi !== null && Net.wifiEnabled && Net.networks.length === 0
        text: "Đang tìm mạng…"
        opacity: 0.8
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 380)
        visible: Net.wifiEnabled && count > 0
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: Net.networks
        }

        delegate: WifiRow {
            width: ListView.view.width
            expanded: root.selected === modelData
            onClicked: root.selected = expanded ? null : modelData
        }
    }
}
