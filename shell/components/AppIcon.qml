import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// Icon của app theo tên trong icon theme, đường dẫn file, hoặc URL ảnh.
// Không tìm được thì hiện icon chung.
Item {
    id: root

    property string icon
    property real size: 24

    readonly property string source: {
        if (icon === "")
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.includes("://"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }

    implicitWidth: size
    implicitHeight: size

    IconImage {
        id: image
        anchors.fill: parent
        source: root.source
        visible: root.source !== "" && status !== Image.Error
        asynchronous: true
        mipmap: true
    }

    Glyph {
        anchors.centerIn: parent
        visible: !image.visible
        text: "\u{f08c6}"
        size: root.size * 0.8
    }
}
