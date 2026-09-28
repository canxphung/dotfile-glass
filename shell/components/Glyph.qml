import QtQuick
import qs.services

// Icon dạng chữ (Material Design trong Symbols Nerd Font).
Text {
    property real size: 16

    font.family: Theme.iconFamily
    font.pixelSize: size
    color: Theme.textOnGlass
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
