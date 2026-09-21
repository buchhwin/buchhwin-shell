import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// Month grid (Monday first) with navigation, today highlighted, optional
// event dots and a selectable day.
ColumnLayout {
    id: root
    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    // { "yyyy-MM-dd": true | "#rrggbb" } for days with events (optional colour).
    property var eventDays: ({})
    property date selectedDate: today
    property bool selectable: false
    signal daySelected(date day)
    spacing: Metrics.spaceMd

    function shift(delta) {
        const next = new Date(year, month + delta, 1)
        year = next.getFullYear()
        month = next.getMonth()
    }

    function reset() {
        year = today.getFullYear()
        month = today.getMonth()
        selectedDate = today
    }

    function key(date) {
        return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0")
    }

    readonly property var cells: {
        const first = new Date(year, month, 1)
        const offset = (first.getDay() + 6) % 7
        const selectedKey = key(root.selectedDate)
        const result = []
        for (let i = 0; i < 42; ++i) {
            const day = new Date(year, month, 1 - offset + i)
            const dayKey = key(day)
            result.push({
                date: day,
                day: day.getDate(),
                inMonth: day.getMonth() === month,
                today: day.toDateString() === root.today.toDateString(),
                selected: root.selectable && dayKey === selectedKey,
                hasEvents: root.eventDays[dayKey] !== undefined,
                eventColor: typeof root.eventDays[dayKey] === "string" ? root.eventDays[dayKey] : ""
            })
        }
        return result
    }

    RowLayout {
        Layout.fillWidth: true
        ShellButton { icon: Icons.back; variant: "ghost"; compact: true; onClicked: root.shift(-1) }
        ShellText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: SettingsService.locale.toString(new Date(root.year, root.month, 1), "MMMM yyyy")
            role: "title"
            MouseArea {
                anchors.fill: parent
                enabled: root.selectable
                cursorShape: root.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: { root.reset(); root.daySelected(root.today) }
            }
        }
        ShellButton { icon: Icons.forward; variant: "ghost"; compact: true; onClicked: root.shift(1) }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: Metrics.spaceXs
        columnSpacing: Metrics.spaceXs

        Repeater {
            model: 7
            ShellText {
                required property int index
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: SettingsService.locale.dayName((index + 1) % 7, Locale.ShortFormat)
                role: "small"
                muted: true
            }
        }

        Repeater {
            model: root.cells
            Item {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Metrics.controlHeight
                Rectangle {
                    anchors.centerIn: parent
                    width: Metrics.controlHeight
                    height: width
                    radius: width / 2
                    color: cell.modelData.today ? Colors.accent
                        : cell.modelData.selected ? Colors.accentSoft
                        : dayMouse.containsMouse ? Colors.hover : "transparent"
                    border.width: cell.modelData.selected && !cell.modelData.today ? Metrics.borderWidth : 0
                    border.color: Colors.accentBorder
                }
                ShellText {
                    anchors.centerIn: parent
                    text: cell.modelData.day
                    color: cell.modelData.today ? Colors.accentText : cell.modelData.inMonth ? Colors.text : Colors.subtleText
                }
                Rectangle {
                    visible: cell.modelData.hasEvents
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.spaceXxs
                    width: Metrics.spaceXs
                    height: width
                    radius: width / 2
                    color: cell.modelData.today ? Colors.accentText
                        : !cell.modelData.inMonth ? Colors.subtleText
                        : cell.modelData.eventColor.length ? cell.modelData.eventColor : Colors.accent
                }
                MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    enabled: root.selectable
                    hoverEnabled: root.selectable
                    cursorShape: root.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    // Changing the selection rebuilds the cells and destroys this
                    // delegate, so read everything first and notify before that.
                    onClicked: {
                        const calendar = root
                        const date = cell.modelData.date
                        const inMonth = cell.modelData.inMonth
                        calendar.daySelected(date)
                        calendar.selectedDate = date
                        if (!inMonth) {
                            calendar.year = date.getFullYear()
                            calendar.month = date.getMonth()
                        }
                    }
                }
            }
        }
    }
}
