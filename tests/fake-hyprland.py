#!/usr/bin/env python3
"""IPC giả của Hyprland cho test shell (tests/shell-smoke.sh).

Mở .socket.sock (lệnh) và .socket2.sock (sự kiện) trong
$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE, trả lời đủ để Quickshell
dựng monitor và workspace, ghi lại mọi lệnh dispatch vào file log, và khi
nhận lệnh chuyển workspace thì phát sự kiện workspacev2 như Hyprland thật.

Cách dùng: fake-hyprland.py MONITOR LOG
"""

import json
import os
import re
import socket
import sys
import threading

monitor_name, log_path = sys.argv[1], sys.argv[2]
base = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"])
os.makedirs(base, exist_ok=True)

lock = threading.Lock()
workspaces = [1, 2, 3]
active = 1
listeners = []


def workspace(ws_id):
    return {
        "id": ws_id,
        "name": str(ws_id),
        "monitor": monitor_name,
        "monitorID": 0,
        "windows": 1,
        "hasfullscreen": False,
        "lastwindow": "0x0",
        "lastwindowtitle": "",
    }


def monitor():
    return {
        "id": 0,
        "name": monitor_name,
        "description": "Glass test",
        "x": 0,
        "y": 0,
        "width": 1600,
        "height": 900,
        "scale": 1.0,
        "focused": True,
        "activeWorkspace": {"id": active, "name": str(active)},
        "specialWorkspace": {"id": 0, "name": ""},
    }


def emit(line):
    for conn in list(listeners):
        try:
            conn.sendall((line + "\n").encode())
        except OSError:
            listeners.remove(conn)


def dispatch(arg):
    global active
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(arg + "\n")
    m = re.search(r'workspace = "([^"]+)"', arg) or re.fullmatch(r"workspace (\S+)", arg)
    if not m:
        return
    target = m.group(1)
    if target in ("e+1", "e-1"):
        i = workspaces.index(active) + (1 if target == "e+1" else -1)
        target = str(workspaces[i % len(workspaces)])
    if target.isdigit():
        active = int(target)
        if active not in workspaces:
            workspaces.append(active)
            workspaces.sort()
            emit(f"createworkspacev2>>{active},{active}")
        emit(f"workspacev2>>{active},{active}")


def reply(request):
    with lock:
        if request == "j/status":
            return json.dumps({"configProvider": "lua"})
        if request == "j/monitors":
            return json.dumps([monitor()])
        if request == "j/workspaces":
            return json.dumps([workspace(w) for w in workspaces])
        if request == "j/clients":
            return "[]"
        if request.startswith("dispatch "):
            dispatch(request[len("dispatch "):])
            return "ok"
        return "unknown request"


def serve_requests(server):
    while True:
        conn, _ = server.accept()
        with conn:
            request = conn.recv(65536).decode()
            conn.sendall(reply(request).encode())


def serve_events(server):
    while True:
        conn, _ = server.accept()
        listeners.append(conn)


def listen(name):
    path = os.path.join(base, name)
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX)
    server.bind(path)
    server.listen(8)
    return server


requests = listen(".socket.sock")
events = listen(".socket2.sock")
threading.Thread(target=serve_events, args=(events,), daemon=True).start()
print("fake-hyprland: sẵn sàng", flush=True)
serve_requests(requests)
