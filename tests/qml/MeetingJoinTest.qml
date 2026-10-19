import Quickshell
import QtQuick
import qs.services
import qs.shell.components
import "Harness.js" as T

// The Join button and CalendarService's side of it, in the runner's sandbox:
// when the button shows and how it looks, and that a Join outside the real
// session starts nothing (a link handed to a browser from a test would reach
// the user's real one) but says what it would have opened. Calendars from a
// link stay a preview here too. Invented links.
ShellRoot {
    id: root
    property int waits: 0

    Component {
        id: buttonComponent
        MeetingJoinButton {}
    }
    // In a window: an item outside every scene keeps the visibility it had
    // once it was hidden.
    FloatingWindow {
        visible: true
        implicitWidth: 200
        implicitHeight: 60
        Item { id: holder; anchors.fill: parent }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            if (!SettingsService.loaded && root.waits < 100) return
            running = false
            root.check()
        }
    }

    function check() {
        const at = (hours, minutes) => new Date(2026, 9, 19, hours, minutes || 0)
        const meeting = { title: "Weekly", allDay: false, start: at(10), end: at(10, 30),
                          description: "Join the meeting now<https://teams.microsoft.com/l/meetup-join/sample>" }
        const lunch = { title: "Lunch", allDay: false, start: at(12), end: at(13), description: "" }

        const button = buttonComponent.createObject(holder, { event: meeting, now: at(8) })
        T.eq([button.visible, button.variant, button.text], [true, "surface", "Join"], "a later meeting in a list: plain Join")
        T.eq(button.toolTip, "Opens the Teams meeting", "the tip names the service")
        button.now = at(9, 56)
        T.eq([button.visible, button.variant], [true, "accent"], "five minutes before: the accent")
        button.now = at(10, 30)
        T.eq(button.visible, false, "gone once it has ended")
        button.soon = true
        button.now = at(9, 30)
        T.eq(button.visible, false, "in the notch: not half an hour before")
        button.now = at(10, 5)
        T.eq(button.visible, true, "but while it runs")
        button.event = lunch
        T.eq(button.visible, false, "an event without a link has none")
        button.event = null
        T.eq([button.visible, button.toolTip], [false, ""], "nor does no event")
        button.destroy()

        // A Join here opens nothing and says what it would have.
        T.ok(!CalendarService.realSession, "the runner is no real session")
        T.eq(CalendarService.join(meeting), true, "Join answers")
        T.ok(/^teams: /.test(CalendarService.joinPreview), "and names what would have opened it")
        T.ok(CalendarService.joinPreview.indexOf("meetup-join") < 0, "without the link")
        T.eq(CalendarService.join(lunch), false, "no link, nothing to join")
        T.eq(CalendarService.nextJoin(at(9, 58)), null, "no events in the sandbox, none to join")

        // Calendars from a link: refused links are refused here, a good one is
        // a preview with its host, and the list is never asked for.
        T.eq(CalendarService.addLink("http://calendar.example.test/a.ics", "Work"), false, "plain http refused")
        T.ok(CalendarService.linkError && /https/.test(CalendarService.linkMessage), "with the reason")
        T.eq(CalendarService.addLink("webcal://calendar.example.test/secret/a.ics", "Work"), true, "a link is taken")
        T.eq(CalendarService.linkPreview, "add: Work from calendar.example.test, read-only, every 15 minutes",
             "as a preview with its host and no more of it")
        T.eq([CalendarService.linkBusy, CalendarService.linkError], [false, false], "nothing ran")
        CalendarService.refreshLinks()
        T.eq([CalendarService.linkState, CalendarService.linkListing], ["", false], "no helper outside the real session")
        T.eq(CalendarService.removeLink("akonadi_ical_resource_1"), false, "nothing removed here")
        T.eq(CalendarService.removeLink("../etc"), false, "nor anything that is no resource id")

        T.finish("MeetingJoinTest")
    }
}
