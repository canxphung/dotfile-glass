import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Popup thông báo ở góc dưới phải, ngay trên khay hệ thống; mới nhất ở dưới.
PanelWindow {
    id: root

    visible: Notifs.popups.length > 0 && !Overlays.powerMenu
    screen: Overlays.activeScreen
    anchors.right: true
    anchors.bottom: true
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: column.implicitHeight + 16
    color: "transparent"
    // Chỉ nhận chuột trên các thẻ, chỗ trống thì bấm xuyên qua.
    mask: Region {
        item: column
    }

    WlrLayershell.namespace: "glass-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    Column {
        id: column
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        spacing: 8

        Repeater {
            model: ScriptModel {
                values: [...Notifs.popups].reverse()
            }

            NotificationCard {}
        }
    }
}
