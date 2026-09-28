import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Ô kính nhỏ phía trên taskbar báo âm lượng / độ sáng khi đổi.
PanelWindow {
    id: root

    // "volume" hay "brightness". Mức hiện theo giá trị thật, không chép lúc
    // nhận tín hiệu: volumesChanged của PipeWire tới trước khi volume đổi.
    property string kind: "volume"
    readonly property bool isVolume: kind === "volume"
    readonly property string glyph: isVolume ? Audio.glyph() : Brightness.level >= 0.5 ? "\u{f00df}" : "\u{f00de}"
    readonly property real value: isVolume ? Audio.volume : Brightness.level
    readonly property bool muted: isVolume && Audio.muted
    property bool shown: false
    // Bỏ qua các lần đổi lúc mới khởi động hoặc vừa đổi loa.
    property bool armed: false

    function show(kind: string): void {
        root.kind = kind;
        shown = true;
        hideTimer.restart();
    }

    function showVolume(): void {
        if (Audio.ready)
            show("volume");
    }

    function showBrightness(): void {
        show("brightness");
    }

    visible: shown
    screen: Overlays.activeScreen
    anchors.bottom: true
    margins.bottom: 24
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: 300
    implicitHeight: 52
    color: "transparent"
    mask: Region {}

    WlrLayershell.namespace: "glass-osd"
    WlrLayershell.layer: WlrLayer.Overlay

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.shown = false
    }

    Timer {
        id: armTimer
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    Connections {
        target: Audio

        function onSinkChanged() {
            root.armed = false;
            armTimer.restart();
        }

        function onChanged() {
            // Đang kéo thanh trượt trong control center thì không cần OSD.
            if (root.armed && !Overlays.controlCenter)
                root.showVolume();
        }
    }

    Connections {
        target: Brightness

        function onChanged() {
            if (!Overlays.controlCenter)
                root.showBrightness();
        }
    }

    GlassRect {
        anchors.fill: parent
        radius: height / 2
        fill: 0.78

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 12

            Glyph {
                text: root.glyph
                size: 22
            }

            // Thanh mức: rãnh tối, phần đầy sáng như thanh tiến trình Aero.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: 4
                color: Qt.alpha(Theme.shadow, 0.6)
                border.color: Qt.alpha(Theme.edge, 0.8)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.value))
                    height: parent.height
                    radius: 4
                    opacity: root.muted ? 0.35 : 1
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Theme.accentBright
                        }
                        GradientStop {
                            position: 1
                            color: Theme.accent
                        }
                    }
                }
            }

            Label {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: root.muted ? "Tắt" : Math.round(root.value * 100)
            }
        }
    }
}
