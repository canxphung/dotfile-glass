pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Danh sách ứng dụng, tìm kiếm, số lần mở và app ghim trên taskbar.
// Số lần mở và app ghim lưu ở ~/.local/state/glass/shell/apps.json.
Singleton {
    id: root

    // Mọi app có trong menu, theo tên.
    readonly property var all: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    // App ghim trên taskbar (chỉ những app có thật). Ghim theo id của
    // desktop entry hoặc tên class của cửa sổ ("foot" khớp
    // org.codeberg.dnkl.foot.desktop).
    readonly property var pinned: {
        all; // quét xong danh sách app hoặc cài thêm app thì tính lại
        const found = store.pinned.map(id => DesktopEntries.heuristicLookup(id)).filter(e => e);
        return found.filter((e, i) => found.indexOf(e) === i);
    }

    // App hay dùng nhất; chưa mở gì thì lấy app ghim.
    function frequent(limit: int): var {
        const used = all
            .filter(e => (store.launches[e.id] ?? 0) > 0)
            .sort((a, b) => store.launches[b.id] - store.launches[a.id]);
        const result = used.slice(0, limit);
        for (const e of pinned) {
            if (result.length >= limit)
                break;
            if (!result.includes(e))
                result.push(e);
        }
        return result;
    }

    // Bỏ dấu tiếng Việt và chữ hoa để "tro choi" khớp "Trò chơi".
    function fold(text: string): string {
        return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();
    }

    function score(entry: var, q: string): int {
        const name = fold(entry.name);
        if (name.startsWith(q))
            return 100;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 80;
        if (name.includes(q))
            return 60;
        const extra = [entry.genericName, entry.comment, entry.id].concat(Array.from(entry.keywords)).map(fold);
        if (extra.some(t => t.includes(q)))
            return 40;
        return 0;
    }

    function search(query: string): var {
        const q = fold(query.trim());
        if (q === "")
            return [];
        return all
            .map(e => ({ entry: e, score: score(e, q) }))
            .filter(r => r.score > 0)
            .sort((a, b) => (b.score - a.score) || ((store.launches[b.entry.id] ?? 0) - (store.launches[a.entry.id] ?? 0)))
            .map(r => r.entry);
    }

    function launch(entry: var): void {
        const command = Array.from(entry.command);
        if (entry.runInTerminal)
            command.unshift(Glass.terminal, "-e");
        Glass.run(entry.id, command);
        const launches = Object.assign({}, store.launches);
        launches[entry.id] = (launches[entry.id] ?? 0) + 1;
        store.launches = launches;
    }

    function isPinned(id: string): bool {
        return pinned.some(e => e.id === id);
    }

    function togglePin(id: string): void {
        if (isPinned(id))
            store.pinned = store.pinned.filter(p => DesktopEntries.heuristicLookup(p)?.id !== id);
        else
            store.pinned = [...store.pinned, id];
    }

    // App đang chạy có appId này ứng với desktop entry nào.
    function entryFor(appId: string): var {
        return appId ? DesktopEntries.heuristicLookup(appId) : null;
    }

    FileView {
        path: Theme.stateDir + "/shell/apps.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: store

            property var launches: ({})
            property list<string> pinned: ["kitty", "org.kde.dolphin", "org.gnome.Nautilus", "thunar", "pcmanfm-qt", "firefox", "chromium", "brave-browser", "google-chrome"]
        }
    }
}
