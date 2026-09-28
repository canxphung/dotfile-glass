pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// Mạng qua NetworkManager: thiết bị Wi-Fi/dây, danh sách mạng, icon cho
// taskbar. Mật khẩu Wi-Fi do agent trong glassd hỏi (hộp thoại
// PromptDialog); không có glassd thì trang Wi-Fi tự hỏi (connectWithPsk).
Singleton {
    id: root

    readonly property bool available: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var devices: Networking.devices.values
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired) ?? null

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wiredConnected: wired?.connected ?? false

    // Mạng Wi-Fi: đang nối trước, rồi mạng đã lưu, rồi theo sóng mạnh.
    readonly property var networks: wifi ? [...wifi.networks.values].sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength)) : []
    readonly property var activeWifi: networks.find(n => n.connected) ?? null

    // Trang Wi-Fi đang mở thì quét liên tục.
    property bool scanning: false

    Binding {
        target: root.wifi
        property: "scannerEnabled"
        value: root.scanning
        when: root.wifi !== null
    }

    function setWifiEnabled(on: bool): void {
        Networking.wifiEnabled = on;
    }

    // Hồ sơ đã lưu không có phần bảo mật (mạng mở) được Quickshell báo là
    // Unknown, nên coi Unknown là mở.
    function secured(network: var): bool {
        return ![WifiSecurityType.Open, WifiSecurityType.Owe, WifiSecurityType.Unknown].includes(network.security);
    }

    function strengthGlyph(strength: real): string {
        return Icons.wifiStrength[Math.max(0, Math.min(3, Math.floor(strength * 4)))];
    }

    // Icon trên taskbar.
    function glyph(): string {
        if (!available)
            return Icons.ethernetOff;
        if (wiredConnected)
            return Icons.ethernet;
        if (activeWifi) {
            const limited = Networking.connectivity === NetworkConnectivity.Limited || Networking.connectivity === NetworkConnectivity.Portal;
            return limited ? Icons.wifiLimited : strengthGlyph(activeWifi.signalStrength);
        }
        return wifiEnabled ? Icons.wifiOff : Icons.wifiDisabled;
    }

    function summary(): string {
        if (!available)
            return "Không khả dụng";
        if (wiredConnected)
            return "Mạng dây";
        if (activeWifi)
            return activeWifi.name;
        return wifiEnabled ? "Chưa kết nối" : "Wi-Fi đang tắt";
    }

    function stateText(network: var): string {
        switch (network.state) {
        case ConnectionState.Connected:
            return "Đã kết nối";
        case ConnectionState.Connecting:
            return "Đang kết nối…";
        case ConnectionState.Disconnecting:
            return "Đang ngắt…";
        default:
            return network.known ? "Đã lưu" : secured(network) ? "Có mật khẩu" : "Mạng mở";
        }
    }
}
