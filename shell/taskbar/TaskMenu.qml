import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Danh sách cửa sổ và thao tác của một app, hiện phía trên nút taskbar.
GlassPopup {
    id: root

    window: button.window
    implicitWidth: 300
    frameHeight: content.implicitHeight + 12

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 6
        spacing: 1

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.bottomMargin: 2
            text: root.button.entry?.name ?? root.button.modelData.key
            color: Theme.textMuted
        }

        Repeater {
            model: root.button.windows

            MenuRow {
                required property var modelData

                Layout.fillWidth: true
                glyph: modelData.activated ? "\u{f0142}" : ""
                text: modelData.title || modelData.appId
                closable: true
                onTriggered: {
                    modelData.activate();
                    root.visible = false;
                }
                onCloseRequested: modelData.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 3
            implicitHeight: 1
            visible: root.button.running
            color: Qt.alpha(Theme.highlight, 0.18)
        }

        MenuRow {
            Layout.fillWidth: true
            visible: root.button.entry !== null
            glyph: "\u{f0415}"
            text: root.button.running ? "Mở cửa sổ mới" : "Mở"
            onTriggered: {
                Apps.launch(root.button.entry);
                root.visible = false;
            }
        }

        MenuRow {
            readonly property bool pinned: root.button.entry ? Apps.isPinned(root.button.entry.id) : false

            Layout.fillWidth: true
            visible: root.button.entry !== null
            glyph: pinned ? "\u{f0404}" : "\u{f0403}"
            text: pinned ? "Bỏ ghim khỏi taskbar" : "Ghim vào taskbar"
            onTriggered: {
                Apps.togglePin(root.button.entry.id);
                root.visible = false;
            }
        }

        MenuRow {
            Layout.fillWidth: true
            visible: root.button.running
            glyph: "\u{f0156}"
            text: root.button.windows.length > 1 ? "Đóng tất cả cửa sổ" : "Đóng cửa sổ"
            onTriggered: {
                for (const w of root.button.windows)
                    w.close();
                root.visible = false;
            }
        }
    }
}
