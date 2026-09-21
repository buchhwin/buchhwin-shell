import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Events of one day with a coloured bar, time range, title and location.
// A click opens the event details (editing happens in Merkuro).
ColumnLayout {
    id: root
    property date day: new Date()
    property bool isToday: false
    // Only today's events that have not ended (events popup); `day` is ignored.
    property bool remainingOnly: false
    // Arguments that reopen the calling panel when the event dialog closes.
    property var returnArgs: undefined
    readonly property var all: remainingOnly ? CalendarService.remainingToday(clock.date) : CalendarService.eventsFor(day)
    // How many rows the caller has room for. Zero is no limit, which is what
    // a popup that scrolls wants; a card in a grid cell passes what fits, so
    // a short cell shows fewer events rather than the top half of all of them.
    property int maxRows: 0
    readonly property var events: root.maxRows > 0 ? root.all.slice(0, root.maxRows) : root.all
    readonly property int hidden: root.all.length - root.events.length
    readonly property string status: CalendarService.status
    spacing: Metrics.spaceSm

    // The one way a surface says it has nothing to show, like every other list
    // in the shell. This was a bare ShellText with full stops on the end of
    // each line - which EmptyState forbids, because they are labels and not
    // sentences. The two that really are two sentences say so by having a
    // description instead of a full stop in the middle.
    EmptyState {
        Layout.fillWidth: true
        visible: root.all.length === 0
        row: true
        icon: root.status === "unavailable" ? Icons.warning : "󰃭"
        title: root.status === "disabled" ? "Calendar is turned off"
            : root.status === "sandbox" ? "No calendar in the test session"
            : root.status === "ok" && CalendarService.visibleCalendarCount === 0 ? "All calendars are hidden"
            : root.status === "unavailable" ? "KDE calendars are unavailable"
            : root.status === "loading" ? "Loading events …"
            : root.remainingOnly ? (CalendarService.todayEvents.length ? "Nothing else today" : "No events today")
            : root.isToday ? "No events today" : "No events"
        // Only where there is somewhere to go. A day with no events in it is
        // not a problem to be solved, and "No events today · Settings >
        // Calendar" reads as one.
        description: root.status === "disabled"
                || (root.status === "ok" && CalendarService.visibleCalendarCount === 0) ? "Settings > Calendar"
            : root.status === "unavailable" ? "Is Akonadi running?"
            : ""
    }

    Repeater {
        model: root.events
        // Not a `ListRow`, and deliberately: the colour bar down its side has
        // no equivalent there, and time-above-title reads as caption-over-body
        // where ListRow reads as bodyLarge-over-small. Converting it would
        // change how a list the user reads every day looks.
        //
        // What it *was* missing is the part that has nothing to do with the
        // shape: the same event in WeekView lights up under the pointer and
        // here it did not, so one of the two felt dead. The tokens are
        // ListRow's own, and a row that does nothing on click (there is always
        // an event to open) gets no exception.
        Rectangle {
            id: eventRow
            required property var modelData
            readonly property bool past: !modelData.allDay && modelData.end <= clock.date
            readonly property bool down: rowMouse.pressed && rowMouse.containsMouse
            Layout.fillWidth: true
            implicitHeight: rowLayout.implicitHeight + Metrics.spaceXs * 2
            opacity: past ? Effects.mutedOpacity : 1
            radius: Metrics.radiusCard
            color: down ? Colors.pressed : rowMouse.containsMouse ? Colors.hover : "transparent"
            scale: down ? Effects.pressScaleWide : 1
            Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
            Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

            RowLayout {
                id: rowLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Metrics.spaceXs
                anchors.rightMargin: Metrics.spaceXs
                spacing: Metrics.spaceMd

                Rectangle {
                    readonly property color base: CalendarService.colorFor(eventRow.modelData)
                    Layout.fillHeight: true
                    Layout.preferredWidth: Metrics.spaceXs
                    radius: width / 2
                    color: eventRow.modelData.allDay ? Qt.rgba(base.r, base.g, base.b, Effects.eventAllDayFill) : base // style: an event keeps its calendar's colour
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ShellText {
                        text: CalendarService.formatRange(eventRow.modelData)
                        role: "caption"
                        font.features: { "tnum": 1 }
                    }
                    ShellText { Layout.fillWidth: true; text: eventRow.modelData.title }
                }
                ShellIcon {
                    glyph: Icons.forward
                    size: Metrics.iconSm
                    color: Colors.subtleText
                    opacity: rowMouse.containsMouse ? 1 : 0
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: CalendarService.openEvent(eventRow.modelData, root.returnArgs)
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    ShellText {
        Layout.fillWidth: true
        visible: root.hidden > 0
        role: "small"
        muted: true
        // Last, not first: the events are what the list is for, and the count
        // is only there so a shortened list does not look like the whole day.
        text: root.hidden === 1 ? "1 more event" : root.hidden + " more events"
    }
}
