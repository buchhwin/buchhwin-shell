pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "notifications/NotificationLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// Session notification server, popup queue and Do Not Disturb. DND modes:
// off, 1h, tomorrow (next morning), manual. The mode survives reloads.
Singleton {
    id: root
    // Nested test sessions share the host's session bus: a nested shell that
    // owns org.freedesktop.Notifications steals the name from the real shell
    // whenever that one restarts. Nested shells only run the server with
    // BUCHHWIN_NESTED_NOTIFICATIONS=1.
    // The lock screen's process (lock.qml) never runs one: a second server
    // waits in the bus queue there and takes the name - and the notifications
    // with it, into a process that shows none - whenever the shell restarts
    // while the screen is locked (LockLogic.lockProcess).
    readonly property bool serverWanted: !LockLogic.lockProcess(Quickshell.shellId)
        && (Quickshell.env("BUCHHWIN_NESTED") !== "1" || Quickshell.env("BUCHHWIN_NESTED_NOTIFICATIONS") === "1")
    readonly property var server: serverLoader.item
    readonly property int maxPopups: 3
    // How many notifications the history keeps. Every one is tracked, image
    // and all, until it is dismissed, and nothing else ever let one go: a
    // session that was never cleared held every notification since login.
    readonly property int maxHistory: 100
    // And how many of them may hold a picture of their own (image data the
    // sender sent along, Logic.carriesPixels): a hundred 256 px ones were
    // 27 MB that the heap kept after they had gone. Older ones beyond this
    // expire like the ones beyond `maxHistory`.
    readonly property int maxImages: 20
    readonly property var history: server ? server.trackedNotifications.values : []
    property var popups: []
    // The popup the notch shows, when the notch is the display: the newest
    // (Logic.notchPick). The popup stack and the notch's click both ask here.
    readonly property var notchPopup: Logic.notchPick(popups)
    // The notifications that came while the centre was closed, by id
    // (id -> true), and the count of them still in the history. A muted
    // app's are never marked: it was silenced, so it does not light the bell
    // either. Opening the centre clears the marks.
    property var unseen: ({})
    readonly property int unread: Logic.unreadCount(history, unseen)
    // When each notification came, by id (ms since the epoch), for the
    // centre's cards. One carried over a shell restart has none.
    property var arrivals: ({})
    function arrivalOf(notification) {
        const stamp = notification ? arrivals[notification.id] : undefined
        return stamp > 0 ? stamp : 0
    }
    // True while Clear all lets the history go, one dismissal after another:
    // the centre empties its list once instead of reworking it for each.
    property bool clearing: false
    property string dndMode: "off"
    property real dndUntil: 0
    // Whose Do Not Disturb this is: the name of the mode that turned it on
    // (gaming; LayoutLogic.dndOnModeChange), which turns it off again when it
    // is left. "" for the user's own - any change made anywhere else.
    property string dndBy: ""
    // Per-app rules ({ "<app key>": "mute" | "critical" }). They live in
    // state.json beside DND rather than in settings.json, which holds only
    // primitives per key.
    property var appRules: ({})
    property real now: Date.now()
    readonly property bool dndActive: Logic.dndActive(dndMode, dndUntil, now)
    readonly property bool dndTimed: Logic.TIMED_DND.indexOf(dndMode) >= 0
    readonly property bool autoSuppressed: (SettingsService.value("notifications.suppressFullscreen") && HyprlandService.fullscreenActive)
        || (SettingsService.value("notifications.suppressGames") && HyprlandService.gameActive)
    readonly property bool suppressed: dndActive || autoSuppressed

    // "Until 06:00 (tomorrow)" and the rest (Logic.dndLabel), the time as the
    // clock shows it.
    readonly property string dndLabel: Logic.dndLabel(dndMode, dndUntil, dndBy, now, SettingsService.twelveHourClock)

    // `by` only from a mode switch (LayoutService.modeDndTransition); every
    // other caller - the tiles, the launcher, IPC, the focus mode - leaves it
    // out, and the Do Not Disturb set is the user's.
    function setDnd(mode, by) {
        const current = Date.now()
        let until = 0
        if (mode === "1h") until = current + 3600000
        else if (mode === "tomorrow") until = Logic.tomorrowEnd(current, SettingsService.value("notifications.dndTomorrowHour"))
        else if (mode !== "manual") mode = "off"
        dndMode = mode
        dndUntil = until
        dndBy = Logic.dndOwner(mode, by)
        // Any change answers what a reboot asked (`resumeModeDnd`).
        dndEndedBy = ""
        now = Date.now()
        saveState()
        scheduleExpiry()
    }

    function toggleDnd() { setDnd(dndActive ? "off" : "manual") }

    function clearAll() {
        const values = root.history.slice()
        clearing = true
        try {
            for (let i = values.length - 1; i >= 0; --i) values[i].dismiss()
        } finally {
            clearing = false
        }
        popups = []
        unseen = ({})
    }

    // The oldest beyond `maxHistory` expire: they leave the history, and the
    // sender hears that they closed (a `notify-send --wait` or `--action`
    // still waiting on one returns). Expired, not dismissed - nobody closed
    // them. So do the older ones beyond the newest `maxImages` that hold a
    // picture of their own. A popup on screen is left alone; it goes with a
    // later arrival.
    function trimHistory() {
        if (!server) return
        const values = server.trackedNotifications.values
        const old = Logic.overflow(values, maxHistory, popups, maxImages)
        for (const notification of old) notification.expire()
        // The marks and stamps of the ones that have gone, whichever way.
        const left = server.trackedNotifications.values
        const marks = Logic.forHistory(unseen, left)
        if (marks !== unseen) unseen = marks
        const stamps = Logic.forHistory(arrivals, left)
        if (stamps !== arrivals) arrivals = stamps
    }

    function hidePopup(notification) {
        popups = popups.filter(item => item !== notification)
        if (heldPopup === notification) heldPopup = null
    }
    // The popup the notch is showing opened up (a click on it): its timer
    // waits until it is closed again, the way a card waits under the pointer.
    property var heldPopup: null

    function markRead() { unseen = ({}) }

    // Counted as unread unless the centre is open, where it is seen as it
    // comes, or the app is muted.
    function markUnseen(notification, rule) {
        if (!notification || rule === "mute" || PanelService.isOpen("notifications")) return
        if (unseen[notification.id] === true) return
        const marks = Object.assign({}, unseen)
        marks[notification.id] = true
        unseen = marks
    }

    // A sender replaced one of its notifications (replaces_id): Quickshell
    // changes the object it has and announces nothing new, so it was not
    // queued again once its popup had gone, nor counted. Now it came "now",
    // is unread again, and pops up again as the newest when it may pop up at
    // all (its card, still up, shows the new words by itself and stays where
    // it is). Asked for the summary and for the body; the second asking
    // finds it done.
    function replaced(notification) {
        if (!notification) return
        now = Date.now()
        const stamps = Object.assign({}, arrivals)
        stamps[notification.id] = now
        arrivals = stamps
        const rule = Logic.ruleFor(appRules, notification)
        markUnseen(notification, rule)
        const state = { suppressed: suppressed, dndMode: dndMode, dndBy: dndBy }
        const next = Logic.requeue(popups, notification, Logic.shouldPopup(state, isCritical(notification), rule), maxPopups)
        if (next !== popups) popups = next
    }

    function isCritical(notification) {
        return notification && notification.urgency === NotificationUrgency.Critical
    }

    function scheduleExpiry() {
        if (dndTimed && dndUntil > Date.now()) {
            expiry.interval = Math.min(2147483000, Math.max(1000, dndUntil - Date.now() + 500))
            expiry.restart()
        } else {
            expiry.stop()
        }
    }

    // Which boot wrote this. A shell restart must not clear a manual Do Not
    // Disturb - reloading the shell is not answering the question - but a
    // reboot should, and the two are otherwise indistinguishable from in here.
    readonly property string bootId: bootFile.text().trim()

    // A change that comes before the file has been read (Do Not Disturb over
    // IPC at startup) is held and applied over what the file says, instead
    // of writing `appRules: {}` over the stored rules.
    property bool stateLoaded: false
    property var earlyState: null
    function saveState() {
        if (!stateLoaded) {
            earlyState = { mode: dndMode, until: dndUntil, by: dndBy, rules: Object.assign({}, appRules) }
            return
        }
        stateFile.setText(JSON.stringify({ dnd: { mode: dndMode, until: dndUntil, boot: bootId, by: dndBy },
                                           appRules: appRules }, null, 2) + "\n")
    }

    // "default" removes the rule again.
    function setAppRule(key, rule) {
        const next = Object.assign({}, appRules)
        if (rule === "mute" || rule === "critical") next[key] = rule
        else delete next[key]
        appRules = next
        saveState()
    }
    function appRule(key) {
        const rule = appRules[key]
        return rule === "mute" || rule === "critical" ? rule : "default"
    }
    // The apps Settings > Notifications offers a rule for: every one with a
    // rule stored, and every one in the history (Logic.ruleRows). A function,
    // so only a page that shows them works them out.
    function ruleRows() { return Logic.ruleRows(appRules, history) }

    // The mode whose manual Do Not Disturb this boot's start ended, until the
    // mode in use has been asked (`resumeModeDnd`); "" otherwise.
    property string dndEndedBy: ""
    // A `resumeModeDnd` that came before the state was read.
    property string pendingResume: ""

    function loadState() {
        try {
            const parsed = JSON.parse(stateFile.text() || "{}")
            const dnd = parsed.dnd || {}
            // **A reboot turns a manual Do Not Disturb off.** "Until turned
            // off" is a promise about this session, and starting the machine
            // again is as clear an answer as reaching for the switch would be;
            // it was reported as Do Not Disturb having switched itself back on
            // after a restart. A *timed* one is a promise about the clock
            // instead - "until six tomorrow" means six tomorrow whether or not
            // the machine slept in between - so those two are left alone.
            // A mode's own is the mode's promise, not the session's: it comes
            // back while that mode is still in use (`resumeModeDnd`).
            const restored = Logic.dndAtBoot(dnd.mode, dnd.by, dnd.boot, bootId)
            dndMode = restored.mode
            dndUntil = Number(dnd.until) || 0
            dndBy = restored.by
            dndEndedBy = restored.ended
            const rules = parsed.appRules || {}
            const clean = {}
            for (const key in rules) if (rules[key] === "mute" || rules[key] === "critical") clean[key] = rules[key]
            appRules = clean
        } catch (error) {
            dndMode = "off"
            dndBy = ""
            dndEndedBy = ""
            appRules = ({})
        }
        stateLoaded = true
        if (earlyState) {
            dndMode = earlyState.mode
            dndUntil = earlyState.until
            dndBy = earlyState.by || ""
            dndEndedBy = ""
            appRules = Object.assign({}, appRules, earlyState.rules)
            earlyState = null
            // Not from inside the load that is finishing (pitfall 3).
            Qt.callLater(saveState)
        }
        now = Date.now()
        scheduleExpiry()
        // Its setDnd writes the file: not from inside the load either.
        if (pendingResume.length) Qt.callLater(root.resumePending)
    }

    // Asked once by LayoutService with the mode in use, once the layout has
    // been read: a manual Do Not Disturb that this boot's start ended is that
    // mode's again while the mode is still the one in use, owner and all, so
    // leaving it ends it as before. Any change of Do Not Disturb made before
    // it asks answers the question instead. True when it turned it on.
    function resumeModeDnd(mode) {
        if (!stateLoaded) {
            pendingResume = String(mode || "")
            return false
        }
        const owner = dndEndedBy
        dndEndedBy = ""
        if (!owner.length || owner !== mode || dndActive) return false
        setDnd("manual", owner)
        return true
    }
    function resumePending() {
        const mode = pendingResume
        pendingResume = ""
        if (mode.length) resumeModeDnd(mode)
    }

    // The clock read again: at the expiry, and once a minute while a timed
    // mode is on. The expiry alone runs on the monotonic clock, which stops in
    // suspend, so a night slept through ended Do Not Disturb hours late
    // (Logic.dndAfter). A minute after waking is the most it can be off now.
    function checkDnd() {
        now = Date.now()
        const next = Logic.dndAfter(dndMode, dndUntil, now)
        if (next !== dndMode) {
            dndMode = next
            dndBy = Logic.dndOwner(next, dndBy)
            saveState()
        }
        scheduleExpiry()
    }
    Timer {
        id: expiry
        onTriggered: root.checkDnd()
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.dndTimed
        onTriggered: root.checkDnd()
    }

    // The kernel's own boot marker, read once and blocking: it is 37 bytes and
    // `loadState` needs it in the same turn it reads the stored state.
    FileView {
        id: bootFile
        path: "/proc/sys/kernel/random/boot_id"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: stateFile
        path: Paths.stateDir + "/state.json"
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadState()
        onLoadFailed: root.loadState()
    }

    Connections {
        target: root.server ? root.server.trackedNotifications : null
        // Read the model, not the `history` binding: both listen to the same
        // signal, and when this handler runs first the binding still holds the
        // previous snapshot. Filtering against that dropped every fresh popup
        // the moment it was added.
        function onValuesChanged() {
            const next = Logic.livePopups(root.popups, root.server ? root.server.trackedNotifications.values : [])
            // The list changes for every arrival too, and most arrivals take
            // nothing out of the queue: the same queue is left alone.
            if (!Logic.sameSequence(root.popups, next)) root.popups = next
        }
    }

    LazyLoader {
        id: serverLoader
        active: root.serverWanted

        NotificationServer {
            bodySupported: true
            bodyMarkupSupported: false
            imageSupported: true
            actionsSupported: true
            persistenceSupported: true
            keepOnReload: true

            onNotification: notification => {
                root.now = Date.now()
                // Stamped before it is tracked: tracking puts it in the
                // history, and the centre's card for it reads the stamp as
                // it is made.
                const stamps = Object.assign({}, root.arrivals)
                stamps[notification.id] = root.now
                root.arrivals = stamps
                notification.tracked = true
                // After this arrival has been queued as a popup or not, and
                // not from inside the server's own signal.
                Qt.callLater(root.trimHistory)
                const rule = Logic.ruleFor(root.appRules, notification)
                root.markUnseen(notification, rule)
                const state = { suppressed: root.suppressed, dndMode: root.dndMode, dndBy: root.dndBy }
                if (!Logic.shouldPopup(state, root.isCritical(notification), rule)) return
                root.popups = Logic.withPopup(root.popups, notification, root.maxPopups)
            }
        }
    }

    // One watcher per notification in the history, for a sender replacing it
    // in place (`replaced`). Variants keeps the watchers of the ones that stay
    // and makes one for each that comes.
    Variants {
        model: root.history
        Connections {
            required property var modelData
            target: modelData
            function onSummaryChanged() { root.replaced(modelData) }
            function onBodyChanged() { root.replaced(modelData) }
        }
    }
}
