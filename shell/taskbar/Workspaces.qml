import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components

// Workspace của Hyprland trên màn hình này. Bấm để chuyển, lăn chuột để
// sang workspace kế bên.
Item {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)

    implicitWidth: row.implicitWidth + 8

    function goTo(workspace: string): void {
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ workspace = "${workspace}" })` : `workspace ${workspace}`);
    }

    MouseArea {
        anchors.fill: parent
        onWheel: wheel => root.goTo(wheel.angleDelta.y < 0 ? "e+1" : "e-1")
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 3

        Repeater {
            model: ScriptModel {
                values: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === root.monitor)
            }

            HoverButton {
                required property HyprlandWorkspace modelData

                width: Math.max(24, name.implicitWidth + 12)
                height: 24
                highlighted: modelData.active
                active: true
                glow: modelData.urgent ? Theme.warning : Theme.accentBright
                onClicked: modelData.activate()

                Label {
                    id: name
                    anchors.centerIn: parent
                    text: parent.modelData.name
                    font.bold: parent.modelData.active
                    opacity: parent.modelData.active ? 1 : 0.75
                }
            }
        }
    }
}
