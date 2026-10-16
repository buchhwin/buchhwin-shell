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

    // A day chosen with the keys or the pointer. Choosing rebuilds the cells
    // and destroys the delegate that did it, so everything is read first and
    // the panel notified before that. A day chosen from the keyboard hands
    // the focus on to the new cell of the same day; it would go with the old
    // one, and the next arrow would start over at the panel's first control.
    function choose(cell, refocus) {
        const date = cell.modelData.date
        const inMonth = cell.modelData.inMonth
        root.daySelected(date)
        root.selectedDate = date
        if (!inMonth) {
            root.year = date.getFullYear()
            root.month = date.getMonth()
        }
        if (refocus) Qt.callLater(root.focusDay, root.key(date))
    }

    function focusDay(dayKey) {
        for (let i = 0; i < days.count; ++i) {
            const item = days.itemAt(i)
            if (item && root.key(item.modelData.date) === dayKey) {
                item.forceActiveFocus(Qt.TabFocusReason)
                return
            }
        }
    }

    function backToToday() {
        root.reset()
        root.daySelected(root.today)
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
        ShellButton { toolTip: "Previous month"; icon: Icons.back; variant: "ghost"; compact: true; onClicked: root.shift(-1) }
        ShellText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: SettingsService.locale.toString(new Date(root.year, root.month, 1), "MMMM yyyy")
            role: "title"
            // A click on the month goes back to today. It had no key at all,
            // so it is a stop for the panel's keys too (NavLogic stops on
            // `focusOnTab` and asks `available`), and says what it does.
            property bool focusOnTab: false
            readonly property bool available: root.selectable
            activeFocusOnTab: focusOnTab && root.selectable
            Keys.onReturnPressed: root.backToToday()
            Keys.onEnterPressed: root.backToToday()
            Keys.onSpacePressed: root.backToToday()
            Accessible.role: root.selectable ? Accessible.Button : Accessible.StaticText
            Accessible.name: text
            Accessible.description: root.selectable ? "Back to today" : ""
            Accessible.onPressAction: if (root.selectable) root.backToToday()
            FocusRing { active: parent.activeFocus; controlRadius: Metrics.radiusInner }
            MouseArea {
                anchors.fill: parent
                enabled: root.selectable
                cursorShape: root.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.backToToday()
            }
        }
        ShellButton { toolTip: "Next month"; icon: Icons.forward; variant: "ghost"; compact: true; onClicked: root.shift(1) }
    }

    // Seven equal columns. Every cell asks for the same token width and
    // fills the rest: with no width of its own a day cell left the weekday
    // names to share the row out, and "Wed" took more than "Fri" and "Sat",
    // which ended up squeezed together (column steps of 63/62/64/51/45/55 px;
    // round 12, D7).
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
                Layout.preferredWidth: 1
                horizontalAlignment: Text.AlignHCenter
                text: SettingsService.locale.dayName((index + 1) % 7, Locale.ShortFormat)
                role: "small"
                muted: true
            }
        }

        Repeater {
            id: days
            model: root.cells
            Item {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: Metrics.controlHeight
                // A stop for the panel's keys like a ListRow, only where a day
                // can be chosen: the arrows walk the grid, Return or Space
                // chooses the day as the click does.
                property bool focusOnTab: false
                readonly property bool available: root.selectable
                activeFocusOnTab: focusOnTab && root.selectable
                Keys.onReturnPressed: root.choose(cell, true)
                Keys.onEnterPressed: root.choose(cell, true)
                Keys.onSpacePressed: root.choose(cell, true)
                Accessible.role: root.selectable ? Accessible.Button : Accessible.StaticText
                Accessible.name: SettingsService.locale.toString(cell.modelData.date, SettingsService.locale.dateFormat(Locale.LongFormat))
                Accessible.description: cell.modelData.hasEvents ? "Has events" : ""
                Accessible.onPressAction: if (root.selectable) root.choose(cell, false)
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
                    FocusRing { active: cell.activeFocus; controlRadius: parent.radius }
                }
                ShellText {
                    anchors.centerIn: parent
                    text: cell.modelData.day
                    // A day of the next or last month is still a number to read:
                    // mutedText, not subtleText, which is for marks.
                    color: cell.modelData.today ? Colors.accentText : cell.modelData.inMonth ? Colors.text : Colors.mutedText
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
                    onClicked: root.choose(cell, false)
                }
            }
        }
    }
}
