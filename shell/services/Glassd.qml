pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Kết nối tới glassd qua socket ($XDG_RUNTIME_DIR/glass/glassd.sock):
// đọc và đổi settings, nhận hộp thoại mà agent Wi-Fi/Bluetooth cần hỏi
// người dùng. glassd chưa chạy thì cứ vài giây thử lại. Giao thức:
// docs/ipc.md.
Singleton {
    id: root

    readonly property bool connected: socket.connected
    // Settings phẳng: "night_light.enabled" → true...
    property var settings: ({})
    // Hộp thoại đang mở, cũ nhất trước. Mỗi phần tử là sự kiện "prompt"
    // của glassd: {id, wait, kind, ...}.
    property var prompts: []
    // Đang có hộp thoại: các lớp phủ khác nhường bàn phím cho nó.
    readonly property bool prompting: prompts.length > 0

    function set(key: string, value: var): void {
        send({ method: "set", key: key, value: value });
    }

    function reply(id: int, value: var): void {
        send({ method: "prompt_reply", prompt: id, value: value });
        drop(id);
    }

    function cancel(id: int): void {
        send({ method: "prompt_cancel", prompt: id });
        drop(id);
    }

    function drop(id: int): void {
        prompts = prompts.filter(p => p.id !== id);
    }

    function send(message: var): void {
        if (!socket.connected)
            return;
        socket.write(JSON.stringify(message) + "\n");
        socket.flush();
    }

    function handle(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.warn("Glassd: dòng không phải JSON:", line);
            return;
        }
        switch (msg.event) {
        case "hello":
            settings = msg.settings;
            break;
        case "changed":
            settings = Object.assign({}, settings, { [msg.key]: msg.value });
            break;
        case "prompt":
            prompts = [...prompts.filter(p => p.id !== msg.id), msg];
            break;
        case "prompt_closed":
            drop(msg.id);
            break;
        }
    }

    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glass/glassd.sock"
    property bool socketExists: false

    Socket {
        id: socket

        path: root.socketPath

        onConnectedChanged: {
            if (connected)
                root.send({ method: "handle_prompts" });
            else
                root.prompts = [];
        }

        parser: SplitParser {
            onRead: line => root.handle(line)
        }
    }

    // Chỉ thử kết nối khi file socket có mặt, để không ghi log lỗi liên tục
    // lúc glassd chưa chạy. FileView không đọc được socket (NotAFile) nhưng
    // báo được khi nó xuất hiện hay mất đi.
    FileView {
        path: root.socketPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.socketExists = false
        onLoadFailed: error => {
            root.socketExists = error === FileViewError.NotAFile;
            if (root.socketExists)
                socket.connected = true;
        }
    }

    // Socket có mà chưa nối được (glassd đang khởi động lại): thử lại.
    Timer {
        interval: 3000
        repeat: true
        running: root.socketExists && !socket.connected
        onTriggered: socket.connected = true
    }
}
