pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import QtQuick
import "notifications/NotificationLogic.js" as Logic
import "notifications/SourceLogic.js" as Source
import "notifications/QuietLogic.js" as Quiet
import "notifications/SavedLogic.js" as Saved
import "notifications/SoundLogic.js" as Sound
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
    // centre's cards. One carried over a shell restart has none, unless the
    // kept history (`keepsHistory`) remembers it.
    property var arrivals: ({})
    function arrivalOf(notification) {
        if (notification && notification.earlier === true) return notification.time > 0 ? notification.time : 0
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
    // Per-app rules ({ "<app key>": "mute" | "critical" | "always" }). They
    // live in state.json beside DND rather than in settings.json, which holds
    // only primitives per key.
    property var appRules: ({})
    // Which version of the keys the rules are stored by: 2 since a browser's
    // sites are apps of their own (Source.migrateRules).
    property int rulesVersion: 0
    property real now: Date.now()
    readonly property bool dndActive: Logic.dndActive(dndMode, dndUntil, now)
    readonly property bool dndTimed: Logic.TIMED_DND.indexOf(dndMode) >= 0

    // ---- keeping quiet by itself ---------------------------------------------
    //
    // The popups are this process's: the session's, and a nested shell's own
    // notices (IPC `notifications notice`). The lock screen's process shows
    // none and asks nothing for them.
    readonly property bool popupsHere: !LockLogic.lockProcess(Quickshell.shellId)
    // While the screen is shared (Settings > Notifications, on by default): an
    // Outlook preview or a chat popup landed on the shared screen in front of
    // everyone in the call. What a share is, and why not Hyprland's
    // screencast event, is QuietLogic's. Read from PipeWire's node list only
    // while the setting is on, and never in the lock screen's process.
    readonly property bool sharingWatched: popupsHere && SettingsService.value("notifications.suppressSharing") === true
    // A screen that mirrors another (the display switcher's Duplicate, a
    // projector) shows the room what is on it, as a share does.
    readonly property int screenShares: sharingWatched ? Quiet.shareCount(Pipewire.nodes.values) + (DisplayService.mirroring ? 1 : 0) : 0
    // A popup that gets through a share anyway (an urgent one, an app set to
    // "always") says what it is and from whom, never what it says.
    readonly property bool concealed: screenShares > 0
    // With more than one screen, a fullscreen window on the focused one sends
    // the popups to another screen that has none, instead of holding them
    // back (a Citrix desktop on the big screen, the portrait screen free). ""
    // is the focused screen, as always. Worked out only while the focused
    // window is fullscreen, and never in the lock screen's process.
    readonly property string popupScreenName: popupsHere && SettingsService.value("notifications.fullscreenElsewhere") === true
        && HyprlandService.fullscreenActive && Quickshell.screens.length > 1 ? elsewhereScreen() : ""
    function elsewhereScreen() {
        const focused = PanelService.focusedScreen()
        const name = focused ? focused.name : ""
        return Quiet.popupScreen(name, Quickshell.screens.map(screen => ({
            name: screen.name, fullscreen: screen.name === name || HyprlandService.fullscreenOn(screen) })), true)
    }
    // Why the popups keep quiet by themselves: "sharing", "game",
    // "fullscreen" or "" (Quiet.reason). A fullscreen window of one of
    // `notifications.fullscreenExceptions` (Citrix's Wfica by default: a
    // remote desktop is a workplace) holds nothing back.
    readonly property string quietReason: Quiet.reason({
        suppressSharing: sharingWatched, shares: screenShares,
        suppressGames: SettingsService.value("notifications.suppressGames") === true,
        gameActive: HyprlandService.gameActive,
        suppressFullscreen: SettingsService.value("notifications.suppressFullscreen") === true,
        fullscreenActive: HyprlandService.fullscreenActive,
        appId: HyprlandService.activeAppId,
        exceptions: SettingsService.value("notifications.fullscreenExceptions"),
        elsewhere: popupScreenName.length > 0
    })
    readonly property bool autoSuppressed: quietReason.length > 0
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
        popups = popups.filter(item => item && item.internal === true)
        unseen = ({})
        if (earlierRecords.length) {
            earlierRecords = []
            saveSoon()
        }
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
        const held = Logic.forHistory(missed, left)
        if (held !== missed) missed = held
    }

    function hidePopup(notification) {
        popups = popups.filter(item => item !== notification)
        if (heldPopup === notification) heldPopup = null
    }
    // The popup the notch is showing opened up (a click on it): its timer
    // waits until it is closed again, the way a card waits under the pointer.
    property var heldPopup: null

    // The centre opened: everything in it is seen, and the word about what
    // came while it was quiet has been answered, however it was opened.
    function markRead() {
        unseen = ({})
        if (missedNotice) hidePopup(missedNotice)
    }

    // Counted as unread unless the centre is open, where it is seen as it
    // comes, or the app is muted.
    function markUnseen(notification, rule) {
        if (!notification || rule === "mute" || PanelService.isOpen("notifications")) return
        if (unseen[notification.id] === true) return
        const marks = Object.assign({}, unseen)
        marks[notification.id] = true
        unseen = marks
    }

    // A notification came (or came again, replaced): a popup when it may be
    // one, else held back - and noted for the word once the quiet ends - and
    // its sound when it is shown. One still up that its sender changed shows
    // the new words where it is: no second sound - a progress notification
    // replaced every second would ring every time - and nothing held back.
    function arrived(notification, rule) {
        const critical = isCritical(notification)
        const state = { suppressed: suppressed, dndMode: dndMode, dndBy: dndBy }
        const show = Logic.shouldPopup(state, critical, rule)
        const up = popups.indexOf(notification) >= 0
        const next = Logic.requeue(popups, notification, show, maxPopups)
        if (next !== popups) popups = next
        if (up) return
        if (!show) noteHeld(notification, critical, rule)
        playFor(notification, show)
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
        arrived(notification, rule)
        saveSoon()
    }

    function isCritical(notification) {
        return notification && notification.urgency === NotificationUrgency.Critical
    }

    // ---- what came while it was quiet -----------------------------------------
    //
    // "3 notifications - Came in while Do Not Disturb was on", once, when Do
    // Not Disturb or the automatic muting ends - leaving gaming, the hour run
    // out, the share or the video over - with "Show" opening the centre.
    // Settings > Notifications, off by default. Counted only while it is on:
    // the ones that would have popped up and were held back, of which the
    // notice names those still unread (Quiet.missedCount).
    readonly property bool missedWatched: serverWanted && SettingsService.value("notifications.missedSummary") === true
    property var missed: ({})
    property string missedCause: ""
    function noteHeld(notification, critical, rule) {
        if (!missedWatched || !notification || rule === "mute") return
        if (!Logic.shouldPopup({ suppressed: false }, critical, rule)) return
        missed = Quiet.withMissed(missed, notification.id)
        if (!missedCause.length) missedCause = Quiet.quietCause(dndActive, quietReason)
    }
    // A moment later, not in the change itself: a fullscreen window left
    // for another and back within the same turn is no end.
    onSuppressedChanged: if (!suppressed) Qt.callLater(root.quietEnded)
    function quietEnded() {
        if (suppressed) return
        const count = Quiet.missedCount(missed, history, unseen)
        const cause = missedCause
        missed = ({})
        missedCause = ""
        if (!missedWatched || count <= 0) return
        if (missedNotice) hidePopup(missedNotice)
        missedNotice = postNotice({ summary: Quiet.missedTitle(count), body: Quiet.missedBody(cause), actionText: "Show",
                                    run: () => PanelService.open("notifications") })
    }
    property var missedNotice: null

    // ---- the shell's own notices -----------------------------------------------
    //
    // A popup of the shell's own beside the notifications: no server, no
    // history, no unread mark; it goes when it is closed or runs out, like a
    // popup does. `options`: summary, body, icon (a theme name), appName
    // (what the card's head says; "Notifications" when left out), urgent,
    // actionText with run (the button and the click), force (through every
    // Do Not Disturb, like an app set to "always"). What came while it was
    // quiet is one; IPC `notifications notice` another. Returns the notice,
    // or null when it may not pop up now.
    function postNotice(options) {
        const it = options || {}
        const state = { suppressed: suppressed, dndMode: dndMode, dndBy: dndBy }
        if (!Logic.shouldPopup(state, it.urgent === true, it.force === true ? "always" : "default")) return null
        const notice = noticeComponent.createObject(root, {
            summary: String(it.summary || ""),
            body: String(it.body || ""),
            appIcon: String(it.icon || ""),
            appName: String(it.appName || "Notifications"),
            urgency: it.urgent === true ? NotificationUrgency.Critical : NotificationUrgency.Low
        })
        if (!notice) return null
        if (it.actionText && typeof it.run === "function") {
            const run = it.run
            const make = identifier => noticeActionComponent.createObject(notice, { identifier: identifier, text: String(it.actionText), run: run })
            notice.actions = [make("default"), make("show")]
        }
        notices = notices.concat([notice])
        popups = Logic.withPopup(popups, notice, maxPopups)
        return notice
    }
    // The notices in the queue. One that leaves it - closed, run out, pushed
    // out by newer popups - has nowhere else to be: its card goes with the
    // queue entry, and the object a moment later.
    property var notices: []
    onPopupsChanged: {
        if (!notices.length) return
        const gone = notices.filter(item => popups.indexOf(item) < 0)
        if (!gone.length) return
        notices = notices.filter(item => popups.indexOf(item) >= 0)
        for (const item of gone) item.retire()
    }
    Component {
        id: noticeComponent
        QtObject {
            id: notice
            // What a card, the notch and the queue read of a notification;
            // no `id` (QML's own word), which only the history's are asked.
            readonly property bool internal: true
            property string appName: "Notifications"
            property string appIcon: ""
            property string summary: ""
            property string body: ""
            readonly property string image: ""
            readonly property string desktopEntry: ""
            property int urgency: NotificationUrgency.Low
            readonly property int expireTimeout: -1
            readonly property var hints: ({})
            property var actions: []
            readonly property bool hasInlineReply: false
            readonly property string inlineReplyPlaceholder: ""
            function dismiss() { root.hidePopup(notice) }
            function expire() { root.hidePopup(notice) }
            property bool retired: false
            function retire() {
                if (retired) return
                retired = true
                if (root.missedNotice === notice) root.missedNotice = null
                notice.destroy(1000)
            }
        }
    }
    Component {
        id: noticeActionComponent
        QtObject {
            property string identifier: ""
            property string text: ""
            property var run: null
            function invoke() { if (typeof run === "function") run() }
        }
    }

    // ---- where a notification comes from ---------------------------------------
    //
    // A browser's site by the installed web app it belongs to (SourceLogic):
    // { name, icon, note } for a card and a group - "Microsoft Teams (PWA)"
    // and its icon instead of "Brave" - and `note`, the origin another sender
    // named, beside its name. Desktop entries are looked up for a listed web
    // app only, in the launcher's settled copy, and kept until the next copy
    // (`entryCache`, changed in place so a binding that asks takes no
    // dependency on it; the revision it reads is what brings the binding
    // back once the entries are in - a start asks before they are).
    property var entryCache: ({})
    function webEntry(notification) {
        const app = Source.webAppById(Source.site(notification))
        if (!app) return null
        const browser = String(notification.appName || notification.desktopEntry || "").trim().toLowerCase()
        const slot = app.id + ":" + browser
        const revision = LauncherService.entriesRevision
        const cached = entryCache[slot]
        if (cached && cached.revision === revision) return cached.entry
        const entry = Source.findEntry(LauncherService.entries, app, browser)
        entryCache[slot] = { revision: revision, entry: entry }
        return entry
    }
    function describe(notification) {
        if (!notification) return { name: "", icon: "", note: "" }
        const entry = notification.internal === true ? null : webEntry(notification)
        return {
            name: Source.label(notification, entry ? entry.name : ""),
            icon: entry && entry.icon ? String(entry.icon) : String(notification.appIcon || ""),
            note: Source.originNote(notification)
        }
    }
    // Whether a click on a card without an action of its own still does
    // something: a web app's notification opens the web app.
    function opensSource(notification) {
        return !!notification && notification.internal !== true && webEntry(notification) !== null
    }
    // A card's click. A web app's notification brings its window to the
    // front after the site has had its click (Chromium cannot raise a window
    // on Wayland by itself), or - with no window open - starts the web app
    // rather than letting the browser open the site in a tab. Anything else
    // takes its default action as before. The action can retire the
    // notification; nothing of it is read afterwards.
    function activate(notification, action) {
        if (!notification) return
        const entry = notification.internal === true ? null : webEntry(notification)
        const address = entry ? Source.windowFor(Hyprland.toplevels.values.map(toplevel => ({
            address: toplevel.address, appId: toplevel.wayland ? toplevel.wayland.appId : "" })), entry) : ""
        if (action && (!entry || address.length)) action.invoke()
        if (!entry) return
        if (address.length) HyprCompat.dispatch(HyprCompat.commands.focusWindow(address))
        else LauncherService.launchApp(entry, false)
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
            earlyState = { mode: dndMode, until: dndUntil, by: dndBy, rules: Object.assign({}, appRules),
                           sounds: Object.assign({}, appSounds) }
            return
        }
        stateFile.setText(JSON.stringify({ dnd: { mode: dndMode, until: dndUntil, boot: bootId, by: dndBy },
                                           appRules: appRules, rulesVersion: rulesVersion,
                                           appSounds: appSounds }, null, 2) + "\n")
    }

    // "default" removes the rule again.
    function setAppRule(key, rule) {
        const next = Object.assign({}, appRules)
        if (Logic.isRule(rule)) next[key] = rule
        else delete next[key]
        appRules = next
        saveState()
    }
    function appRule(key) {
        const rule = appRules[key]
        return Logic.isRule(rule) ? rule : "default"
    }
    // The apps Settings > Notifications offers a rule for: every one with a
    // rule stored, and every one in the history (Logic.ruleRows), named as
    // the centre names them. A function, so only a page that shows them
    // works them out.
    function ruleRows() { return Logic.ruleRows(appRules, history, root.describe) }

    // The mode whose manual Do Not Disturb this boot's start ended, until the
    // mode in use has been asked (`resumeModeDnd`); "" otherwise.
    property string dndEndedBy: ""
    // A `resumeModeDnd` that came before the state was read.
    property string pendingResume: ""

    function loadState() {
        let migratedNow = false
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
            for (const key in rules) if (Logic.isRule(rules[key])) clean[key] = rules[key]
            // A browser's rule from before its sites were apps of their own
            // goes to Teams and Outlook as well, once (Source.migrateRules).
            const migrated = Source.migrateRules(clean, parsed.rulesVersion)
            migratedNow = migrated.version !== (Number(parsed.rulesVersion) || 0)
            appRules = migrated.rules
            rulesVersion = migrated.version
            const sounds = parsed.appSounds || {}
            const quiet = {}
            for (const key in sounds) if (sounds[key] === false) quiet[key] = false
            appSounds = quiet
        } catch (error) {
            dndMode = "off"
            dndBy = ""
            dndEndedBy = ""
            appRules = ({})
            rulesVersion = Source.RULES_VERSION
            appSounds = ({})
        }
        stateLoaded = true
        if (earlyState) {
            dndMode = earlyState.mode
            dndUntil = earlyState.until
            dndBy = earlyState.by || ""
            dndEndedBy = ""
            appRules = Object.assign({}, appRules, earlyState.rules)
            appSounds = Object.assign({}, appSounds, earlyState.sounds || {})
            earlyState = null
            migratedNow = true
        }
        // Not from inside the load that is finishing (pitfall 3).
        if (migratedNow) Qt.callLater(saveState)
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

    // ---- sounds -----------------------------------------------------------------
    //
    // One short sound for a popup that is shown (Settings > Notifications,
    // off by default; SoundLogic says when and which). Per app: `appSounds`
    // ({ "<app key>": false }) in state.json beside the rules, for the apps
    // that play their own (a Teams call rings in the browser).
    readonly property bool soundsOn: serverWanted && SettingsService.value("notifications.sounds") === true
    property var appSounds: ({})
    property real lastSound: 0
    function appSound(key) { return appSounds[key] !== false }
    function setAppSound(key, on) {
        const next = Object.assign({}, appSounds)
        if (on === false) next[key] = false
        else delete next[key]
        appSounds = next
        saveState()
    }
    function playFor(notification, shown) {
        if (!soundsOn || !notification) return
        const stamp = Date.now()
        if (!Sound.wantsSound({ enabled: true, shown: shown, suppressed: suppressed, hints: notification.hints,
                                appSound: appSound(Logic.appKey(notification)), now: stamp, last: lastSound })) return
        lastSound = stamp
        Quickshell.execDetached(Sound.command(Sound.soundFile(notification.hints, isCritical(notification))))
    }

    // ---- the history across a restart --------------------------------------------
    //
    // keepOnReload carries the history over a reload, not over a restart -
    // a deploy, Super+Ctrl+R, a crash - and this shell restarts more often
    // than most. With Settings > Notifications "Keep notifications across
    // restarts" (a machine setting, off by default: the words of every
    // notification on disk) the newest 50 are written to a file only its
    // owner can read, and a start shows them under "Earlier" (SavedLogic:
    // what is kept and what is not). Nothing runs, reads or writes while it
    // is off; turning it off removes the file.
    readonly property bool keepsHistory: serverWanted && SettingsService.value("notifications.keepHistory") === true
    readonly property string savedPath: Paths.stateDir + "/notifications.json"
    // Oldest first, as the file keeps them; `earlier` is the centre's, newest
    // first.
    property var earlierRecords: []
    readonly property var earlier: Saved.earlierItems(earlierRecords).reverse()
    // What the centre lists: the history and the earlier ones.
    readonly property int listed: history.length + earlierRecords.length
    // The file exists with mode 0600 (FileView's atomic writes keep the mode
    // of a file that is there, and make a new one 0644), and has been read.
    property bool savedReady: false
    property bool savedRead: false
    onKeepsHistoryChanged: keepsHistory ? prepareSaved() : forgetSaved()
    Component.onCompleted: if (keepsHistory) prepareSaved()
    // Not while the file of a moment ago is still being removed: the removal
    // could come after the new file and leave a later write to make one
    // readable by everyone. It asks again once it is done.
    function prepareSaved() {
        if (savedReady || savedPrepare.running || savedForget.running) return
        savedPrepare.running = true
    }
    function forgetSaved() {
        savedReady = false
        savedRead = false
        saveTimer.stop()
        if (earlierRecords.length) earlierRecords = []
        savedForget.running = true
    }
    function forgetEarlier(item) {
        if (!item || item.earlier !== true) return
        earlierRecords = Saved.without(earlierRecords, item.source)
        saveSoon()
    }
    function loadSaved() {
        if (!keepsHistory) return
        const parts = Saved.split(Saved.parse(savedFile.text()), history)
        earlierRecords = parts.earlier
        let stamps = null
        for (const id in parts.times) {
            if (arrivals[id] > 0) continue
            if (!stamps) stamps = Object.assign({}, arrivals)
            stamps[id] = parts.times[id]
        }
        if (stamps) arrivals = stamps
        savedRead = true
        // Written back through the timer, not from inside the read (pitfall 3).
        saveSoon()
    }
    function saveSoon() {
        if (keepsHistory && savedRead) saveTimer.restart()
    }
    function writeSaved() {
        if (!keepsHistory || !savedReady || !savedRead || !server) return
        const live = history.filter(notification => notification && notification.transient !== true)
            .map(notification => Saved.record(notification, arrivalOf(notification),
                                              Source.originHost(Source.hint(notification, Source.ORIGIN_HINT))))
        savedFile.setText(Saved.serialize(Saved.merge(earlierRecords, live)))
    }
    Timer {
        id: saveTimer
        interval: 2000
        onTriggered: root.writeSaved()
    }
    Process {
        id: savedPrepare
        // Made for its owner alone before anything is written into it, and
        // an older one set right.
        command: ["sh", "-c", "umask 077 && mkdir -p -- \"$1\" && { [ -e \"$2\" ] || : > \"$2\"; } && chmod 600 -- \"$2\"",
                  "sh", Paths.stateDir, root.savedPath]
        onExited: code => {
            if (code !== 0) {
                console.warn("buchhwin-shell: the notification history file could not be made private; it is not kept")
                return
            }
            // Turned off meanwhile: the file it has just made goes too.
            if (!root.keepsHistory) {
                if (!savedForget.running) savedForget.running = true
                return
            }
            root.savedReady = true
            if (savedFile.preload) savedFile.reload()
            else savedFile.preload = true
        }
    }
    Process {
        id: savedForget
        command: ["rm", "-f", "--", root.savedPath]
        onExited: if (root.keepsHistory) root.prepareSaved()
    }
    FileView {
        id: savedFile
        path: root.savedPath
        // Read once the file is private (savedPrepare); never watched - the
        // only writer is this service.
        preload: false
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadSaved()
        onLoadFailed: root.loadSaved()
    }

    // ---- for `notifications get` --------------------------------------------------
    // Counts and flags only, like the rest of that answer.
    function report() {
        return {
            screenShares: screenShares,
            concealed: concealed,
            quietReason: quietReason,
            popupScreen: popupScreenName,
            missedSummary: missedWatched,
            missed: Quiet.missedCount(missed, history, unseen),
            notices: popups.filter(item => item && item.internal === true).length,
            keepHistory: keepsHistory,
            earlier: earlierRecords.length,
            sounds: soundsOn,
            rulesVersion: rulesVersion
        }
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
            root.saveSoon()
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
            // KDE Connect's text messages take an answer on the card itself
            // (NotificationCard's reply field) instead of a dialog of its own.
            inlineReplySupported: true
            keepOnReload: true
            // Kept by Quickshell (and offered to senders as capabilities):
            // the site a browser speaks for, which Chromium then sends as a
            // hint instead of the first line of every body
            // (SourceLogic), and - while sounds are on - what a sender says
            // about its sound.
            extraHints: root.soundsOn ? [Source.ORIGIN_HINT, "suppress-sound", "sound-file", "sound-name"]
                                      : [Source.ORIGIN_HINT]

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
                root.arrived(notification, rule)
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
