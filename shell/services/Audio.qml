pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Âm thanh qua PipeWire: loa/micro mặc định, danh sách thiết bị, âm lượng
// từng app (như Volume Mixer của Windows).
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool ready: sink?.ready ?? false

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? true

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    // Loa, tai nghe... (không phải luồng của app).
    readonly property var sinks: nodes.filter(n => n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => !n.isSink && !n.isStream)
    // App đang phát tiếng.
    readonly property var streams: nodes.filter(n => n.isSink && n.isStream)

    // Âm lượng hoặc trạng thái tắt tiếng đổi (từ bất kỳ đâu: phím, app, pavucontrol).
    signal changed

    function glyph(): string {
        if (!ready || muted || volume <= 0)
            return "\u{f075f}";
        if (volume < 0.34)
            return "\u{f057f}";
        if (volume < 0.67)
            return "\u{f0580}";
        return "\u{f057e}";
    }

    function setVolume(v: real): void {
        setNodeVolume(sink, v);
    }

    function toggleMute(): void {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    function setMicVolume(v: real): void {
        setNodeVolume(source, v);
    }

    function toggleMicMute(): void {
        if (source?.ready)
            source.audio.muted = !source.audio.muted;
    }

    function setNodeVolume(node: var, v: real): void {
        if (!node?.ready)
            return;
        node.audio.muted = false;
        node.audio.volume = Math.max(0, Math.min(1, v));
    }

    function setDefault(node: var): void {
        if (node.isSink)
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;
    }

    // Tên dễ đọc: mô tả của thiết bị, hay tên app với luồng phát.
    function label(node: var): string {
        if (node.isStream)
            return node.properties["application.name"] || node.description || node.name;
        return node.description || node.nickname || node.name;
    }

    // Giữ node được theo dõi để có volume/muted.
    PwObjectTracker {
        objects: [...new Set([root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams])].filter(n => n)
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumesChanged() {
            root.changed();
        }
        function onMutedChanged() {
            root.changed();
        }
    }
}
