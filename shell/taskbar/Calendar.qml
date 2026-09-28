import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Lịch tháng bật ra phía trên đồng hồ.
GlassPopup {
    id: root

    required property date today
    readonly property var locale: Qt.locale("vi_VN")

    property int month: today.getMonth()
    property int year: today.getFullYear()

    function shift(delta: int): void {
        const d = new Date(year, month + delta, 1);
        month = d.getMonth();
        year = d.getFullYear();
    }

    alignRight: true
    implicitWidth: 300
    frameHeight: layout.implicitHeight + 24

    onVisibleChanged: {
        if (visible) {
            month = today.getMonth();
            year = today.getFullYear();
        }
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.today.toLocaleDateString(root.locale, "dddd, d MMMM, yyyy")
            font.pointSize: Theme.fontSize * 1.1
        }

        RowLayout {
            Layout.fillWidth: true

            HoverButton {
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.shift(-1)

                Glyph {
                    anchors.centerIn: parent
                    text: "\u{f0141}"
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Tháng " + (root.month + 1) + ", " + root.year
                font.bold: true
            }

            HoverButton {
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.shift(1)

                Glyph {
                    anchors.centerIn: parent
                    text: "\u{f0142}"
                }
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: root.locale

            delegate: Label {
                required property string shortName
                horizontalAlignment: Text.AlignHCenter
                text: shortName
                color: Theme.textMuted
            }
        }

        MonthGrid {
            id: grid

            Layout.fillWidth: true
            Layout.preferredHeight: 6 * 30 + 5 * spacing
            month: root.month
            year: root.year
            locale: root.locale

            delegate: Rectangle {
                required property var model

                readonly property bool isToday: model.today

                implicitHeight: 30
                radius: 4
                color: isToday ? Qt.alpha(Theme.accent, 0.55) : "transparent"
                border.color: isToday ? Theme.accentBright : "transparent"

                Label {
                    anchors.centerIn: parent
                    text: parent.model.day
                    opacity: parent.model.month === root.month ? 1 : 0.35
                    font.bold: parent.isToday
                }
            }
        }
    }
}
