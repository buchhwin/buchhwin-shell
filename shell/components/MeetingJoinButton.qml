import QtQuick
import qs.theme
import qs.services

// Join for an online meeting, beside an event whose text carries a Teams,
// Meet, Zoom or Webex link (CalendarService.meetingFor). It shows itself only
// then, so a list can put one in every row. In a list it stays until the
// meeting ends (`soon` false); the notch's day page and the clock's hint ask
// for `soon`: from five minutes before the start until the end. A meeting
// that is about to start or running wears the accent, a later one the plain
// surface, so a day of meetings is not a column of loud buttons.
//
// A click opens it (CalendarService.join: a Teams meeting in the Teams web
// app, anything else in the browser) and closes the panel it was in.
ShellButton {
    id: join
    property var event: null
    // The minute clock of the surface (its SystemClock's date): the button
    // runs no clock of its own.
    property var now: new Date()
    property bool soon: false
    readonly property var meeting: event ? CalendarService.meetingFor(event) : null
    readonly property bool starting: meeting !== null && CalendarService.soonJoin(event, now)

    visible: meeting !== null && (soon ? starting : CalendarService.listJoin(event, now))
    compact: true
    variant: starting ? "accent" : "surface"
    icon: Icons.join
    text: "Join"
    toolTip: meeting ? "Opens the " + meeting.label.replace(/^Join /, "") + " meeting" : ""
    onClicked: CalendarService.join(join.event)
}
