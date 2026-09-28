pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

// Nút trên taskbar: app ghim đứng trước, rồi tới app đang chạy; các cửa sổ
// cùng app gộp vào một nhóm như "superbar" của Windows 7.
Singleton {
    readonly property var groups: {
        const byKey = new Map();
        const out = [];
        for (const entry of Apps.pinned) {
            const group = { key: entry.id, entry: entry, windows: [] };
            byKey.set(group.key, group);
            out.push(group);
        }
        for (const toplevel of ToplevelManager.toplevels.values) {
            const entry = Apps.entryFor(toplevel.appId);
            const key = entry?.id ?? (toplevel.appId || toplevel.title);
            let group = byKey.get(key);
            if (!group) {
                group = { key: key, entry: entry, windows: [] };
                byKey.set(key, group);
                out.push(group);
            }
            group.windows.push(toplevel);
        }
        return out;
    }
}
