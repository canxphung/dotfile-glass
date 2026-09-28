import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.services
import qs.components

// Khay hệ thống (StatusNotifierItem): fcitx5, Discord, Steam...
Row {
    id: root

    required property var window

    spacing: 1

    Repeater {
        model: SystemTray.items

        HoverButton {
            id: item

            required property SystemTrayItem modelData

            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 32
            highlighted: modelData.status === Status.NeedsAttention
            glow: modelData.status === Status.NeedsAttention ? Theme.warning : Theme.accentBright

            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !modelData.onlyMenu)
                    modelData.activate();
                else if (mouse.button === Qt.MiddleButton)
                    modelData.secondaryActivate();
                else if (modelData.hasMenu)
                    menu.open();
            }
            onWheel: wheel => modelData.scroll(wheel.angleDelta.y, false)

            // Icon theo tên trong icon theme ("image://icon/tên"): theme không
            // có thì Qt vẽ ô caro, nên hiện icon chữ thay vào.
            readonly property string themeIcon: modelData.icon.startsWith("image://icon/") ? modelData.icon.slice(13).split("?")[0] : ""
            readonly property bool missing: themeIcon !== "" && !Quickshell.hasThemeIcon(themeIcon)

            IconImage {
                anchors.centerIn: parent
                visible: !item.missing
                implicitSize: 18
                source: item.missing ? "" : item.modelData.icon
                asynchronous: true
            }

            Glyph {
                anchors.centerIn: parent
                visible: item.missing
                text: "\u{f08c6}"
                size: 16
            }

            QsMenuAnchor {
                id: menu
                menu: item.modelData.menu
                anchor.window: root.window
                anchor.item: item
                anchor.edges: Edges.Top
                anchor.gravity: Edges.Top
            }
        }
    }
}
