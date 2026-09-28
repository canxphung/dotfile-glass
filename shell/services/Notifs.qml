pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Máy chủ thông báo (org.freedesktop.Notifications).
//
// Mỗi thông báo mới hiện thành popup một lúc rồi ẩn, nhưng vẫn được giữ
// lại (lịch sử cho control center ở giai đoạn 4) cho tới khi người dùng
// đóng, app tự rút lại, hoặc bị đẩy ra khi quá `historyLimit`.
Singleton {
    id: root

    // Không làm phiền: không hiện popup, trừ thông báo khẩn.
    property bool dnd: false
    readonly property int historyLimit: 50
    readonly property int defaultTimeout: 6000

    // Thông báo đang hiện popup, mới nhất trước.
    property var popups: []
    readonly property var history: server.trackedNotifications.values

    function hide(n: Notification): void {
        popups = popups.filter(p => p !== n);
    }

    function dismissAll(): void {
        for (const n of history.slice())
            n.dismiss();
        popups = [];
    }

    // Thời gian hiện popup (ms); 0 là giữ tới khi đóng.
    function timeoutFor(n: Notification): int {
        if (n.urgency === NotificationUrgency.Critical || n.expireTimeout === 0)
            return 0;
        if (n.expireTimeout > 0)
            return Math.max(2000, Math.min(n.expireTimeout, 30000));
        return defaultTimeout;
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            n.closed.connect(() => root.hide(n));

            // Lúc này thông báo mới chưa vào danh sách, nên chừa một chỗ.
            const tracked = server.trackedNotifications.values;
            for (let i = 0; i <= tracked.length - root.historyLimit; i++)
                tracked[i].expire();

            if (root.dnd && n.urgency !== NotificationUrgency.Critical)
                return;
            root.popups = [n, ...root.popups.filter(p => p.id !== n.id)];
        }
    }
}
