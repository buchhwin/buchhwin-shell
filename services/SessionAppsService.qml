pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "sessionapps/PlacementLogic.js" as Placement
import "sessionapps/ReopenLogic.js" as Reopen
import "workspaces/WorkspaceLogic.js" as Workspaces
import "hypr/HiddenWindows.js" as Hidden
import "lock/LockLogic.js" as LockLogic

// Apps in their places (Settings > Apps):
//   Open on - an app always opens on a screen and a workspace of that
//     screen's block, or floats: Hyprland window rules sent at runtime, like
//     the workspace blocks, for the screens that are connected;
//   Work apps - a list started together (Super+Alt+W, the launcher, or at
//     login once the wallet step is over), each through the launcher, so a
//     browser keeps its wallet path;
//   Reopen after login - the apps of a session that ended from the shell,
//     offered again by a notification at the next login, never started by
//     themselves.
// The placements and the work apps are ~/.config/buchhwin-shell/apps.json
// (this machine's: they name its screens), the last session's apps
// ~/.local/state/buchhwin-shell/session-apps.json (scripts/session-apps.py,
// 0600, desktop ids and places only). Logic: services/sessionapps/.
//
// Unused, it costs nothing: no rule is sent without a placement, no process
// runs, no timer and no window event is listened to. Inert in the lock
// process; a nested session never starts an app (its windows could open on
// the host, and a browser would touch the real profile) and never notifies.
Singleton {
    id: root

    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell)
    readonly property bool active: !lockProcess
    readonly property bool nested: Quickshell.env("BUCHHWIN_NESTED") === "1"
    // What happens by itself (the login's work apps, the offer) only here.
    readonly property bool realSession: active && !nested && (Quickshell.env("BUCHHWIN_SHELL_PATH") || "").length > 0

    readonly property int block: Workspaces.perMonitorBlock
    readonly property string storePath: Paths.configDir + "/apps.json"
    readonly property string statePath: Paths.stateDir + "/session-apps.json"
    readonly property bool workAtLogin: SettingsService.value("autostart.workAtLogin") === true
    readonly property bool reopenOffer: SettingsService.value("autostart.reopen") === true

    // ---- apps.json ---------------------------------------------------------------
    property var store: Placement.emptyStore()
    property bool storeLoaded: false
    readonly property var rules: store.placement
    readonly property var workApps: store.workApps
    // The file as last read or written: the watch reads every write of our
    // own back (testing.md pitfall 77), and that text is what `store` holds.
    property string storeText: ""

    // A file that is there and cannot be read (not a first start: testing.md
    // pitfall 132) is never written over with an empty store.
    property bool storeRefused: false

    function loadStore() {
        storeRefused = false
        const textValue = storeFile.text()
        if (storeText.length && textValue === storeText) { storeLoaded = true; return }
        if (storeLoaded && !textValue.trim().length) return
        storeText = textValue
        store = Placement.parseStore(textValue, block)
        storeLoaded = true
    }
    // Said once: the watch reads it again now and then (nine times in the
    // first six seconds offscreen).
    function storeFailed(error) {
        if (error !== FileViewError.FileNotFound) {
            if (!storeRefused) console.warn("buchhwin-shell: apps.json cannot be read (" + FileViewError.toString(error)
                                            + "); Settings > Apps keeps it as it is")
            storeRefused = true
        }
        storeLoaded = true
    }
    // One write per event-loop turn (pitfall 3): a burst of changes is one.
    function saveStore(next) {
        if (next === store || !storeLoaded || storeRefused) return false
        store = next
        storeText = Placement.serializeStore(next)
        storeWrite.restart()
        return true
    }
    Timer { id: storeWrite; interval: 0; onTriggered: storeFile.setText(root.storeText) }
    FileView {
        id: storeFile
        path: root.active ? root.storePath : ""
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: root.loadStore()
        onLoadFailed: error => root.storeFailed(error)
        onFileChanged: reload()
    }

    // ---- screens -----------------------------------------------------------------
    // The monitors that are on and show a picture of their own, with the
    // descriptions a placement is matched by (DisplayService reads them from
    // `hyprctl -j monitors all`; Quickshell's screens have none), and where
    // each one's block of workspaces starts (0 without workspaces per monitor).
    readonly property var monitors: active ? DisplayService.monitors
        .filter(monitor => !monitor.disabled && !monitor.mirror && Quickshell.screens.some(screen => screen.name === monitor.name))
        .map(monitor => ({ name: monitor.name, description: monitor.description, model: monitor.model })) : []
    readonly property var offsets: {
        const result = {}
        for (const monitor of monitors) result[monitor.name] = HyprlandService.offsetFor(monitor.name)
        return result
    }
    function monitorNamed(name) { return monitors.find(monitor => monitor.name === name) || null }
    function screenLabel(rule) { return Placement.screenLabel(Placement.monitorFor(rule, monitors)) }
    function screenRects() {
        const result = {}
        for (const screen of Quickshell.screens) result[screen.name] = { x: screen.x, y: screen.y, width: screen.width, height: screen.height }
        return result
    }

    // ---- apps and windows ------------------------------------------------------------
    function entryInfo(app) {
        const entry = String(app || "").length ? DesktopEntries.byId(app) : null
        return entry ? { id: entry.id, name: entry.name || "", startupClass: entry.startupClass || "",
                         categories: entry.categories || [], command: entry.command || [] } : null
    }
    function appName(app) {
        const entry = entryInfo(app)
        return entry && entry.name.length ? entry.name : String(app || "")
    }
    function classOf(toplevel) {
        const wayland = toplevel ? toplevel.wayland : null
        if (wayland && wayland.appId) return wayland.appId
        const ipc = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : {}
        return ipc["class"] || ipc.initialClass || ""
    }
    // The app a window class belongs to, remembered per class until the next
    // scan of the desktop entries; a Citrix session by its title. A holder
    // object, so filling it is no binding's business.
    property var classCache: ({ revision: -1, keys: {} })
    function keyOfWindow(cls, title) {
        const low = String(cls || "").toLowerCase()
        if (low === "wfica") {
            const citrix = Reopen.citrixEntryFor(title, DesktopEntries.applications.values
                .filter(entry => entry && Placement.isCitrixEntry(entry))
                .map(entry => ({ id: entry.id, name: entry.name, startupClass: entry.startupClass })))
            if (citrix.length) return citrix
        }
        if (classCache.revision !== LauncherService.entriesRevision) classCache = { revision: LauncherService.entriesRevision, keys: {} }
        if (classCache.keys[low] === undefined) {
            const entry = low.length ? (DesktopEntries.heuristicLookup(cls) || DesktopEntries.byId(cls) || DesktopEntries.byId(low)) : null
            classCache.keys[low] = entry && entry.id ? entry.id : ""
        }
        return Reopen.keyOf(classCache.keys[low], low)
    }
    // The windows on real workspaces now: [{ address, cls, key }].
    function currentWindows() {
        const result = []
        for (const toplevel of Hyprland.toplevels.values) {
            const address = Reopen.normalizeAddress(toplevel.address)
            const cls = classOf(toplevel)
            if (!address.length || !cls.length || !toplevel.workspace || toplevel.workspace.id < 1 || Hidden.isHiddenClass(cls)) continue
            result.push({ address: address, cls: cls, key: keyOfWindow(cls, toplevel.title) })
        }
        return result
    }
    function openCounts() {
        const counts = {}
        for (const window of currentWindows()) counts[window.key] = (counts[window.key] || 0) + 1
        return counts
    }

    // ---- Open on: the rules ------------------------------------------------------------
    // The rules Hyprland has from us since its last config reload ({ name:
    // { on, match, target } }), and how many taken back in the conf dialect
    // still float their app (Placement.ruleRelease cannot unset that).
    property var knownRules: ({})
    property int staleRules: 0
    readonly property int rulesOn: Object.keys(knownRules).filter(name => knownRules[name].on === true).length
    // Sent once the dialect is known and the desktop entries are read (a
    // web app's windows are its StartupWMClass), and again whenever the
    // placements, the screens, their blocks or the entries change - but not
    // while the saved monitor layout is on its way back (after a config
    // reload every monitor sits at the catch-all place for a moment, and the
    // blocks wait for it too: DisplayService.layoutPending, pitfall 120).
    readonly property string ruleInput: active && HyprCompat.detected && LauncherService.entries.length > 0
        && (rules.length > 0 || rulesOn > 0) && !DisplayService.layoutPending
        ? JSON.stringify([rules, monitors, offsets, HyprCompat.lua, LauncherService.entriesRevision]) : ""
    onRuleInputChanged: if (ruleInput.length) ruleTimer.restart()
    Timer { id: ruleTimer; interval: 400; onTriggered: root.applyRules() }
    function applyRules() {
        if (!active || !HyprCompat.detected) return
        const wanted = Placement.wantedRules(store, monitors, offsets, entryInfo)
        const plan = Placement.rulePlan(knownRules, wanted, HyprCompat.lua)
        knownRules = plan.known
        staleRules = plan.stale
        if (plan.commands.length) HyprCompat.configure(HyprCompat.commands.combine(plan.commands))
    }
    // A reload forgets every rule sent at runtime (and the named ones of the
    // Lua dialect with them), so they are all new again and nothing is stale.
    Connections {
        target: root.active ? HyprlandService : null
        function onConfigReloaded() {
            root.knownRules = ({})
            root.staleRules = 0
            if (root.rules.length) ruleTimer.restart()
        }
    }

    function ruleFor(app) { return Placement.ruleFor(store, app) }
    function ruleText(rule) { return Placement.describeRule(rule, screenLabel(rule)) }
    // A placement from Settings or IPC: `screenName` a connected monitor's
    // connector name ("" for any screen), `workspace` 1-10 of its block or 0
    // for the one it shows.
    function placeApp(app, screenName, workspace, floating) {
        const name = String(screenName || "")
        const monitor = name.length ? monitorNamed(name) : null
        // A place needs a screen or floating; one that is not here is none.
        if (name.length ? !monitor : floating !== true) return false
        const next = Placement.withRule(store, { app: String(app || ""), screen: monitor ? monitor.description : "",
                                                 screenName: monitor ? monitor.name : "", workspace: Number(workspace) || 0,
                                                 float: floating === true }, block)
        return next !== store ? saveStore(next) : Placement.ruleFor(store, String(app || "")) !== null
    }
    function unplace(app) {
        if (!ruleFor(String(app || ""))) return false
        return saveStore(Placement.withoutRule(store, String(app || "")))
    }

    // The dock menu's row for an app on the dock of `screenName` (the
    // focused screen when the dock is everywhere): { on, text }, `on` when
    // the app's place is that screen's shown workspace already.
    function hereOf(screenName) {
        const name = String(screenName || "").length ? String(screenName) : HyprlandService.focusedMonitorName
        const monitor = monitorNamed(name)
        if (!monitor) return null
        const shown = HyprlandService.activeWorkspaceOn(name)
        const local = shown - (offsets[name] || 0)
        return { monitor: monitor, local: local >= 1 && local <= block ? local : 0 }
    }
    function hereFor(app, screenName) {
        const here = hereOf(screenName)
        const rule = here ? Placement.hereRule(String(app || ""), here.monitor, here.local, block) : null
        if (!rule) return null
        const current = ruleFor(rule.app)
        return { on: Placement.isHere(current, rule), text: current ? ruleText(current) : ruleText(rule) }
    }
    function toggleHere(app, screenName) {
        const here = hereOf(screenName)
        const rule = here ? Placement.hereRule(String(app || ""), here.monitor, here.local, block) : null
        if (!rule) return false
        return Placement.isHere(ruleFor(rule.app), rule) ? unplace(rule.app) : saveStore(Placement.withRule(store, rule, block))
    }

    // ---- starting apps -----------------------------------------------------------------
    // One start after another (Reopen.LAUNCH_GAP_MS apart), a browser's family
    // waiting for the browser's first window (it may bring back the rest
    // itself), and an app with a window already never started again.
    property var queue: []
    property var familyWait: ({})
    readonly property bool launching: queue.length > 0
    function enqueue(items) {
        if (!items.length) return
        queue = queue.concat(items)
        if (!launchTimer.running) { launchTimer.start(); tickLaunch() }
    }
    Timer { id: launchTimer; interval: Reopen.LAUNCH_GAP_MS; repeat: true; onTriggered: root.tickLaunch() }
    function tickLaunch() {
        const now = Date.now()
        const open = openCounts()
        const index = Reopen.nextLaunch(queue, open, familyWait, now)
        if (index < 0) {
            if (!Reopen.launchesLeft(queue, open)) {
                launchTimer.stop()
                queue = []
                familyWait = ({})
            }
            return
        }
        const item = queue[index]
        queue = queue.map((entry, at) => at === index ? Object.assign({}, entry, { launched: entry.launched + 1 }) : entry)
        if (item.restores) {
            const wait = Object.assign({}, familyWait)
            wait[item.family] = now + Reopen.FAMILY_WAIT_MS
            familyWait = wait
        }
        if (placing) placeUntil = Math.max(placeUntil, now + Reopen.PLACE_MS)
        const entry = DesktopEntries.byId(item.app)
        if (!entry) return
        if (nested) console.info("buchhwin-shell: session apps (nested) would start", item.app)
        else LauncherService.launchApp(entry, false)
    }
    function familyOf(key) {
        const info = entryInfo(key)
        return info ? Reopen.restoreKind(info).family : ""
    }

    function addWorkApp(id) { return saveStore(Placement.withWorkApp(store, String(id || ""))) }
    function removeWorkApp(id) { return saveStore(Placement.withoutWorkApp(store, String(id || ""))) }

    // The work apps that are installed and not running yet, started; with
    // none set (Super+Alt+W on a fresh list) Settings > Apps opens instead,
    // unless `quiet` (the login's start). The number started.
    function startWork(quiet) {
        if (!active) return 0
        const installed = workApps.filter(id => entryInfo(id) !== null)
        if (!installed.length) {
            if (quiet !== true) PanelService.open("settings", { page: "apps" })
            return 0
        }
        const open = openCounts()
        const items = installed.filter(id => !(open[id] > 0) && !queue.some(item => item.app === id)).map(id => {
            const kind = Reopen.restoreKind(entryInfo(id))
            return { key: id, app: id, family: kind.family || id, restores: kind.restores, count: 1, launched: 0 }
        })
        enqueue(items)
        return items.length
    }

    // ---- the last session ---------------------------------------------------------------
    property var saved: Reopen.emptyState()
    property bool savedLoaded: false
    // Read only while something needs it: the offer, Settings > Apps, IPC.
    property bool stateAsked: false
    readonly property bool stateWanted: active && (reopenOffer || stateAsked)
    readonly property int savedApps: Reopen.appCount(saved.entries)
    // Read anew after scripts/session-apps.py wrote it: a FileView set to its
    // path at that moment (pitfall 91), not one that read the old file.
    property string stateRead: ""
    onStateWantedChanged: if (stateWanted && !stateRead.length) rereadState()
    Component.onCompleted: if (stateWanted) rereadState()
    function rereadState() {
        stateRead = ""
        Qt.callLater(() => { if (root.stateWanted) root.stateRead = root.statePath })
    }
    FileView {
        id: stateFile
        path: root.stateRead
        printErrors: false
        onLoaded: root.takeState(Reopen.parseState(text()))
        onLoadFailed: root.takeState(Reopen.emptyState())
    }
    function takeState(state) {
        saved = state
        savedLoaded = true
        if (reopenWhenRead) { reopenWhenRead = false; startReopen() }
        if (offerWhenRead) { offerWhenRead = false; offer() }
    }
    property bool reopenWhenRead: false
    property bool offerWhenRead: false

    // Placing: the free places by app ({ key: [place …] }) and until when
    // windows that open are put there.
    property var pending: ({})
    property bool placing: false
    property real placeUntil: 0
    property int placed: 0
    // Windows put in place in this reopen, so a second one leaves them be.
    property var placedAddresses: ({})

    // Reopen the last session's apps. False when there is nothing to reopen
    // (and Settings > Apps opens, which says so).
    function reopen() {
        if (!active) return false
        stateAsked = true
        if (!savedLoaded) { reopenWhenRead = true; return true }
        return startReopen()
    }
    function startReopen() {
        const list = Reopen.groups(saved.entries)
        if (!list.length) {
            PanelService.open("settings", { page: "apps" })
            return false
        }
        pending = Reopen.pendingFrom(list)
        placed = 0
        placedAddresses = ({})
        placing = true
        placeUntil = Date.now() + Reopen.PLACE_MS
        placeTimer.restart()
        // What is open already is placed first - a browser the login started
        // has brought back its windows - and counts against the starts.
        const windows = currentWindows()
        const open = {}
        for (const window of windows) open[window.key] = (open[window.key] || 0) + 1
        for (const window of windows) placeWindow(window.address, window.key, window.cls)
        enqueue(Reopen.launchQueue(list, app => { const info = entryInfo(app); return info ? Reopen.restoreKind(info) : null }, open))
        return true
    }
    function placeWindow(address, key, cls) {
        if (!placing || placedAddresses[address]) return false
        const taken = Reopen.takePlace(pending, [key, "class:" + String(cls || "").toLowerCase()])
        if (!taken) return false
        pending = taken.pending
        placedAddresses[address] = true
        const target = Reopen.targetOf(taken.place, monitors, offsets, HyprlandService.perMonitor,
                                       HyprlandService.focusedMonitorName, screenRects())
        const steps = Reopen.placeCommands(address, target)
        if (steps.length) HyprCompat.dispatchInOrder(steps)
        placed += 1
        if (!Reopen.pendingCount(pending)) stopPlacing()
        return true
    }
    function stopPlacing() {
        placing = false
        pending = ({})
        placeTimer.stop()
    }
    // One single-shot wait, set to what is left of the time each round.
    Timer {
        id: placeTimer
        interval: 1000
        onTriggered: {
            const left = root.placeUntil - Date.now()
            if (left > 0 || root.launching) { interval = Math.max(1000, Math.min(left, 30000)); restart() }
            else root.stopPlacing()
        }
    }
    // A window that opens: a browser's family goes on a moment later (its
    // windows are coming back), and while placing, the window goes to its
    // place.
    Connections {
        target: Hyprland
        enabled: root.placing || root.launching
        function onRawEvent(event) {
            if (event.name !== "openwindow") return
            const info = Reopen.parseOpenWindow(event.data)
            if (!info) return
            const key = root.keyOfWindow(info.cls, info.title)
            const family = root.familyOf(key)
            if (family.length && root.familyWait[family] !== undefined)
                root.familyWait = Reopen.familyArrived(root.familyWait, family, Date.now())
            root.placeWindow(info.address, key, info.cls)
        }
    }

    // ---- keeping a session ----------------------------------------------------------------
    // The shell's half of the snapshot (Reopen.snapshotWindows).
    function snapshotList() {
        const windows = Hyprland.toplevels.values.map(toplevel => {
            const cls = classOf(toplevel)
            const key = keyOfWindow(cls, toplevel.title)
            const monitor = toplevel.monitor ? toplevel.monitor.name
                : toplevel.workspace && toplevel.workspace.monitor ? toplevel.workspace.monitor.name : ""
            return { address: toplevel.address, cls: cls, app: key.indexOf("class:") === 0 ? "" : key,
                     workspace: toplevel.workspace ? toplevel.workspace.id : -1, monitor: monitor }
        })
        return Reopen.snapshotWindows(windows, { monitors: monitors, offsets: offsets, perMonitor: HyprlandService.perMonitor,
                                                 block: block, hidden: Hidden.isHiddenClass })
    }
    // What SessionService runs for a log-out, restart or shut-down while
    // "Offer to reopen apps" is on: the snapshot first (three seconds at
    // most, and whatever it does the action follows), then the action as
    // ever. Null keeps the plain command.
    function endCommand(actionId) {
        if (!active || !reopenOffer || ["logout", "reboot", "poweroff"].indexOf(String(actionId)) < 0) return null
        return ["sh", "-c", "timeout 3 python3 \"$1\" snapshot \"$2\" \"$3\" >/dev/null 2>&1; exec \"$4\" \"$5\"",
                "sh", Paths.script("session-apps.py"), statePath, JSON.stringify(snapshotList()),
                Paths.script("session-action.sh"), String(actionId)]
    }
    // Kept now (IPC), as the end of a session keeps it.
    function snapshotNow() {
        if (!active || helper.running) return false
        stateAsked = true
        helper.command = ["python3", Paths.script("session-apps.py"), "snapshot", statePath, JSON.stringify(snapshotList())]
        helper.running = true
        return true
    }
    function forget() {
        if (!active || helper.running) return false
        stateAsked = true
        helper.command = ["python3", Paths.script("session-apps.py"), "forget", statePath]
        helper.running = true
        return true
    }
    Process {
        id: helper
        stderr: ErrorLog { label: "SessionAppsService.helper" }
        onExited: root.rereadState()
    }

    // ---- the login --------------------------------------------------------------------
    // Once per login, not per shell start: a marker in the runtime directory
    // (emptied when the login ends) named after the compositor's instance,
    // read and written by a FileView - no process for it. It is written at
    // the first start of a login whether or not anything is on, so turning
    // "Start at login" on later and restarting the shell starts nothing
    // until the next login. The work apps and the offer wait for
    // scripts/session-init.sh's wallet step, so they come after the login's
    // one KWallet prompt and not under it.
    readonly property string loginMarker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/buchhwin-shell-session-apps-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none")
    // Asked once: loginChecked is the handler's own guard, not part of
    // loginReady, because a handler that writes what its property's binding
    // reads re-runs that binding inside its own change - "Binding loop
    // detected for property loginReady" at every start of the real session
    // (testing.md pitfall 138).
    property bool loginChecked: false
    readonly property bool loginReady: realSession && SettingsService.loaded && storeLoaded
    onLoginReadyChanged: if (loginReady && !loginChecked) { loginChecked = true; markerFile.path = loginMarker }
    FileView {
        id: markerFile
        printErrors: false
        // There: a shell restart within the login - nothing again.
        onLoadFailed: root.firstStart()
    }
    function firstStart() {
        // Not from inside the FileView's own handler (pitfall 3).
        Qt.callLater(() => markerFile.setText(new Date().toISOString() + "\n"))
        if (workAtLogin || reopenOffer) loginWait.running = true
    }
    Process {
        id: loginWait
        // Up to two minutes; it ends with the shell (Paths.bound).
        command: Paths.bound(["python3", Paths.script("session-apps.py"), "wait-login", Paths.stateDir + "/startup.log"])
        stderr: ErrorLog { label: "SessionAppsService.loginWait" }
        onExited: root.loginWaited()
    }
    // The desktop entries are read in the background after a start; the
    // work apps are looked up in them, so a quick wallet step waits for them
    // a few seconds at most.
    property int entryWaits: 0
    Timer { id: entryWait; interval: 1000; onTriggered: root.loginWaited() }
    function loginWaited() {
        if (!LauncherService.entries.length && entryWaits < 10) {
            entryWaits += 1
            entryWait.start()
            return
        }
        if (workAtLogin) startWork(true)
        if (reopenOffer) {
            stateAsked = true
            if (savedLoaded) offer()
            else offerWhenRead = true
        }
    }

    // ---- the offer ----------------------------------------------------------------------
    // A notification with "Reopen" to the shell's own server, once per kept
    // session (the file is marked as offered as it goes out). notify-send
    // waits for the answer until the notice closes; ten minutes is time
    // enough, and the history keeps the notice after that with its button
    // doing nothing (NetworkService's way), bound to the shell (Paths.bound).
    function offer() {
        if (!realSession || !Reopen.wantsOffer(saved, reopenOffer) || offerNotice.running) return false
        const words = Reopen.offerText(savedApps)
        offerNotice.command = Paths.bound(["timeout", "10m", "notify-send", "--app-name=Session", "--icon=view-restore",
                                           "--action=reopen=Reopen", "--", words.title, words.body])
        offerNotice.running = true
        saved = Object.assign({}, saved, { offered: true })
        Quickshell.execDetached(["python3", Paths.script("session-apps.py"), "mark-offered", statePath])
        return true
    }
    Process {
        id: offerNotice
        stderr: ErrorLog { label: "SessionAppsService.offer" }
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "reopen") root.reopen()
        }
    }

    // ---- IPC ----------------------------------------------------------------------------
    // Counts and flags, never an app's name (shell.qml's `sessionApps get`).
    function describe() {
        return JSON.stringify({
            active: active, rules: rules.length, rulesOn: rulesOn, staleRules: staleRules, dialect: HyprCompat.dialect,
            workApps: workApps.length, workAtLogin: workAtLogin, reopen: reopenOffer,
            saved: savedLoaded ? savedApps : -1, savedWindows: savedLoaded ? saved.entries.length : -1,
            offered: savedLoaded && saved.offered === true, launching: launching, placing: placing,
            pending: Reopen.pendingCount(pending), placed: placed
        })
    }
}
