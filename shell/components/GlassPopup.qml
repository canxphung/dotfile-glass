import QtQuick
import Quickshell

// Popup kính bật lên phía trên một nút trên taskbar; bấm ra ngoài là đóng.
//
// Cửa sổ popup có kích thước cố định (implicitWidth/implicitHeight là cỡ
// tối đa), phần kính bên trong co giãn theo nội dung, phần thừa trong suốt
// và bấm xuyên qua. Đổi kích thước một popup đang mở khiến vài compositor
// đóng nó luôn, nên tránh hẳn.
//
// Vì lý do tương tự, popup neo theo toạ độ của nút tính lúc mở chứ không
// dùng anchor.item (Quickshell đặt lại vị trí ngay sau khi hiện).
PopupWindow {
    id: root

    required property var window
    required property Item button
    // Chiều cao phần kính, thường là implicitHeight của nội dung + lề.
    property real frameHeight: 100
    property bool alignRight: false
    default property alias content: frame.data

    function open(): void {
        const p = window.itemPosition(button);
        anchor.rect.x = p.x;
        anchor.rect.y = p.y - 4;
        anchor.rect.width = button.width;
        anchor.rect.height = button.height;
        visible = true;
    }

    function toggle(): void {
        if (visible)
            visible = false;
        else
            open();
    }

    anchor.window: window
    anchor.edges: alignRight ? Edges.Top | Edges.Right : Edges.Top
    anchor.gravity: alignRight ? Edges.Top | Edges.Left : Edges.Top
    grabFocus: true
    color: "transparent"
    implicitWidth: 300
    implicitHeight: 480
    mask: Region {
        item: frame
    }

    GlassRect {
        id: frame
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(root.frameHeight, parent.height)
        fill: 0.8
    }
}
