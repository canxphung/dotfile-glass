import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Màn hình chọn khoá / đăng xuất / ngủ / khởi động lại / tắt máy, phủ
// toàn màn hình như màn hình Ctrl+Alt+Del của Windows 7. Hyprland blur
// phần phía sau lớp phủ tối.
PanelWindow {
    id: root

    readonly property var actions: [
        { id: "lock", glyph: "\u{f033e}", text: "Khoá máy" },
        { id: "logout", glyph: "\u{f0343}", text: "Đăng xuất" },
        { id: "suspend", glyph: "\u{f04b2}", text: "Ngủ" },
        { id: "reboot", glyph: "\u{f0709}", text: "Khởi động lại" },
        { id: "poweroff", glyph: "\u{f0425}", text: "Tắt máy" }
    ]
    property int current: 0

    function close(): void {
        Overlays.powerMenu = false;
    }

    function trigger(index: int): void {
        close();
        Glass.session(actions[index].id);
    }

    visible: Overlays.powerMenu
    screen: Overlays.screen
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: Qt.alpha(Theme.shadow, 0.55)

    WlrLayershell.namespace: "glass-powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible) {
            current = 0;
            keys.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                root.close();
                break;
            case Qt.Key_Down:
            case Qt.Key_Tab:
                root.current = (root.current + 1) % root.actions.length;
                break;
            case Qt.Key_Up:
            case Qt.Key_Backtab:
                root.current = (root.current + root.actions.length - 1) % root.actions.length;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.trigger(root.current);
                break;
            default:
                return;
            }
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 6

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 18
            text: Glass.user
            font.pointSize: Theme.fontSize * 2
            font.weight: Font.Light
            style: Text.Raised
            styleColor: Qt.alpha(Theme.shadow, 0.8)
        }

        Repeater {
            model: root.actions

            HoverButton {
                required property var modelData
                required property int index

                Layout.preferredWidth: 300
                Layout.preferredHeight: 48
                highlighted: root.current === index
                glow: modelData.id === "poweroff" || modelData.id === "reboot" ? Theme.danger : Theme.accentBright
                onClicked: root.trigger(index)
                onHoveredChanged: {
                    if (hovered)
                        root.current = index;
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    spacing: 16

                    Glyph {
                        Layout.preferredWidth: 28
                        text: parent.parent.modelData.glyph
                        size: 24
                    }

                    Label {
                        Layout.fillWidth: true
                        text: parent.parent.modelData.text
                        font.pointSize: Theme.fontSize * 1.3
                    }
                }
            }
        }

        HoverButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 18
            Layout.preferredWidth: 120
            Layout.preferredHeight: 34
            active: true
            onClicked: root.close()

            Label {
                anchors.centerIn: parent
                text: "Huỷ"
            }
        }
    }
}
