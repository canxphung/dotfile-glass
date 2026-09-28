pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Loa và micro mặc định của PipeWire.
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool ready: sink?.ready ?? false

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true

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
        if (!ready)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute(): void {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    // Giữ node được theo dõi để có volume/muted.
    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => n)
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
