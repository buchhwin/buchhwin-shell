pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "notifications/NotificationLogic.js" as Logic

// Session notification server, popup queue and Do Not Disturb. DND modes:
// off, 1h, tomorrow (next morning), manual. The mode survives reloads.
Singleton {
    id: root
    // Nested test sessions share the host's session bus: a nested shell that
    // owns org.freedesktop.Notifications steals the name from the real shell
    // whenever that one restarts. Nested shells only run the server with
    // BUCHHWIN_NESTED_NOTIFICATIONS=1.
    readonly property bool serverWanted: Quickshell.env("BUCHHWIN_NESTED") !== "1"
        || Quickshell.env("BUCHHWIN_NESTED_NOTIFICATIONS") === "1"
    readonly property var server: serverLoader.item
    readonly property int maxPopups: 3
    readonly property var history: server ? server.trackedNotifications.values : []
    property var popups: []
    property int unread: 0
    property string dndMode: "off"
    property real dndUntil: 0
    // Per-app rules ({ "<app key>": "mute" | "critical" }). They live in
    // state.json beside DND rather than in settings.json, which holds only
    // primitives per key.
    property var appRules: ({})
    property real now: Date.now()
    readonly property bool dndActive: dndMode === "manual" || ((dndMode === "1h" || dndMode === "tomorrow") && dndUntil > now)
    readonly property bool autoSuppressed: (SettingsService.value("notifications.suppressFullscreen") && HyprlandService.fullscreenActive)
        || (SettingsService.value("notifications.suppressGames") && HyprlandService.gameActive)
    readonly property bool suppressed: dndActive || autoSuppressed

    readonly property string dndLabel: !dndActive ? "Off"
        : dndMode === "manual" ? "Until turned off"
        : "Until " + Qt.formatTime(new Date(dndUntil), "HH:mm") + (dndMode === "tomorrow" ? " (tomorrow)" : "")

    function setDnd(mode) {
        const current = new Date()
        let until = 0
        if (mode === "1h") until = current.getTime() + 3600000
        else if (mode === "tomorrow") {
            const hour = SettingsService.value("notifications.dndTomorrowHour")
            until = new Date(current.getFullYear(), current.getMonth(), current.getDate() + 1, hour, 0, 0).getTime()
        } else if (mode !== "manual") mode = "off"
        dndMode = mode
        dndUntil = until
        now = Date.now()
        saveState()
        scheduleExpiry()
    }

    function toggleDnd() { setDnd(dndActive ? "off" : "manual") }

    function clearAll() {
        const values = root.history.slice()
        for (let i = values.length - 1; i >= 0; --i) values[i].dismiss()
        popups = []
        unread = 0
    }

    function hidePopup(notification) {
        popups = popups.filter(item => item !== notification)
    }

    function markRead() { unread = 0 }

    function isCritical(notification) {
        return notification && notification.urgency === NotificationUrgency.Critical
    }

    function scheduleExpiry() {
        if ((dndMode === "1h" || dndMode === "tomorrow") && dndUntil > Date.now()) {
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

    function saveState() {
        stateFile.setText(JSON.stringify({ dnd: { mode: dndMode, until: dndUntil, boot: bootId },
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

    function loadState() {
        try {
            const parsed = JSON.parse(stateFile.text() || "{}")
            const dnd = parsed.dnd || {}
            dndMode = ["off", "1h", "tomorrow", "manual"].indexOf(dnd.mode) >= 0 ? dnd.mode : "off"
            dndUntil = Number(dnd.until) || 0
            // **A reboot turns a manual Do Not Disturb off.** "Until turned
            // off" is a promise about this session, and starting the machine
            // again is as clear an answer as reaching for the switch would be;
            // it was reported as Do Not Disturb having switched itself back on
            // after a restart. A *timed* one is a promise about the clock
            // instead - "until six tomorrow" means six tomorrow whether or not
            // the machine slept in between - so those two are left alone.
            if (dndMode === "manual" && String(dnd.boot || "") !== bootId) dndMode = "off"
            const rules = parsed.appRules || {}
            const clean = {}
            for (const key in rules) if (rules[key] === "mute" || rules[key] === "critical") clean[key] = rules[key]
            appRules = clean
        } catch (error) {
            dndMode = "off"
            appRules = ({})
        }
        now = Date.now()
        scheduleExpiry()
    }

    Timer {
        id: expiry
        onTriggered: {
            root.now = Date.now()
            if (!root.dndActive && root.dndMode !== "off") {
                root.dndMode = "off"
                root.saveState()
            } else {
                root.scheduleExpiry()
            }
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
            root.popups = Logic.livePopups(root.popups, root.server ? root.server.trackedNotifications.values : [])
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
                notification.tracked = true
                root.now = Date.now()
                if (!PanelService.isOpen("notifications")) root.unread += 1
                const state = { suppressed: root.suppressed, dndMode: root.dndMode }
                if (!Logic.shouldPopup(state, root.isCritical(notification), Logic.ruleFor(root.appRules, notification))) return
                root.popups = Logic.withPopup(root.popups, notification, root.maxPopups)
            }
        }
    }
}
