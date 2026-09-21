pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.PimCalendars
import org.kde.kitemmodels
import org.kde.akonadi as Akonadi
import qs.theme
import "calendar/CalendarLogic.js" as Logic
import "calendar/EventDraftLogic.js" as Draft
import "calendar/EventEditLogic.js" as Edit
import "calendar/RecurrenceLogic.js" as Rec
import "calendar/WeekLogic.js" as Week

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
Singleton {
    id: root

    readonly property bool enabled: SettingsService.value("calendar.enabled")
    readonly property int hintMinutes: Math.max(5, Math.min(120, SettingsService.value("calendar.hintMinutes")))
    readonly property bool hintActive: enabled && SettingsService.value("calendar.eventHint")
        && SettingsService.value("desktop.clockIndicators")
    readonly property var hiddenIds: Logic.parseIdList(SettingsService.value("calendar.hiddenCalendars"))
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
    readonly property string status: !enabled ? "disabled"
        : sandboxed ? "sandbox"
        : calendarRows.length > 0 ? "ok"
        : timedOut ? "unavailable" : "loading"

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
    // eventsFor(), for screenshots of the week view without private data.
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
    function formatRange(event) { return Logic.formatRange(event) }

    function isCalendarVisible(id) { return hiddenIds.indexOf(id) < 0 }
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
    readonly property bool writeAllowed: AppearanceService.realSession && !editorPreview && !previewEvents
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
            saveMessage = AppearanceService.realSession ? "Preview: this is what would be written. Nothing was saved."
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
        onExited: code => { exitCode = code; root.finishResolve() }
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
        onExited: code => { exitCode = code; root.finishWrite() }
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

    function openManager() {
        Quickshell.execDetached(["merkuro-calendar"])
        PanelService.close()
    }

    onHiddenIdsChanged: if (backendItem) backendItem.applySelection()
    onEnabledChanged: timedOut = false

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

    LazyLoader {
        id: backend
        active: root.enabled && !root.sandboxed

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
                readonly property string day: Logic.dayKey(date)
                onDayChanged: {
                    root.revision++
                    todayCalendar.today = new Date()
                    todayCalendar.resetToToday()
                    viewCalendar.today = new Date()
                }
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
