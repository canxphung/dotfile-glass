import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import qs.services
import qs.components

// Hộp thoại glassd cần hỏi người dùng: mật khẩu Wi-Fi (agent của
// NetworkManager), xác nhận/nhập mã ghép nối Bluetooth (agent của BlueZ).
// Phủ mờ màn hình như hộp thoại UAC; nhiều yêu cầu thì hiện lần lượt.
PanelWindow {
    id: root

    readonly property var prompt: Glassd.prompts.length > 0 ? Glassd.prompts[0] : null
    readonly property bool isWifi: prompt?.kind === "wifi_secrets"
    readonly property string action: prompt?.action ?? ""
    // Hộp thoại chỉ để xem (hiện mã): không có nút trả lời.
    readonly property bool displayOnly: prompt !== null && !prompt.wait
    readonly property bool needsText: isWifi || action === "pin" || action === "passkey"
    // Thiết bị Bluetooth đang hỏi.
    readonly property var device: prompt && !isWifi ? Bluetooth.devices.values.find(d => d.dbusPath === prompt.device) ?? null : null

    visible: prompt !== null
    screen: Overlays.activeScreen
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: Qt.alpha(Theme.shadow, 0.45)

    WlrLayershell.namespace: "glass-prompt"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function title(): string {
        if (!prompt)
            return "";
        if (isWifi)
            return prompt.security === "enterprise" ? "Đăng nhập mạng Wi-Fi" : "Nhập mật khẩu Wi-Fi";
        switch (action) {
        case "authorize_service":
            return "Cho phép thiết bị Bluetooth";
        case "display_pin":
        case "display_passkey":
            return "Nhập mã trên thiết bị";
        default:
            return "Ghép nối Bluetooth";
        }
    }

    function message(): string {
        if (!prompt)
            return "";
        const name = "“" + (isWifi ? prompt.ssid : prompt.name) + "”";
        if (isWifi) {
            if (prompt.retry)
                return "Mật khẩu của mạng " + name + " không đúng. Nhập lại:";
            return prompt.security === "enterprise" ? "Mạng " + name + " cần tên đăng nhập và mật khẩu." : "Mạng " + name + " cần mật khẩu.";
        }
        switch (action) {
        case "confirm":
            return "Kiểm tra mã dưới đây có giống mã hiện trên " + name + " không.";
        case "authorize":
            return name + " muốn ghép nối với máy này.";
        case "authorize_service":
            return name + " muốn dùng " + (prompt.service ?? "một dịch vụ") + ".";
        case "pin":
            return "Nhập mã PIN của " + name + " (thường là 0000 hoặc 1234).";
        case "passkey":
            return "Nhập mã số hiện trên " + name + ".";
        default:
            return "Gõ mã dưới đây trên " + name + " rồi nhấn Enter.";
        }
    }

    function accept(): void {
        if (!prompt)
            return;
        if (isWifi) {
            const value = {};
            for (const field of prompt.fields)
                value[field] = field === "identity" ? identity.text : secret.text;
            if (Object.values(value).some(v => v === ""))
                return;
            Glassd.reply(prompt.id, value);
        } else if (action === "pin" || action === "passkey") {
            if (secret.text === "")
                return;
            Glassd.reply(prompt.id, { value: secret.text });
        } else {
            Glassd.reply(prompt.id, { accept: "true" });
        }
    }

    function reject(): void {
        if (!prompt)
            return;
        // Đang hiện mã: huỷ cả việc ghép nối.
        if (displayOnly && device?.pairing)
            device.cancelPair();
        Glassd.cancel(prompt.id);
    }

    // Hiện mã xong BlueZ không báo lại agent: tự đóng khi thiết bị đã ghép
    // nối, hoặc lệnh ghép nối từ máy này kết thúc (thành công hay không).
    Connections {
        target: root.displayOnly ? root.device : null

        function onPairedChanged() {
            if (root.device.paired)
                Glassd.cancel(root.prompt.id);
        }

        function onPairingChanged() {
            if (!root.device.pairing)
                Glassd.cancel(root.prompt.id);
        }
    }

    function focusFirst(): void {
        if (!prompt)
            return;
        if (isWifi && prompt.fields.includes("identity"))
            identity.focusInput();
        else if (needsText)
            secret.focusInput();
        else
            keys.forceActiveFocus();
    }

    // Đặt focus sau khi các ô đã hiện theo yêu cầu mới: ô còn ẩn thì không
    // nhận focus.
    onPromptChanged: {
        identity.text = "";
        secret.text = "";
        secret.reveal = false;
        if (prompt)
            Qt.callLater(focusFirst);
    }

    // Hiện ra: mờ dần vào và phóng nhẹ, như hộp thoại Windows 7.
    onVisibleChanged: if (visible)
        appear.restart()

    MouseArea {
        anchors.fill: parent
    }

    GlassRect {
        id: box

        anchors.centerIn: parent
        width: 420
        height: layout.implicitHeight + 36
        fill: 0.85

        ParallelAnimation {
            id: appear
            NumberAnimation {
                target: box
                property: "opacity"
                from: 0
                to: 1
                duration: 140
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: box
                property: "scale"
                from: 0.94
                to: 1
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.reject()
            Keys.onReturnPressed: root.accept()
            Keys.onEnterPressed: root.accept()

            ColumnLayout {
                id: layout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Glyph {
                        text: root.isWifi ? Icons.wifiStrength[3] : Icons.bluetooth
                        size: 34
                        color: Theme.tintLight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.title()
                        font.pointSize: Theme.fontSize * 1.4
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.message()
                    wrapMode: Text.Wrap
                }

                // Mã để so hoặc để gõ trên thiết bị.
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    visible: (root.prompt?.code ?? "") !== ""
                    text: (root.prompt?.code ?? "").replace(/(\d{3})(\d{3})/, "$1 $2")
                    font.family: Theme.monoFamily
                    font.pointSize: Theme.fontSize * 2.4
                    font.bold: true
                    color: Theme.accentBright
                }

                GlassField {
                    id: identity
                    Layout.fillWidth: true
                    visible: root.isWifi && (root.prompt?.fields ?? []).includes("identity")
                    placeholder: "Tên đăng nhập"
                    onAccepted: secret.focusInput()
                }

                GlassField {
                    id: secret
                    Layout.fillWidth: true
                    visible: root.needsText
                    secret: root.isWifi
                    placeholder: root.isWifi ? "Mật khẩu" : "Mã"
                    onAccepted: root.accept()
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    DialogButton {
                        text: root.displayOnly ? "Huỷ ghép nối" : root.isWifi || root.needsText ? "Huỷ" : "Từ chối"
                        onClicked: root.reject()
                    }

                    DialogButton {
                        visible: !root.displayOnly
                        primary: true
                        text: root.isWifi ? "Kết nối" : root.action === "authorize_service" ? "Cho phép" : "Ghép nối"
                        onClicked: root.accept()
                    }
                }
            }
        }
    }

    component DialogButton: HoverButton {
        id: button

        property string text
        property bool primary: false

        Layout.preferredWidth: Math.max(96, label.implicitWidth + 28)
        Layout.preferredHeight: 32
        active: true
        highlighted: primary

        Label {
            id: label
            anchors.centerIn: parent
            text: button.text
            font.bold: button.primary
        }
    }
}
