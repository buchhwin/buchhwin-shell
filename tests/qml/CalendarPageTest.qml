import Quickshell
import QtQuick
import qs.services
import qs.shell.components
import "Harness.js" as T
import "../../shell/settings/pages"

// Settings > Calendar's "Calendars from a link" in the runner's sandbox: the
// page loads, the form opens behind its button, a refused link says why and
// keeps the form, and a link that is taken is a preview here (no helper, no
// Akonadi) that names the host only. Invented links.
ShellRoot {
    id: root
    property int waits: 0

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 1400
        visible: true
        Loader { id: loader; width: 860; active: false; sourceComponent: CalendarPage {} }
    }

    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }
    function button(text) {
        return walk(loader.item, item => item.hasOwnProperty("shownText") && item.text === text, [])[0] || null
    }
    function fields() {
        return walk(loader.item, item => item.hasOwnProperty("accessibleName") && item.hasOwnProperty("savedText"), [])
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            if (!SettingsService.loaded && root.waits < 100) return
            running = false
            loader.active = true
            Qt.callLater(root.check)
        }
    }

    function check() {
        T.ok(loader.item !== null, "the page loads")
        const add = button("Add calendar from a link …")
        T.ok(add !== null && add.visible, "the form waits behind its button")
        const both = fields()
        T.eq(both.map(field => field.accessibleName), ["Calendar link", "Calendar name"], "a link and a name")
        T.ok(both.every(field => !field.visible), "hidden until asked for")
        add.clicked()
        T.ok(!add.visible && both.every(field => field.visible), "the button opens the form")
        const confirm = button("Add")
        T.eq(confirm.enabledState, false, "Add waits for a link")

        both[0].text = "http://calendar.example.test/a.ics"
        T.eq(confirm.enabledState, true, "and takes one")
        confirm.clicked()
        T.ok(CalendarService.linkError && /https/.test(CalendarService.linkMessage), "plain http is refused with the reason")
        T.eq(both[0].text, "http://calendar.example.test/a.ics", "and the form keeps the link to correct")

        both[0].text = "webcal://calendar.example.test/private/a.ics"
        both[1].text = "Work"
        confirm.clicked()
        T.eq(CalendarService.linkPreview, "add: Work from calendar.example.test, read-only, every 15 minutes",
             "a test session shows what would be added, by its host")
        T.eq(both[0].text, "", "and the link is not kept in the field")
        T.eq(CalendarService.linkCalendars.length, 0, "nothing is listed: the helper never ran")

        button("Cancel").clicked()
        T.ok(add.visible && both.every(field => !field.visible && field.text === ""), "Cancel closes the form and forgets it")

        // The real session's add, as the page sees it: the state goes back to
        // "" once the answer is in, and the answer decides about the form.
        const page = loader.item
        add.clicked()
        both[0].text = "https://calendar.example.test/a.ics"
        page.addSent = true
        CalendarService.linkState = "adding"
        CalendarService.linkError = true
        CalendarService.linkMessage = "Akonadi refused it."
        CalendarService.linkState = ""
        T.ok(page.adding && both[0].text === "https://calendar.example.test/a.ics", "a refused add keeps the form and the link")
        page.addSent = true
        CalendarService.linkState = "adding"
        CalendarService.linkError = false
        CalendarService.linkMessage = "Added."
        CalendarService.linkState = ""
        T.ok(!page.adding && both[0].text === "", "one that worked closes it")
        T.eq(page.rechecking, true, "and is asked about again while the page is open")
        page.rechecks = 2
        T.eq(page.rechecking, false, "twice, when nothing is being fetched")

        // A calendar Akonadi is fetching is asked about until it is done, ten
        // times at most.
        const fetching = { id: "akonadi_ical_resource_9", name: "Work", host: "calendar.example.test", status: "running",
                           online: true, message: "", subtitle: "calendar.example.test · Updating …" }
        CalendarService.linkCalendars = [fetching]
        T.eq(page.rechecking, true, "a fetch under way is followed")
        CalendarService.linkListing = true
        T.eq(page.rechecking, false, "not while a list is on its way")
        CalendarService.linkListing = false
        page.rechecks = 10
        T.eq(page.rechecking, false, "and not for ever")
        page.followUp(0)
        CalendarService.linkCalendars = [Object.assign({}, fetching, { status: "idle" })]
        T.eq(page.rechecking, false, "done: nothing more to ask")
        CalendarService.linkCalendars = []
        CalendarService.resetLinkMessage()
        T.eq([CalendarService.linkMessage, CalendarService.linkError, CalendarService.linkPreview], ["", false, ""],
             "a page shown again starts without the last visit's words")

        T.finish("CalendarPageTest")
    }
}
