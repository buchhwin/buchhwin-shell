import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/calendar/WeekLogic.js" as Week

// Week (Monday first) or single day around the selected day: day headers, an
// all-day row with lanes for multi-day events and a scrollable time grid with
// event blocks in their calendar colours. `dayCount` picks the range (7 = week
// view, 1 = day view). Layout maths lives in WeekLogic.js.
ColumnLayout {
    id: root
    property date today: new Date()
    property date selectedDate: today
    // Days shown side by side: 7 for the week view, 1 for the day view.
    property int dayCount: 7
    signal daySelected(date day)
    signal eventClicked(var event)
    // Double click on the time grid.
    signal createRequested(date day)
    spacing: Metrics.spaceSm

    // Short events are drawn at least half an hour tall.
    readonly property int minMinutes: 30
    readonly property int defaultHour: 7
    readonly property bool singleDay: dayCount === 1
    readonly property date rangeStart: Week.rangeStart(selectedDate, dayCount, 1)
    readonly property string rangeKey: dayCount + " " + SettingsService.locale.toString(rangeStart, "yyyy-MM-dd")
    readonly property var days: Week.weekDays(rangeStart, dayCount)
    // eventsFor() reads the calendar revision, so this follows live updates.
    readonly property var events: Week.uniqueEvents(days.map(day => CalendarService.eventsFor(day)))
    readonly property var allDay: Week.allDayLayout(events, rangeStart, dayCount)
    readonly property var blocks: days.map(day => Week.dayBlocks(events, day, minMinutes))
    readonly property real dayWidth: Math.max(0, (width - Metrics.weekGutter) / dayCount)
    readonly property real minuteHeight: Metrics.weekHourHeight / 60

    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    function shift(steps) { daySelected(Week.shiftRange(selectedDate, steps, dayCount)) }
    function scrollToStart() {
        const hour = Week.scrollHour(blocks, defaultHour)
        grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, hour * Metrics.weekHourHeight - Metrics.spaceSm))
    }
    function rangeLabel() {
        const locale = SettingsService.locale
        if (singleDay) return locale.toString(rangeStart, "dddd, MMMM d, yyyy")
        const end = days[days.length - 1]
        if (rangeStart.getFullYear() !== end.getFullYear())
            return locale.toString(rangeStart, "MMM d, yyyy") + " – " + locale.toString(end, "MMM d, yyyy")
        if (rangeStart.getMonth() !== end.getMonth())
            return locale.toString(rangeStart, "MMM d") + " – " + locale.toString(end, "MMM d, yyyy")
        return locale.toString(rangeStart, "MMMM d") + " – " + locale.toString(end, "d, yyyy")
    }

    onRangeKeyChanged: Qt.callLater(scrollToStart)
    onVisibleChanged: if (visible) Qt.callLater(scrollToStart)
    Component.onCompleted: Qt.callLater(scrollToStart)

    SystemClock { id: clock; precision: SystemClock.Minutes }

    RowLayout {
        Layout.fillWidth: true
        ShellButton { icon: Icons.back; variant: "ghost"; compact: true; toolTip: root.singleDay ? "Previous day" : "Previous week"; onClicked: root.shift(-1) }
        ShellText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.rangeLabel()
            role: "title"
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.daySelected(root.today)
            }
        }
        ShellButton { icon: Icons.forward; variant: "ghost"; compact: true; toolTip: root.singleDay ? "Next day" : "Next week"; onClicked: root.shift(1) }
    }

    // ---- day headers (the day view's title already names the day) --------
    Item {
        Layout.fillWidth: true
        visible: !root.singleDay
        implicitHeight: Metrics.controlHeightSm
        Repeater {
            model: root.days
            Item {
                id: header
                required property var modelData
                required property int index
                readonly property bool isToday: root.sameDay(modelData, root.today)
                readonly property bool isSelected: root.sameDay(modelData, root.selectedDate)
                x: Metrics.weekGutter + index * root.dayWidth
                width: root.dayWidth
                height: parent.height
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.weekBlockGap
                    anchors.rightMargin: Metrics.weekBlockGap
                    radius: Metrics.radiusInner
                    color: header.isSelected ? Colors.accentSoft : headerMouse.containsMouse ? Colors.hover : "transparent"
                    border.width: header.isSelected ? Metrics.borderWidth : 0
                    border.color: Colors.accentBorder
                }
                RowLayout {
                    anchors.centerIn: parent
                    spacing: Metrics.spaceXs
                    ShellText {
                        text: SettingsService.locale.toString(header.modelData, "ddd")
                        role: "small"
                        muted: !header.isToday
                        color: header.isToday ? Colors.accentForeground : Colors.mutedText
                    }
                    ShellText {
                        text: header.modelData.getDate()
                        role: "small"
                        color: header.isToday ? Colors.accentForeground : Colors.text
                        font.weight: header.isToday ? Typography.semibold : Typography.regular
                    }
                }
                MouseArea {
                    id: headerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.daySelected(header.modelData)
                }
            }
        }
    }

    // ---- all-day row ----------------------------------------------------
    Item {
        Layout.fillWidth: true
        visible: root.allDay.lanes > 0
        implicitHeight: root.allDay.lanes * (Metrics.weekAllDayHeight + Metrics.weekBlockGap)
        ShellIcon {
            width: Metrics.weekGutter
            height: Metrics.weekAllDayHeight
            glyph: "󰃭"
            size: Metrics.iconXs
            color: Colors.subtleText
        }
        Repeater {
            model: root.allDay.items
            Rectangle {
                id: allDayBlock
                required property var modelData
                readonly property color base: CalendarService.colorFor(modelData.event)
                x: Metrics.weekGutter + modelData.column * root.dayWidth + Metrics.weekBlockGap
                y: modelData.lane * (Metrics.weekAllDayHeight + Metrics.weekBlockGap)
                width: modelData.span * root.dayWidth - Metrics.weekBlockGap * 2
                height: Metrics.weekAllDayHeight
                radius: Metrics.radiusTiny
                color: Qt.rgba(base.r, base.g, base.b, allDayMouse.containsMouse ? Effects.eventFillHover : Effects.eventAllDayFill) // style: an event keeps its calendar's colour, tinted by a token
                ShellText {
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.spaceXs
                    anchors.rightMargin: Metrics.spaceXs
                    verticalAlignment: Text.AlignVCenter
                    text: (allDayBlock.modelData.continuesBefore ? "‹ " : "") + allDayBlock.modelData.event.title
                    role: "caption"
                    color: Colors.text
                }
                MouseArea {
                    id: allDayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.eventClicked(allDayBlock.modelData.event)
                }
            }
        }
    }

    // ---- time grid ------------------------------------------------------
    Flickable {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: Metrics.weekGridHeight
        contentWidth: width
        contentHeight: 24 * Metrics.weekHourHeight + Metrics.spaceSm
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
            width: grid.width
            height: grid.contentHeight

            Repeater {
                model: 24
                Item {
                    required property int index
                    y: index * Metrics.weekHourHeight
                    width: parent.width
                    height: Metrics.weekHourHeight
                    Rectangle {
                        x: Metrics.weekGutter
                        width: parent.width - Metrics.weekGutter
                        height: Metrics.borderWidth
                        color: Colors.border
                    }
                    ShellText {
                        visible: parent.index > 0
                        width: Metrics.weekGutter - Metrics.spaceXs * 2
                        y: -height / 2
                        horizontalAlignment: Text.AlignRight
                        text: String(parent.index).padStart(2, "0") + ":00"
                        role: "caption"
                        color: Colors.subtleText
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Repeater {
                model: root.days
                Item {
                    id: column
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: root.sameDay(modelData, root.selectedDate)
                    x: Metrics.weekGutter + index * root.dayWidth
                    width: root.dayWidth
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        color: column.isSelected && !root.singleDay ? Colors.hover : "transparent"
                    }
                    Rectangle {
                        width: Metrics.borderWidth
                        height: parent.height
                        color: Colors.border
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.daySelected(column.modelData)
                        onDoubleClicked: root.createRequested(column.modelData)
                    }

                    Repeater {
                        model: root.blocks[column.index] || []
                        Rectangle {
                            id: block
                            required property var modelData
                            readonly property var event: modelData.event
                            readonly property color base: CalendarService.colorFor(event)
                            readonly property real slot: (column.width - Metrics.weekBlockGap * 2) / modelData.columns
                            x: Metrics.weekBlockGap + modelData.column * slot
                            y: modelData.start * root.minuteHeight + Metrics.weekBlockGap / 2
                            width: slot - Metrics.weekBlockGap
                            height: Math.max(Metrics.weekBlockGap, (modelData.shownEnd - modelData.start) * root.minuteHeight - Metrics.weekBlockGap)
                            radius: Metrics.radiusTiny
                            clip: true
                            opacity: event.end <= clock.date ? Effects.mutedOpacity : 1
                            color: Qt.rgba(base.r, base.g, base.b, blockMouse.containsMouse ? Effects.eventFillHover : Effects.eventFill) // style: an event keeps its calendar's colour, tinted by a token

                            Rectangle {
                                width: Metrics.spaceXxs
                                height: parent.height
                                color: block.base
                            }
                            Column {
                                x: Metrics.spaceXs + Metrics.spaceXxs
                                width: parent.width - x - Metrics.spaceXxs
                                ShellText {
                                    width: parent.width
                                    text: block.event.title
                                    role: "caption"
                                    color: Colors.text
                                    wrapMode: Text.Wrap
                                    maximumLineCount: Math.max(1, Math.floor(block.height / (font.pixelSize * 1.3)) - 1)
                                }
                                ShellText {
                                    width: parent.width
                                    visible: block.height >= Metrics.weekHourHeight * 1.5
                                    text: CalendarService.formatRange(block.event)
                                    role: "caption"
                                    font.features: { "tnum": 1 }
                                }
                            }
                            MouseArea {
                                id: blockMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.eventClicked(block.event)
                            }
                        }
                    }
                }
            }

            // Current time on today's column.
            Item {
                readonly property int dayIndex: Week.dayIndex(root.rangeStart, clock.date, root.dayCount)
                visible: dayIndex >= 0 && dayIndex < root.dayCount
                x: Metrics.weekGutter + dayIndex * root.dayWidth
                y: (clock.date.getHours() * 60 + clock.date.getMinutes()) * root.minuteHeight
                width: root.dayWidth
                Rectangle {
                    y: -height / 2
                    width: parent.width
                    height: Metrics.weekNowLine
                    color: Colors.danger
                }
                Rectangle {
                    x: -width / 2
                    y: -height / 2
                    width: Metrics.spaceSm
                    height: width
                    radius: width / 2
                    color: Colors.danger
                }
            }
        }
    }
}
