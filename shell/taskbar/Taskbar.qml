import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Thanh taskbar ở đáy mỗi màn hình.
PanelWindow {
    id: bar

    required property ShellScreen modelData

    screen: modelData
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    color: "transparent"

    WlrLayershell.namespace: "glass-taskbar"
    WlrLayershell.layer: WlrLayer.Top

    GlassRect {
        anchors.fill: parent
        radius: 0
        fill: 0.62
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        spacing: 2

        StartOrb {
            Layout.fillHeight: true
            screen: bar.screen
        }

        TaskList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            window: bar
        }

        Loader {
            Layout.fillHeight: true
            active: Overlays.hyprland
            visible: active
            sourceComponent: Workspaces {
                screen: bar.screen
            }
        }

        Tray {
            Layout.fillHeight: true
            window: bar
        }

        Indicators {
            Layout.fillHeight: true
            screen: bar.screen
        }

        Clock {
            Layout.fillHeight: true
            window: bar
        }
    }
}
