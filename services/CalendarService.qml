pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.PimCalendars
import org.kde.kitemmodels
// This import is where every shell log's "QSettings::value: Empty key passed"
// comes from (the line before "Configuration Loaded", and in each QML test
// that imports qs.services): akonadi_quick_plugin links KPim6AkonadiWidgets,
// which links KF6XmlGui, and XmlGui's language-override routine
// (KDEPrivate::initializeLanguages, klanguageoverridesrc) runs as the library
// is loaded and asks QSettings for an empty key. A bare ShellRoot with only
// this import prints it (probed 16./17.10., kxmlgui 6.31); nothing of ours
// uses QSettings. Harmless, and not ours to silence: the import costs about
// 0.4 MB and 5-10 ms, too little for a lazy split. The backend below is
// another matter (see `wanted`).
import org.kde.akonadi as Akonadi
import qs.theme
import "calendar/CalendarLogic.js" as Logic
import "calendar/EventDraftLogic.js" as Draft
import "calendar/EventEditLogic.js" as Edit
import "calendar/LinkLogic.js" as Links
import "calendar/MeetingLogic.js" as Meeting
import "calendar/RecurrenceLogic.js" as Rec
import "calendar/WeekLogic.js" as Week
import "lock/LockLogic.js" as LockLogic

// Read-only KDE calendars (Akonadi, including Google accounts added in KDE)
// through Plasma's calendar "pimevents" plugin, the same source the Plasma
// clock uses. Events arrive with their calendar colour and update live through
// Akonadi. Calendars can be hidden in Settings > Calendar. Event titles never
// go to the log.
//
// Everything that changes a calendar goes through
// scripts/calendar-helper.py, which writes through Akonadi's item API: new
// events into calendars Akonadi reports as writable (CanCreateItem), and
// changes and deletions against the stored incidence. The Plasma plugin
// exposes no event UID, so an opened event is sent to the helper, which finds
// it again and says whether it is a series and which occurrence was meant -
// so a single occurrence can be moved or dropped without touching the rest.
// Writing only happens in the real session; nested sessions, `calendar
// editorPreview` and `calendar preview` show the request instead.
//
// Calendars from a link (Settings > Calendar) are Akonadi iCal resources on
// a published URL, made and removed by scripts/calendar-link.py; their events
// come through the plugin like any other calendar's. An event whose text
// carries a Teams, Meet, Zoom or Webex link gets Join (MeetingLogic.js).
Singleton {
    id: root

    readonly property bool enabled: SettingsService.value("calendar.enabled")
    readonly property int hintMinutes: Math.max(5, Math.min(120, SettingsService.value("calendar.hintMinutes")))
    readonly property bool hintActive: enabled && SettingsService.value("calendar.eventHint")
        && SettingsService.value("desktop.clockIndicators")
    // Re-read on every settings write, whatever its key (`value` depends on
    // the whole document), and each new list re-ran `applySelection` over
    // every calendar and every binding below. An equal list hands back the
    // previous one, which QML does not announce as a change; it is kept in a
    // holder so reading it adds no dependency.
    property var lastHiddenIds: ({ list: [] })
    readonly property var hiddenIds: {
        const next = Logic.parseIdList(SettingsService.value("calendar.hiddenCalendars"))
        if (JSON.stringify(next) === JSON.stringify(lastHiddenIds.list)) return lastHiddenIds.list
        lastHiddenIds.list = next
        return next
    }
    // "accent" (default) or "calendar": colour of the bar next to an event.
    readonly property string eventColorMode: SettingsService.value("calendar.eventColor")
    function colorFor(event) { return Logic.eventColor(event, Colors.accent, eventColorMode) }

    // Nested test sessions sandbox XDG_CONFIG_HOME and never load the Akonadi
    // plugin: a client without the host's server would start a second Akonadi
    // that writes into the host's configuration. Tests use `calendar preview`.
    readonly property bool sandboxed: {
        const configHome = Quickshell.env("XDG_CONFIG_HOME") || ""
        return Quickshell.env("BUCHHWIN_NESTED") === "1"
            || (configHome.length > 0 && configHome !== Paths.home + "/.config")
    }

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    // Bumped whenever the plugin delivers data; functions read it so bindings
    // that call them re-evaluate.
    property int revision: 0
    property bool timedOut: false

    readonly property var backendItem: backend.item
    readonly property var calendarRows: backendItem ? backendItem.rows : []
    readonly property var calendarGroups: Logic.groupCalendars(calendarRows)
    readonly property var writableIds: backendItem ? backendItem.writableIds : []
    // Choices for new events: [{ value: collection id, label }].
    readonly property var newEventCalendars: Draft.calendarOptions(calendarGroups, writableIds, hiddenIds)
    readonly property int visibleCalendarCount: calendarRows.filter(row => row.selectable && hiddenIds.indexOf(row.id) < 0).length

    // disabled | sandbox | loading | ok | unavailable
    readonly property string status: Logic.status(enabled, sandboxed, calendarRows.length, timedOut)

    readonly property var todayEvents: {
        const unused = revision
        return backendItem ? backendItem.eventsOn(backendItem.todayCalendar, new Date()) : []
    }
    readonly property var eventDays: {
        const unused = revision
        const keys = {}
        if (!backendItem) return keys
        const range = Logic.monthRange(viewYear, viewMonth)
        for (let day = range.start; day < range.end; day = Logic.addDays(day, 1)) {
            const events = backendItem.eventsOn(backendItem.viewCalendar, day)
            if (events.length) keys[Logic.dayKey(day)] = events[0].color || true
        }
        return keys
    }

    function showMonth(year, month) {
        const date = new Date(year, month, 1)
        viewYear = date.getFullYear()
        viewMonth = date.getMonth()
    }

    // Synthetic events (IPC `calendar preview`) replace the real ones in
    // eventsFor(), for screenshots of the calendar without private data.
    property var previewEvents: null
    function startPreview(colors) { previewEvents = Week.sampleEvents(new Date(), colors) }

    function eventsFor(date) {
        const unused = revision
        if (previewEvents) return Logic.eventsForDay(previewEvents, date)
        if (!backendItem) return []
        const inView = Logic.inRange(Logic.startOfDay(date), Logic.monthRange(viewYear, viewMonth))
        return backendItem.eventsOn(inView ? backendItem.viewCalendar : backendItem.todayCalendar, date)
    }
    function remainingToday(now) { return Logic.remainingToday(todayEvents, now) }
    function upcoming(now) {
        const unused = revision
        if (!backendItem) return null
        const soon = todayEvents.concat(backendItem.eventsOn(backendItem.todayCalendar, Logic.addDays(now, 1)))
        return Logic.nextUpcoming(soon, now, hintMinutes)
    }
    function formatRange(event) { return Logic.formatRange(event, SettingsService.twelveHourClock) }

    function setCalendarVisible(id, visible) {
        SettingsService.set("calendar.hiddenCalendars", Logic.formatIdList(Logic.withId(hiddenIds, id, !visible)))
    }

    function refresh() { if (backendItem) backendItem.update() }

    // ---- writing: scripts/calendar-helper.py -------------------------------
    // One helper for everything that changes a calendar: it resolves a shown
    // event to its stored incidence and writes through Akonadi's item API.
    // Titles, locations and notes go to it on stdin, never as arguments.
    //
    // Dry run: outside the real session nothing is started at all. A nested
    // session must never reach the host's Akonadi, and `--dry-run` would still
    // read it for anything but a new event, so the dialog shows the request
    // that would be sent instead.
    property bool editorPreview: false
    // The same test as AppearanceService.realSession, read here rather than
    // there: the lock face shows events, and asking AppearanceService would
    // create it in the lock process, which then applies Hyprland options,
    // the cursor and the X11 scale from there.
    readonly property bool realSession: (Quickshell.env("BUCHHWIN_SHELL_PATH") || "").length > 0
        && Quickshell.env("BUCHHWIN_NESTED") !== "1"
    readonly property bool writeAllowed: realSession && !editorPreview && !previewEvents

    // Whether calendar-helper.py can run here at all: it writes through KDE's
    // Akonadi Python bindings (PySide6 and AkonadiCore), which Fedora packages
    // and openSUSE Leap and Arch do not. Nothing asked before, so on Arch the
    // editor took a whole new event and only its Save said the bindings were
    // missing, and an opened event read "could not be matched safely". Asked
    // once per shell, when the backend first starts, with the helper's own two
    // imports (calendar-helper.py `check` would need Akonadi and a request).
    // "" (not asked) | checking | ready | missing
    property string writerState: ""
    readonly property bool writerReady: writerState === "ready"
    // Writes would happen here, and cannot: the editor offers Merkuro instead
    // of a form whose Save would only fail.
    readonly property bool writesBlocked: writeAllowed && writerState === "missing"
    readonly property string writesBlockedReason: writesBlocked ? Edit.refuse("noBindings").message : ""

    function checkWriter() {
        if (writerState.length || !realSession || LockLogic.lockProcess(Quickshell.shellId)) return
        writerState = "checking"
        writerCheck.running = true
    }

    // Quiet either way: a missing module is an answer, not a log line.
    Process {
        id: writerCheck
        command: ["python3", "-c", "try:\n    from PySide6.QtCore import QCoreApplication\n"
                  + "    from AkonadiCore import Akonadi\nexcept Exception:\n    raise SystemExit(1)\n"]
        onExited: code => root.writerState = code === 0 ? "ready" : "missing"
    }
    // "" | saving | saved | error | preview
    property string saveState: ""
    property string saveMessage: ""
    property string previewText: ""

    function helperArgv(command) {
        return ["python3", Paths.script("calendar-helper.py"), command]
    }

    function previewFor(command, request) {
        return command + "\n" + JSON.stringify(request, null, 2)
    }

    function openEditor(day, returnArgs) {
        // Without the bindings a new event can only be made in Merkuro.
        if (writesBlocked) { openManager(); return }
        resetSave()
        PanelService.openOver("eventEditor", { mode: "new", day: Logic.dayKey(day) }, returnArgs)
    }
    function openEvent(event, returnArgs) {
        resetSave()
        resolveEvent(event)
        PanelService.openOver("eventEditor", { mode: "details", event: event }, returnArgs)
    }
    function resetSave() {
        if (saveState === "saving") return
        saveState = ""
        saveMessage = ""
        previewText = ""
    }

    function createEvent(draft, rule) {
        if (saveState === "saving") return false
        if (writesBlocked) return fail(writesBlockedReason)
        const check = Draft.validate(draft)
        if (!check.ok) return fail(check.error)
        const repeat = Rec.validate(rule, draft.date)
        if (!repeat.ok) return fail(repeat.error)
        const request = Draft.addPayload(draft, Rec.payload(rule))
        if (!request) return fail("Nothing to save.")
        writer.calendarId = String(draft.calendarId)
        return startWrite("add", request, "The event could not be saved.")
    }

    function fail(message) {
        saveState = "error"
        saveMessage = message
        return false
    }

    // original/originalRule: what the editor started from.
    function changeEvent(original, draft, locked, originalRule, rule, scope) {
        if (saveState === "saving") return false
        if (writesBlocked) return fail(writesBlockedReason)
        if (!identity.ok) return fail(identityMessage.length ? identityMessage
                                                            : "This event cannot be changed here.")
        const check = Edit.validate(draft, original, locked, rule)
        if (!check.ok) return fail(check.error)
        const planned = Edit.changeRequest(original, draft, identity, locked, originalRule, rule, scope)
        if (!planned) return fail("Nothing changed.")
        writer.calendarId = ""
        return startWrite(planned.command, planned.request, "The event could not be changed.")
    }

    function deleteEvent(scope) {
        if (saveState === "saving") return false
        if (writesBlocked) return fail(writesBlockedReason)
        if (!identity.ok) return fail(identityMessage.length ? identityMessage
                                                            : "This event cannot be deleted here.")
        const planned = Edit.deleteRequest(identity, scope)
        if (!planned) return fail("This event cannot be deleted here.")
        writer.calendarId = ""
        return startWrite(planned.command, planned.request, "The event could not be deleted.")
    }

    function startWrite(command, request, fallback) {
        if (!writeAllowed) {
            previewText = previewFor(command, request)
            saveState = "preview"
            saveMessage = root.realSession ? "Preview: this is what would be written. Nothing was saved."
                : "Test session: this is what would be written. Nothing was saved."
            return true
        }
        previewText = ""
        saveState = "saving"
        saveMessage = ""
        writer.kind = command
        writer.fallback = fallback
        writer.request = JSON.stringify(request)
        writer.exitCode = -1
        writer.outDone = false
        writer.command = helperArgv(command)
        writer.running = true
        writerTimeout.restart()
        return true
    }

    function finishWrite() {
        if (saveState !== "saving" || writer.exitCode < 0 || !writer.outDone) return
        writerTimeout.stop()
        // The answer may contain the title: it is parsed, never logged.
        const answer = Draft.parseAnswer(writer.exitCode, writerOut.text, writer.fallback)
        writer.exitCode = -1
        if (!answer.ok) {
            saveState = "error"
            saveMessage = answer.message
            refresh()
            return
        }
        saveState = "saved"
        saveMessage = writer.kind === "add" ? "Event saved."
            : writer.kind === "delete" || writer.kind === "exclude" ? "Event deleted." : "Event updated."
        if (writer.kind === "add" && writer.calendarId.length)
            SettingsService.set("calendar.newEventCalendar", writer.calendarId)
        if (writer.kind !== "add") {
            identityState = ""
            identity = Edit.refuse("notFound")
        }
        refresh()
    }

    // ---- resolving an existing event ---------------------------------------
    // identityState: "" | checking | ok | refused. The identity (item ids, the
    // UID) stays inside the service: never logged, never in IPC output.
    property var identityEvent: null
    property string identityState: ""
    property var identity: Edit.refuse("notFound")
    readonly property string identityMessage: identity && identity.ok ? "" : String(identity ? identity.message : "")
    readonly property string identityReason: identity && identity.ok ? "" : String(identity ? identity.reason : "")
    readonly property string identityLocation: identity && identity.ok ? String(identity.location || "") : ""
    readonly property bool identityRecurs: identity !== null && identity.ok === true && identity.recurs === true
    property var queuedEvent: null

    function resolveEvent(event) {
        identityEvent = event
        identity = Edit.refuse("notFound")
        if (!event) { identityState = ""; return }
        if (previewEvents) {
            applyIdentity(Edit.previewMatch(event))
            return
        }
        // No helper to ask: the details say why, not "could not be matched".
        if (writesBlocked) {
            applyIdentity(Edit.refuse("noBindings"))
            return
        }
        if (status !== "ok") {
            applyIdentity(Edit.refuse("unavailable"))
            return
        }
        const request = Edit.resolveRequest(event)
        if (!request) { applyIdentity(Edit.refuse("notFound")); return }
        identityState = "checking"
        if (resolver.running) {
            queuedEvent = event
            return
        }
        startResolve(request)
    }

    function applyIdentity(found) {
        identity = found
        identityState = found.ok ? "ok" : "refused"
    }

    function startResolve(request) {
        resolver.request = JSON.stringify(request)
        resolver.exitCode = -1
        resolver.outDone = false
        resolver.command = helperArgv("resolve")
        resolver.running = true
        resolverTimeout.restart()
    }

    function finishResolve() {
        if (resolver.exitCode < 0 || !resolver.outDone) return
        resolverTimeout.stop()
        const answer = Draft.parseAnswer(resolver.exitCode, resolverOut.text, "")
        resolver.exitCode = -1
        if (queuedEvent) {
            // A newer event was opened meanwhile.
            const next = queuedEvent
            queuedEvent = null
            const request = Edit.resolveRequest(next)
            if (request) { Qt.callLater(() => startResolve(request)); return }
        }
        applyIdentity(Edit.applyResolve(answer))
    }

    // The request goes in on stdin so a title is never a process argument.
    Process {
        id: resolver
        property string request: "{}"
        property int exitCode: -1
        property bool outDone: false
        stdinEnabled: true
        onStarted: {
            write(request + "\n")
            stdinEnabled = false
        }
        // Opened again for the next run: closed, the next request would go
        // nowhere and the helper would read an empty one.
        onExited: code => { stdinEnabled = true; exitCode = code; root.finishResolve() }
        stdout: StdioCollector {
            id: resolverOut
            onStreamFinished: { resolver.outDone = true; root.finishResolve() }
        }
        stderr: ErrorLog { label: "calendar-helper.resolve" }
    }

    Timer {
        id: resolverTimeout
        interval: 60000
        onTriggered: {
            resolver.running = false
            root.queuedEvent = null
            if (root.identityState === "checking")
                root.applyIdentity(Edit.refuse("unavailable"))
        }
    }

    Process {
        id: writer
        property string kind: "add"
        property string calendarId: ""
        property string fallback: ""
        property string request: "{}"
        property int exitCode: -1
        property bool outDone: false
        stdinEnabled: true
        onStarted: {
            write(request + "\n")
            stdinEnabled = false
        }
        onExited: code => { stdinEnabled = true; exitCode = code; root.finishWrite() }
        stdout: StdioCollector {
            id: writerOut
            onStreamFinished: { writer.outDone = true; root.finishWrite() }
        }
        stderr: ErrorLog { label: "calendar-helper.write" }
    }

    Timer {
        id: writerTimeout
        interval: 120000
        onTriggered: {
            if (root.saveState !== "saving") return
            writer.running = false
            root.saveState = "error"
            root.saveMessage = "The calendar helper did not finish or could not start. "
                + "Check the calendar in Merkuro before trying again."
        }
    }

    // ---- calendars from a link: scripts/calendar-link.py ---------------------
    // Asked each time Settings > Calendar is shown (refreshLinks) and answered
    // with the list after every change; nothing runs otherwise. The link goes
    // in on stdin and is never kept here: the list names hosts only.
    // A change (add, remove, fetch now) and a list run in processes of their
    // own, so a list asked for meanwhile neither holds up nor drops what the
    // user did.
    // linkState: "" | adding | removing | syncing - a change on its way.
    property var linkCalendars: []
    property string linkState: ""
    property bool linkListing: false
    property string linkMessage: ""
    property bool linkError: false
    // Whether linkMessage is a list's ("Akonadi is not running"), which the
    // next list that works takes back, rather than the answer to a change.
    property bool linkMessageListed: false
    // What a test session would have asked for, without the link.
    property string linkPreview: ""
    readonly property bool linkBusy: linkState.length > 0
    // Moved on as a change starts and as it ends: a list begun before is
    // older than the change's own answer and is dropped.
    property int linkGeneration: 0

    function refreshLinks() {
        if (!realSession || LockLogic.lockProcess(Quickshell.shellId) || linkListing) return
        linkListing = true
        lister.generation = linkGeneration
        lister.exitCode = -1
        lister.outDone = false
        lister.running = true
        listerTimeout.restart()
    }

    // A page shown again starts without the last visit's words, unless a
    // change is still on its way and its answer is yet to come.
    function resetLinkMessage() {
        if (linkBusy) return
        linkMessage = ""
        linkError = false
        linkMessageListed = false
        linkPreview = ""
    }

    // `text` is what was pasted; false when it is refused here (linkMessage
    // says why) or another change is running.
    function addLink(text, name) {
        if (linkBusy) return false
        const link = Links.normalize(text)
        if (!link.ok) return linkFailed(link.error)
        const request = Links.addRequest(text, name)
        if (!realSession) {
            const shown = Links.nameFor(name, link.url)
            linkPreview = "add: " + shown + " from " + Links.hostOf(link.url) + ", read-only, every "
                + Links.REFRESH_MINUTES + " minutes"
            linkError = false
            linkMessageListed = false
            linkMessage = "Test session: this is what would be added. Nothing was changed."
            return true
        }
        return startLink("add", request)
    }
    function removeLink(id) {
        if (linkBusy || !Links.validId(id)) return false
        if (!realSession) return linkFailed("Only in the buchhwin-shell session.")
        return startLink("remove", JSON.stringify({ id: id }))
    }
    function syncLink(id) {
        if (linkBusy || !Links.validId(id)) return false
        if (!realSession) return linkFailed("Only in the buchhwin-shell session.")
        return startLink("sync", JSON.stringify({ id: id }))
    }
    function linkFailed(message) {
        linkError = true
        linkMessageListed = false
        linkMessage = message
        return false
    }

    function startLink(command, request) {
        linkMessage = ""
        linkError = false
        linkMessageListed = false
        linkPreview = ""
        linkGeneration += 1
        linker.kind = command
        linker.request = request
        linker.exitCode = -1
        linker.outDone = false
        linker.command = ["python3", Paths.script("calendar-link.py"), command]
        linker.running = true
        linkerTimeout.restart()
        linkState = command === "add" ? "adding" : command === "remove" ? "removing" : "syncing"
        return true
    }

    function finishLink() {
        if (!linkBusy || linker.exitCode < 0 || !linker.outDone) return
        linkerTimeout.stop()
        // Parsed, never logged: a status message is Akonadi's.
        const answer = Links.parseAnswer(linker.exitCode, linkerOut.text)
        linker.exitCode = -1
        linkGeneration += 1
        if (answer.ok || answer.calendars.length) linkCalendars = answer.calendars
        linkError = !answer.ok
        linkMessageListed = false
        linkMessage = !answer.ok ? answer.message
            : linker.kind === "add" ? "Added. The first events arrive once Akonadi has fetched the calendar."
            : linker.kind === "remove" ? "Removed." : "Fetching now …"
        // Last: whoever waits on the state (the page's form) reads the
        // answer above when it changes.
        linkState = ""
        if (answer.ok) refresh()
    }

    function finishList() {
        if (!linkListing || lister.exitCode < 0 || !lister.outDone) return
        listerTimeout.stop()
        const answer = Links.parseAnswer(lister.exitCode, listerOut.text)
        lister.exitCode = -1
        linkListing = false
        if (lister.generation !== linkGeneration) return
        if (answer.ok || answer.calendars.length) linkCalendars = answer.calendars
        if (answer.ok) {
            if (linkMessageListed) {
                linkMessage = ""
                linkMessageListed = false
            }
            return
        }
        // A look that finds Akonadi not running says so on the page, not as
        // an error of something the user did, and not over a change's answer.
        if (linkMessage.length && !linkMessageListed) return
        linkError = false
        linkMessageListed = true
        linkMessage = answer.message
    }

    Process {
        id: linker
        property string kind: "add"
        property string request: ""
        property int exitCode: -1
        property bool outDone: false
        stdinEnabled: true
        // The link on stdin, never as an argument (see LinkLogic.js).
        onStarted: {
            write(request + "\n")
            stdinEnabled = false
        }
        onExited: code => { stdinEnabled = true; exitCode = code; root.finishLink() }
        stdout: StdioCollector {
            id: linkerOut
            onStreamFinished: { linker.outDone = true; root.finishLink() }
        }
        stderr: ErrorLog { label: "calendar-link" }
    }

    Timer {
        id: linkerTimeout
        // The helper waits up to 20 s for a new agent, and each call 10 s.
        interval: 60000
        onTriggered: {
            if (!root.linkBusy) return
            linker.running = false
            root.linkGeneration += 1
            root.linkFailed("The calendar helper did not finish. Check Settings > Accounts before trying again.")
            root.linkState = ""
        }
    }

    // The list takes nothing on stdin.
    Process {
        id: lister
        property int generation: 0
        property int exitCode: -1
        property bool outDone: false
        command: ["python3", Paths.script("calendar-link.py"), "list"]
        onExited: code => { exitCode = code; root.finishList() }
        stdout: StdioCollector {
            id: listerOut
            onStreamFinished: { lister.outDone = true; root.finishList() }
        }
        stderr: ErrorLog { label: "calendar-link.list" }
    }

    Timer {
        id: listerTimeout
        interval: 30000
        onTriggered: {
            if (!root.linkListing) return
            lister.running = false
            root.linkListing = false
        }
    }

    // ---- joining an online meeting -------------------------------------------
    // The meeting an event joins ({ url, service, label }) or null; whether
    // its Join belongs in a list (until it ends) or in the notch's day page
    // and next to the clock (from MeetingLogic.LEAD_MINUTES before).
    function meetingFor(event) { return Meeting.meeting(event) }
    function listJoin(event, now) { return Meeting.listJoin(event, now || new Date()) }
    function soonJoin(event, now) { return Meeting.soonJoin(event, now || new Date()) }
    // Today's first meeting that offers Join now, or null.
    function nextJoin(now) { return Meeting.nextJoin(remainingToday(now || new Date()), now || new Date()) }

    // What the last Join in a test session would have opened, without the
    // link: "teams: launch-brave.sh".
    property string joinPreview: ""

    // A Teams meeting opens in the Teams web app when there is one (through
    // the browser's session launcher), anything else through the session's
    // xdg-open. Outside the real session nothing starts - a link handed to a
    // browser from a nested session would reach the user's real browser.
    function join(event) {
        const found = Meeting.meeting(event)
        if (!found) return false
        const app = found.service === "teams" ? Meeting.teamsApp(DesktopEntries.applications.values) : null
        const command = Meeting.joinCommand(found, app, Paths.script)
        if (!command) return false
        if (!realSession) {
            joinPreview = found.service + ": " + String(command[0]).split("/").pop()
            console.info("buchhwin-shell: calendar (test session) would join a " + found.service + " meeting with "
                         + joinPreview.slice(found.service.length + 2))
            return true
        }
        Quickshell.execDetached(command)
        PanelService.close()
        return true
    }

    function openManager() {
        // Through launch-app.sh, so Merkuro gets the session's environment
        // (the Plasma look, none of the shell's own settings) and a unit of
        // its own.
        Quickshell.execDetached([Paths.script("launch-app.sh"), "org.kde.merkuro.calendar", "merkuro-calendar"])
        PanelService.close()
    }

    onHiddenIdsChanged: if (backendItem) backendItem.applySelection()
    // The 15-s wait below is for one start of the backend (CalendarLogic.status).
    onEnabledChanged: timedOut = false
    onCalendarRowsChanged: if (calendarRows.length > 0) timedOut = false
    Connections {
        target: backend
        function onActiveChanged() { if (backend.active) root.timedOut = false }
    }

    // After a suspend across midnight the day clock below is late (it runs on
    // a timer that slept too, WallClock.qml): today's list stayed yesterday's
    // until it caught up, and with it the clock's event hint and the notch's
    // next event. A jump of the wall clock asks for the day at once.
    Connections {
        target: WallClock
        function onJumped() { if (root.backendItem) root.backendItem.newDay(new Date()) }
    }

    Timer {
        // Without Akonadi the calendar list stays empty.
        //
        // `repeat` so the timer does not clear its own `running` when it
        // fires. A non-repeating one does, and that tears down the binding
        // below permanently - after which `onEnabledChanged: timedOut = false`
        // above, which exists to arm this timeout again, could never arm
        // anything. Repeating costs nothing: `timedOut` makes the binding
        // false in the same handler that sets it.
        repeat: true
        interval: 15000
        running: backend.active && root.calendarRows.length === 0 && !root.timedOut
        onTriggered: root.timedOut = true
    }

    // Started when something needs it, not with the shell (G6, 2026-10-13):
    // the dashboard, the events popup, the notch's events and its date page,
    // the calendar widget, the lock screen, Settings > Calendar and the clock
    // widget's event hint say so through CalendarDemand while they are shown.
    // Once started it stays for five minutes past the last of them, so a
    // dashboard opened twice does not reconnect to Akonadi twice.
    //
    // The hint used to keep the backend on by itself, from login and in every
    // mode, though only a clock widget of its own (on the desktop, not in a
    // bar or the notch) draws it: in notch and bar modes the shell paid for an
    // indicator nobody could see. And the backend is costly: Plasma's
    // pimevents plugin links KDE's Akonadi calendar, which links KMail's
    // composer and viewer and with them Qt WebEngine - 223 libraries, ~21 MB
    // PSS and ~11 MB of it private (19.10.). Qt never unloads a plugin, so
    // after the first events view the libraries stay mapped; what the cool-
    // down frees is the models and Akonadi's monitors, and what a session
    // without an events view saves is all of it.
    property int trackers: 0
    property bool warm: false
    function track() { trackers += 1; warm = true; coolDown.stop() }
    function untrack() {
        trackers = Math.max(0, trackers - 1)
        if (trackers === 0) coolDown.restart()
    }
    Timer { id: coolDown; interval: 300000; onTriggered: if (root.trackers === 0) root.warm = false }
    readonly property bool wanted: trackers > 0 || warm

    LazyLoader {
        id: backend
        active: root.enabled && !root.sandboxed && root.wanted

        Scope {
            id: scope
            property alias todayCalendar: todayCalendar
            property alias viewCalendar: viewCalendar
            property var rows: []
            property var writableIds: []

            function eventsOn(calendar, date) {
                return Logic.fromEventData(calendar.daysModel.eventsForDate(Logic.startOfDay(date)))
            }

            function update() {
                todayCalendar.daysModel.update()
                viewCalendar.daysModel.update()
            }

            // Today's lists anew, once per day: from the day clock (with the
            // time of its own tick) and from a jump of the wall clock (now),
            // whichever notices the new day first.
            property string shownDay: Logic.dayKey(new Date())
            function newDay(at) {
                if (!Logic.dayChanged(shownDay, at)) return
                shownDay = Logic.dayKey(at)
                root.revision++
                todayCalendar.today = at
                todayCalendar.resetToToday()
                viewCalendar.today = at
            }

            Component.onCompleted: root.checkWriter()

            function readRows() {
                const result = []
                for (let i = 0; i < rowObjects.count; ++i) {
                    const row = rowObjects.objectAt(i)
                    if (row) result.push({ id: row.collectionId, name: row.name, icon: row.iconName,
                                           level: row.kDescendantLevel, selectable: row.isEnabled })
                }
                rows = result
            }

            // Every selectable calendar is shown unless hidden in the settings.
            function applySelection() {
                let changed = false
                for (let i = 0; i < rowObjects.count; ++i) {
                    const row = rowObjects.objectAt(i)
                    if (!row || !row.isEnabled) continue
                    const wanted = root.hiddenIds.indexOf(row.collectionId) < 0
                    if (row.isChecked !== wanted) {
                        pimCalendars.setChecked(row.collectionId, wanted)
                        changed = true
                    }
                }
                if (changed) pimCalendars.saveConfig()
            }

            PlasmaCalendar.EventPluginsManager {
                id: plugins
                enabledPlugins: ["pimevents"]
            }

            SystemClock {
                id: dayClock
                precision: SystemClock.Hours
                enabled: WallClock.ticking
                readonly property string day: Logic.dayKey(date)
                onDayChanged: scope.newDay(date)
            }

            PlasmaCalendar.Calendar {
                id: todayCalendar
                today: new Date()
                displayedDate: new Date()
                days: 7
                weeks: 6
                firstDayOfWeek: 1
                Component.onCompleted: daysModel.setPluginsManager(plugins)
            }

            PlasmaCalendar.Calendar {
                id: viewCalendar
                today: new Date()
                displayedDate: new Date(root.viewYear, root.viewMonth, 1)
                days: 7
                weeks: 6
                firstDayOfWeek: 1
                Component.onCompleted: daysModel.setPluginsManager(plugins)
            }

            Connections {
                target: todayCalendar.daysModel
                function onAgendaUpdated(updatedDate) { revisionTimer.restart() }
            }
            Connections {
                target: viewCalendar.daysModel
                function onAgendaUpdated(updatedDate) { revisionTimer.restart() }
            }
            Timer {
                id: revisionTimer
                interval: 50
                onTriggered: root.revision++
            }

            PimCalendarsModel { id: pimCalendars }

            // Calendars that accept new events (read-only Akonadi collection list).
            Instantiator {
                id: writableObjects
                model: Akonadi.CollectionComboBoxModel {
                    mimeTypeFilter: [Akonadi.MimeTypes.calendar]
                    accessRightsFilter: Akonadi.Collection.CanCreateItem
                }
                delegate: QtObject {
                    required property var collectionId
                }
                onObjectAdded: writableTimer.restart()
                onObjectRemoved: writableTimer.restart()
            }
            Timer {
                id: writableTimer
                interval: 100
                onTriggered: {
                    const ids = []
                    for (let i = 0; i < writableObjects.count; ++i) {
                        const row = writableObjects.objectAt(i)
                        if (row && Number(row.collectionId) > 0) ids.push(Number(row.collectionId))
                    }
                    scope.writableIds = ids
                }
            }

            Instantiator {
                id: rowObjects
                model: KDescendantsProxyModel { model: pimCalendars }
                delegate: QtObject {
                    required property int collectionId
                    required property string name
                    required property string iconName
                    required property bool isChecked
                    required property bool isEnabled
                    required property int kDescendantLevel
                }
                onObjectAdded: rowsTimer.restart()
                onObjectRemoved: rowsTimer.restart()
            }
            Timer {
                id: rowsTimer
                interval: 100
                onTriggered: {
                    scope.readRows()
                    scope.applySelection()
                }
            }
        }
    }
}
