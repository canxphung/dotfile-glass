import QtQuick
import qs.services

// Chữ theo font giao diện người dùng chọn (appearance.font).
Text {
    font.family: Theme.fontFamily
    font.pointSize: Theme.fontSize
    color: Theme.textOnGlass
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
