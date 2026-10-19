import Quickshell
import QtQuick
import qs.services
import qs.shell.components
import "Harness.js" as T
import "../../services/calendar/CalendarLogic.js" as C

// The calendar backend (Akonadi through Plasma's pimevents plugin, which
// brings Qt WebEngine and some 220 libraries along) starts only for something
// on screen that shows events - the clock widget's event hint included, as a
// demand of its own - and no longer for the hint setting alone, which kept it
// on from login in every mode. The runner's sandboxed configuration keeps the
// service `sandboxed`, so the backend itself never loads here; what is tested
// is when it would. And the status a later start of the backend shows.
ShellRoot {
    id: root
    property int waits: 0

    Component {
        id: demandComponent
        CalendarDemand {}
    }

    Timer {
        id: wait
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
        T.ok(CalendarService.sandboxed, "the runner's configuration is a sandbox: no Akonadi here")
        T.ok(CalendarService.hintActive, "the event hint is on by default")
        T.eq([CalendarService.trackers, CalendarService.wanted], [0, false],
             "the hint setting alone does not want the backend")
        const demand = demandComponent.createObject(root, { active: true })
        T.eq([CalendarService.trackers, CalendarService.wanted], [1, true], "a shown events view wants it")
        demand.active = false
        T.eq(CalendarService.trackers, 0, "a view that hides lets go")
        T.ok(CalendarService.wanted, "and the backend stays for the cool-down")
        demand.destroy()
        T.ok(!CalendarService.writesBlocked && CalendarService.writerState === "",
             "outside the real session the writer is never asked for")

        // Status across two starts of the backend: the first one slow.
        T.eq(C.status(true, false, 0, false), "loading", "waiting for the first rows")
        T.eq(C.status(true, false, 0, true), "unavailable", "15 s without rows: unavailable")
        T.eq(C.status(true, false, 3, true), "ok", "rows after all: ok (and the service clears the wait)")
        T.eq(C.status(true, false, 0, false), "loading", "the next start, its rows not in yet: loading again")
        T.eq([C.status(false, false, 3, false), C.status(true, true, 0, true)], ["disabled", "sandbox"],
             "off and sandboxed before anything else")
        T.finish("CalendarDemandTest")
    }
}
