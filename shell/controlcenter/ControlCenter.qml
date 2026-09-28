import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Control center: công tắc nhanh, âm lượng, độ sáng, pin, thông báo, và các
// trang Wi-Fi, Bluetooth, âm thanh. Hiện ở góc dưới phải, trên khay hệ
// thống; bấm ra ngoài hoặc Esc là đóng.
PanelWindow {
    id: root

    visible: Overlays.controlCenter
    screen: Overlays.screen
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "glass-controlcenter"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: visible && !Glassd.prompting ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close(): void {
        Overlays.controlCenter = false;
    }

    function back(): void {
        if (Overlays.page === "main")
            close();
        else
            Overlays.page = "main";
    }

    onVisibleChanged: {
        if (visible) {
            Brightness.refresh(false);
            keys.forceActiveFocus();
            appear.restart();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    GlassRect {
        id: panel

        anchors.right: parent.right
        anchors.rightMargin: 6
        y: parent.height - Theme.barHeight - height - 6
        width: 380
        height: Math.min(pages.implicitHeight + 24, parent.height - Theme.barHeight - 24)
        fill: 0.78
        clip: true

        transform: Translate {
            id: slide
        }

        ParallelAnimation {
            id: appear
            NumberAnimation {
                target: panel
                property: "opacity"
                from: 0
                to: 1
                duration: 140
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: slide
                property: "y"
                from: 16
                to: 0
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        // Chặn click trong bảng khỏi lọt xuống lớp phủ.
        MouseArea {
            anchors.fill: parent
        }

        FocusScope {
            id: keys
            anchors.fill: parent
            anchors.margins: 12
            focus: true

            Keys.onEscapePressed: root.back()

            Loader {
                id: pages
                width: parent.width
                height: parent.height
                sourceComponent: {
                    switch (Overlays.page) {
                    case "wifi":
                        return wifiPage;
                    case "bluetooth":
                        return bluetoothPage;
                    case "audio":
                        return audioPage;
                    default:
                        return mainPage;
                    }
                }
            }
        }
    }

    Component {
        id: mainPage
        MainPage {}
    }

    Component {
        id: wifiPage
        WifiPage {
            onBack: root.back()
        }
    }

    Component {
        id: bluetoothPage
        BluetoothPage {
            onBack: root.back()
        }
    }

    Component {
        id: audioPage
        AudioPage {
            onBack: root.back()
        }
    }
}
