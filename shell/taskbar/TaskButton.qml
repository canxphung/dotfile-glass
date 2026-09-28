import QtQuick
import Quickshell
import qs.services
import qs.components

// Một app trên taskbar.
//   Chuột trái: chưa chạy thì mở; một cửa sổ thì đưa lên; nhiều cửa sổ thì
//               hiện danh sách để chọn.
//   Chuột giữa: mở thêm cửa sổ mới.
//   Chuột phải: danh sách cửa sổ, ghim/bỏ ghim, đóng.
HoverButton {
    id: root

    required property var modelData
    required property var window

    readonly property var entry: modelData.entry
    readonly property var windows: modelData.windows
    readonly property bool running: windows.length > 0

    implicitWidth: 50
    active: running
    highlighted: windows.some(w => w.activated) || menu.visible

    // Nhiều cửa sổ: thêm một khung chồng phía sau như Windows 7.
    Rectangle {
        z: -1
        visible: root.windows.length > 1
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: -3
        radius: root.radius
        color: "transparent"
        border.color: Qt.alpha(Theme.highlight, 0.28)
    }

    AppIcon {
        anchors.centerIn: parent
        icon: root.entry?.icon ?? root.modelData.key
        size: 26
        opacity: root.running ? 1 : 0.85
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && windows.length > 1)) {
            menu.toggle();
        } else if (mouse.button === Qt.MiddleButton || !running) {
            if (entry)
                Apps.launch(entry);
        } else {
            windows[0].activate();
        }
    }

    TaskMenu {
        id: menu
        button: root
    }
}
