import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Start menu kiểu Windows 7.
//
// Phủ cả màn hình bằng một lớp trong suốt để bấm ra ngoài là đóng; phần
// menu nằm góc dưới trái, ngay trên taskbar. Mở là gõ được ngay để tìm.
PanelWindow {
    id: root

    visible: Overlays.startMenu
    screen: Overlays.screen
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "glass-startmenu"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: visible && !Glassd.prompting ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string query: ""
    property bool showAll: false

    readonly property var frequent: Apps.frequent(12)
    // Mới cài, chưa có app hay dùng hay app ghim nào: hiện luôn tất cả.
    readonly property bool listingAll: showAll || frequent.length === 0
    readonly property var entries: query !== "" ? Apps.search(query) : listingAll ? Apps.all : frequent

    function close(): void {
        Overlays.startMenu = false;
    }

    function launch(entry: var): void {
        Apps.launch(entry);
        close();
    }

    function open(path: string): void {
        Glass.openPath(path);
        close();
    }

    onVisibleChanged: {
        if (!visible)
            return;
        search.text = "";
        showAll = false;
        list.currentIndex = 0;
        search.forceActiveFocus();
        appear.restart();
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    GlassRect {
        id: menu

        x: 2
        y: parent.height - Theme.barHeight - height - 2
        width: 560
        height: Math.min(540, parent.height - Theme.barHeight - 12)
        fill: 0.72

        // Chặn click trong menu khỏi lọt xuống lớp phủ.
        MouseArea {
            anchors.fill: parent
        }

        ParallelAnimation {
            id: appear
            NumberAnimation {
                target: menu
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

        transform: Translate {
            id: slide
        }

        // Cột trái: danh sách app trên nền sáng/tối, ô tìm ở dưới.
        Rectangle {
            id: pane
            x: 8
            y: 8
            width: 340
            height: parent.height - 8 - 48
            radius: 4
            color: Qt.alpha(Theme.surface, 0.94)
            border.color: Qt.alpha(Theme.edge, 0.6)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 2

                ListView {
                    id: list

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.entries
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    keyNavigationWraps: true

                    delegate: AppRow {
                        required property var modelData
                        required property int index

                        width: ListView.view.width
                        entry: modelData
                        compact: root.listingAll && root.query === ""
                        selected: ListView.isCurrentItem
                        onActivated: root.launch(modelData)
                        onHoveredChanged: {
                            if (hovered)
                                list.currentIndex = index;
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: root.query !== "" ? "Không tìm thấy ứng dụng nào" : "Chưa có ứng dụng"
                        color: Theme.textOnSurface
                        opacity: 0.6
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    implicitHeight: 1
                    visible: root.query === "" && root.frequent.length > 0
                    color: Qt.alpha(Theme.textOnSurface, 0.15)
                }

                // "Tất cả ứng dụng" / "Quay lại"
                AppRow {
                    Layout.fillWidth: true
                    visible: root.query === "" && root.frequent.length > 0
                    compact: true
                    glyph: root.showAll ? "\u{f0141}" : "\u{f0142}"
                    title: root.showAll ? "Quay lại" : "Tất cả ứng dụng"
                    onActivated: {
                        root.showAll = !root.showAll;
                        list.currentIndex = 0;
                        search.forceActiveFocus();
                    }
                }
            }
        }

        // Ô tìm.
        Rectangle {
            x: pane.x
            y: pane.y + pane.height + 10
            width: pane.width
            height: 30
            radius: 3
            color: Qt.alpha(Theme.surface, 0.95)
            border.color: search.activeFocus ? Theme.accent : Qt.alpha(Theme.edge, 0.6)

            TextInput {
                id: search

                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 32
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pointSize: Theme.fontSize
                color: Theme.textOnSurface
                selectionColor: Theme.selection
                clip: true
                onTextChanged: {
                    root.query = text;
                    list.currentIndex = 0;
                }

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.close();
                        break;
                    case Qt.Key_Down:
                        list.incrementCurrentIndex();
                        break;
                    case Qt.Key_Up:
                        list.decrementCurrentIndex();
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (list.currentIndex >= 0 && list.count > 0)
                            root.launch(root.entries[list.currentIndex]);
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text === ""
                    text: "Tìm ứng dụng"
                    color: Theme.textOnSurface
                    opacity: 0.5
                    font.italic: true
                }
            }

            Glyph {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: Theme.textOnSurface
                opacity: 0.6
            }
        }

        // Cột phải: người dùng, thư mục, cài đặt, nguồn.
        ColumnLayout {
            x: pane.x + pane.width + 8
            y: 14
            width: parent.width - x - 8
            height: parent.height - 14 - 8
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                spacing: 8

                Glyph {
                    text: "\u{f0009}"
                    size: 40
                    color: Theme.tintLight
                }

                Label {
                    Layout.fillWidth: true
                    text: Glass.user
                    font.pointSize: Theme.fontSize * 1.25
                    font.bold: true
                    style: Text.Raised
                    styleColor: Qt.alpha(Theme.shadow, 0.6)
                }
            }

            Place {
                glyph: "\u{f10b5}"
                text: Glass.user
                onTriggered: root.open(Glass.home)
            }
            Place {
                glyph: "\u{f0219}"
                text: "Tài liệu"
                onTriggered: root.open(UserDirs.documents)
            }
            Place {
                glyph: "\u{f024f}"
                text: "Ảnh"
                onTriggered: root.open(UserDirs.pictures)
            }
            Place {
                glyph: "\u{f1359}"
                text: "Nhạc"
                onTriggered: root.open(UserDirs.music)
            }
            Place {
                glyph: "\u{f024d}"
                text: "Tải về"
                onTriggered: root.open(UserDirs.download)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 6
                implicitHeight: 1
                color: Qt.alpha(Theme.highlight, 0.2)
            }

            Place {
                glyph: "\u{f018d}"
                text: "Terminal"
                onTriggered: {
                    Glass.run(Glass.terminal, [Glass.terminal]);
                    root.close();
                }
            }
            Place {
                glyph: "\u{f0493}"
                text: "Cài đặt"
                onTriggered: root.open(Glass.settingsFile)
            }

            Item {
                Layout.fillHeight: true
            }

            // Nút nguồn hai phần như Windows 7: tắt máy | các lựa chọn khác.
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 0

                HoverButton {
                    implicitWidth: powerLabel.implicitWidth + 44
                    implicitHeight: 30
                    active: true
                    glow: Theme.danger
                    onClicked: {
                        root.close();
                        Glass.session("poweroff");
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Glyph {
                            text: "\u{f0425}"
                        }
                        Label {
                            id: powerLabel
                            text: "Tắt máy"
                        }
                    }
                }

                HoverButton {
                    implicitWidth: 26
                    implicitHeight: 30
                    active: true
                    onClicked: Overlays.openPowerMenu()

                    Glyph {
                        anchors.centerIn: parent
                        text: "\u{f0142}"
                    }
                }
            }
        }
    }

    component Place: MenuRow {
        Layout.fillWidth: true
        implicitHeight: 34
    }
}
