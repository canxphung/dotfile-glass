pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth qua BlueZ. Ghép nối cần xác nhận mã thì agent trong glassd hỏi
// (hộp thoại PromptDialog).
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var devices: adapter ? [...adapter.devices.values] : []
    readonly property var paired: devices.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var nearby: devices.filter(d => !d.paired && d.name !== "")
    readonly property var connected: devices.filter(d => d.connected)

    // Trang Bluetooth đang mở và muốn tìm thiết bị mới.
    property bool discovering: false

    Binding {
        target: root.adapter
        property: "discovering"
        value: root.discovering && root.enabled
        when: root.adapter !== null
    }

    function setEnabled(on: bool): void {
        if (adapter)
            adapter.enabled = on;
    }

    // Ghép nối xong thì tin cậy và kết nối luôn, như bấm "Kết nối" trên
    // Windows.
    function pairAndConnect(device: var): void {
        pending = [...pending.filter(d => d !== device), device];
        device.pair();
    }

    property var pending: []

    Instantiator {
        model: root.pending

        delegate: Connections {
            required property var modelData

            target: modelData

            function onPairedChanged() {
                if (!modelData.paired)
                    return;
                modelData.trusted = true;
                modelData.connect();
                root.pending = root.pending.filter(d => d !== modelData);
            }

            function onPairingChanged() {
                // Ghép nối thất bại hoặc bị huỷ.
                if (!modelData.pairing && !modelData.paired)
                    root.pending = root.pending.filter(d => d !== modelData);
            }
        }
    }

    function glyph(): string {
        if (!enabled)
            return Icons.bluetoothOff;
        return connected.length > 0 ? Icons.bluetoothConnected : Icons.bluetooth;
    }

    function summary(): string {
        if (!available)
            return "Không có Bluetooth";
        if (!enabled)
            return "Đang tắt";
        if (connected.length === 1)
            return connected[0].name;
        if (connected.length > 1)
            return connected.length + " thiết bị";
        return "Chưa kết nối";
    }

    function stateText(device: var): string {
        if (device.pairing)
            return "Đang ghép nối…";
        switch (device.state) {
        case BluetoothDeviceState.Connected:
            return device.batteryAvailable ? "Đã kết nối · pin " + Math.round(device.battery * 100) + "%" : "Đã kết nối";
        case BluetoothDeviceState.Connecting:
            return "Đang kết nối…";
        case BluetoothDeviceState.Disconnecting:
            return "Đang ngắt…";
        default:
            return device.paired ? "Đã ghép nối" : "Chưa ghép nối";
        }
    }
}
