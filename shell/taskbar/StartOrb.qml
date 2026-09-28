import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.services
import qs.components

// Nút Start: quả cầu kính, bấm để mở start menu.
Item {
    id: root

    required property ShellScreen screen
    readonly property bool open: Overlays.startMenu && Overlays.screen === screen

    implicitWidth: 52

    Item {
        id: orb
        anchors.centerIn: parent
        width: 34
        height: 34
        scale: mouse.pressed ? 0.94 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 80
            }
        }

        // Quầng sáng khi rê chuột hoặc menu đang mở.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8
            height: width
            radius: width / 2
            color: Qt.alpha(Theme.accentBright, mouse.containsMouse || root.open ? 0.35 : 0)

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(Theme.edge, 0.95)
                strokeWidth: 1
                fillGradient: RadialGradient {
                    centerX: orb.width / 2
                    centerY: orb.height * 0.78
                    centerRadius: orb.width * 0.62
                    focalX: centerX
                    focalY: centerY

                    GradientStop {
                        position: 0
                        color: mouse.containsMouse || root.open ? Theme.tintLight : Theme.accentBright
                    }
                    GradientStop {
                        position: 0.55
                        color: Theme.accent
                    }
                    GradientStop {
                        position: 1
                        color: Theme.tintDeep
                    }
                }

                PathAngleArc {
                    centerX: orb.width / 2
                    centerY: orb.height / 2
                    radiusX: orb.width / 2 - 0.5
                    radiusY: orb.height / 2 - 0.5
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        // Vệt bóng nửa trên.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 2
            width: parent.width * 0.78
            height: parent.height * 0.46
            radius: height / 2
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Theme.highlight, 0.7)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Theme.highlight, 0.08)
                }
            }
        }

        Glyph {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1
            text: "\u{f0ae2}"
            size: 18
            color: "white"
            style: Text.Outline
            styleColor: Qt.alpha(Theme.edge, 0.4)
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Overlays.toggleStartMenu(root.screen)
    }
}
