pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Thư mục người dùng theo ~/.config/user-dirs.dirs (xdg-user-dirs).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property var dirs: ({})

    function path(name: string, fallback: string): string {
        return dirs[name] ?? home + "/" + fallback;
    }

    readonly property string documents: path("DOCUMENTS", "Documents")
    readonly property string pictures: path("PICTURES", "Pictures")
    readonly property string music: path("MUSIC", "Music")
    readonly property string videos: path("VIDEOS", "Videos")
    readonly property string download: path("DOWNLOAD", "Downloads")

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config") + "/user-dirs.dirs"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const found = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^XDG_([A-Z]+)_DIR="(.*)"$/);
                if (m)
                    found[m[1]] = m[2].replace(/^\$HOME/, root.home);
            }
            root.dirs = found;
        }
    }
}
