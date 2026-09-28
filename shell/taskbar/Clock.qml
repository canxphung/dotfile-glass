import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Đồng hồ hai dòng như Windows 7: giờ trên, ngày dưới. Bấm để xem lịch.
HoverButton {
    id: root

    required property var window

    implicitWidth: Math.max(time.implicitWidth, date.implicitWidth) + 20
    highlighted: calendar.visible
    onClicked: calendar.toggle()

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: -1

        Label {
            id: time
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
        }

        Label {
            id: date
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "dd/MM/yyyy")
        }
    }

    Calendar {
        id: calendar
        window: root.window
        button: root
        today: clock.date
    }
}
