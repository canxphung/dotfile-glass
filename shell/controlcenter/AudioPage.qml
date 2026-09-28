import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Trang âm thanh: chọn loa, micro; âm lượng từng app đang phát.
ColumnLayout {
    id: root

    signal back

    spacing: 6

    PageHeader {
        Layout.fillWidth: true
        title: "Âm thanh"
        onBack: root.back()
    }

    Label {
        Layout.fillWidth: true
        visible: Audio.sinks.length === 0
        text: "Không có thiết bị âm thanh (PipeWire chưa chạy?)."
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    SectionLabel {
        visible: Audio.sinks.length > 0
        text: "Phát ra"
    }

    Repeater {
        model: ScriptModel {
            values: Audio.sinks
        }

        DeviceRow {
            isDefault: modelData === Audio.sink
            glyph: Icons.speaker
        }
    }

    SectionLabel {
        visible: Audio.sources.length > 0
        text: "Thu vào"
    }

    Repeater {
        model: ScriptModel {
            values: Audio.sources
        }

        DeviceRow {
            isDefault: modelData === Audio.source
            glyph: Icons.microphone
        }
    }

    SectionLabel {
        visible: Audio.streams.length > 0
        text: "Ứng dụng"
    }

    Repeater {
        model: ScriptModel {
            values: Audio.streams
        }

        ColumnLayout {
            id: stream

            required property var modelData

            Layout.fillWidth: true
            spacing: 0

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 38
                text: Audio.label(stream.modelData)
                opacity: 0.85
            }

            SliderRow {
                glyph: stream.modelData.audio?.muted ? "\u{f075f}" : Icons.speaker
                value: stream.modelData.audio?.volume ?? 0
                dimmed: stream.modelData.audio?.muted ?? false
                onGlyphClicked: stream.modelData.audio.muted = !stream.modelData.audio.muted
                onMoved: v => Audio.setNodeVolume(stream.modelData, v)
            }
        }
    }

    component DeviceRow: HoverButton {
        id: row

        required property var modelData
        property bool isDefault: false
        property string glyph

        Layout.fillWidth: true
        Layout.preferredHeight: 34
        highlighted: isDefault
        onClicked: Audio.setDefault(modelData)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Glyph {
                Layout.preferredWidth: 22
                text: row.glyph
            }

            Label {
                Layout.fillWidth: true
                text: Audio.label(row.modelData)
                font.bold: row.isDefault
            }

            Glyph {
                visible: row.isDefault
                text: Icons.check
                color: Theme.accentBright
            }
        }
    }
}
