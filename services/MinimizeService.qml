pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "dock/MinimizeLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// Minimize and restore, for the dock, the overview, Alt+Tab, Super+H and an
// app's own minimize button (dock/MinimizeLogic.js has the how and the why:
// a minimized window sits on a special workspace named after the workspace it
// came from, and nothing else is stored).
//
// Made at the start (shell.qml asks for it), for two things that cannot wait
// for a first use: windows left minimized by a shell that went - a restart, a
// crash - come back to their workspaces at once, and an app's minimize
// request is heard. Both are Hyprland's own events, which arrive anyway; the
// only process is the one `hyprctl -j clients` of the start. Everything else
// reads Hyprland's toplevels when asked, with no binding of its own.
//
// The lock process never reaches this (testing.md pitfall 86): nothing under
// shell/lock/ may name it, and it does nothing there if something does.
Singleton {
    id: root

    readonly property bool realSession: !LockLogic.lockProcess(Quickshell.shellId)
    // Settings > Dock > Minimize: an app's own minimize button (VS Code's
    // title bar, Citrix's toolbar) minimizes its window. On by default: those
    // buttons did nothing under Hyprland.
    readonly property bool honoursRequests: realSession && SettingsService.value("windows.minimizeRequests") !== false

    // When the shell minimized each window, by address, for Super+Shift+H
    // (the one minimized last comes back first). Kept for the session only:
    // the start brings every window back anyway.
    property var order: ({})
    // The window and the app with the focus as Hyprland's own events say
    // (activewindowv2, activewindow), for an app's request: they arrive in
    // the same stream as the request, in order, which Quickshell's own
    // record of the active window does not promise.
    property string lastActiveAddress: ""
    property string lastActiveClass: ""

    function addressOf(toplevel) {
        return toplevel ? Logic.addressOf(toplevel.address) : ""
    }
    function record(toplevel) {
        if (!toplevel) return null
        const ipc = toplevel.lastIpcObject || {}
        const wayland = toplevel.wayland
        return { address: addressOf(toplevel),
                 appClass: wayland && wayland.appId ? wayland.appId : ipc.class || ipc.initialClass || "",
                 workspace: toplevel.workspace ? toplevel.workspace.id : 0,
                 workspaceName: toplevel.workspace ? toplevel.workspace.name : "",
                 pinned: ipc.pinned === true }
    }
    function toplevelFor(address) {
        const key = Logic.addressOf(address)
        return key.length ? Hyprland.toplevels.values.find(item => addressOf(item) === key) || null : null
    }
    function focusedWorkspace() {
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
    }
    // The minimized windows now, minimized last first.
    function parkedNow() {
        return Logic.parked(Hyprland.toplevels.values.map(record).filter(Boolean), order)
    }
    function isMinimized(address) {
        const window = record(toplevelFor(address))
        return window !== null && Logic.isParked(window.workspaceName)
    }

    // ---- minimize ---------------------------------------------------------------------
    // A window to its special workspace, without the focus: Hyprland gives
    // the focus to the next window on the workspace by itself. False for one
    // that cannot go (MinimizeLogic.canMinimize).
    function minimize(address) {
        const window = record(toplevelFor(address))
        if (!realSession || !window || !Logic.canMinimize(window)) return false
        HyprCompat.dispatch(Logic.minimizeCommand(window.address, Logic.originFor(window)))
        const next = Object.assign({}, order)
        next[window.address] = Date.now()
        order = next
        return true
    }
    // Super+H: the window in front - never one Quickshell only remembers as
    // the last active (MinimizeLogic.inFront).
    function minimizeActive() {
        const window = record(Hyprland.activeToplevel)
        return window !== null && Logic.inFront(window, focusedWorkspace()) && minimize(window.address)
    }

    // ---- restore -------------------------------------------------------------------------
    // A minimized window back to its workspace, and to the front when
    // `focus`. `delay` (ms): a surface that holds the keyboard - the
    // overview, Alt+Tab, the dock with the keys - must let go first, or
    // Hyprland hands the focus back to it; the window moves at once and the
    // focus follows. False for a window that is not minimized.
    function restore(address, focus, delay) {
        const window = record(toplevelFor(address))
        if (!realSession || !window || !Logic.isParked(window.workspaceName)) return false
        const target = Logic.restoreTarget(window, focusedWorkspace())
        forget(window.address)
        const wait = Number(delay) || 0
        if (focus && wait > 0) {
            HyprCompat.dispatchInOrder(Logic.restorePlan(window.address, target, false))
            pendingFocus = window.address
            focusTimer.interval = wait
            focusTimer.restart()
        } else {
            HyprCompat.dispatchInOrder(Logic.restorePlan(window.address, target, focus === true))
        }
        return true
    }
    // Super+Shift+H: the window minimized last.
    function restoreLast() {
        const address = Logic.lastParked(Hyprland.toplevels.values.map(record).filter(Boolean), order)
        return address.length > 0 && restore(address, true, 0)
    }
    // Every minimized window back, none to the front.
    function restoreAll() {
        const plan = Logic.restoreAllPlan(Hyprland.toplevels.values.map(record).filter(Boolean), focusedWorkspace())
        order = ({})
        HyprCompat.dispatchInOrder(plan)
        return plan.length
    }
    function toggle(address) {
        return isMinimized(address) ? restore(address, true, 0) : minimize(address)
    }
    function forget(address) {
        if (order[address] === undefined) return
        const next = Object.assign({}, order)
        delete next[address]
        order = next
    }

    property string pendingFocus: ""
    Timer {
        id: focusTimer
        onTriggered: {
            if (root.pendingFocus.length) HyprCompat.dispatch(HyprCompat.commands.focusWindow(root.pendingFocus))
            root.pendingFocus = ""
        }
    }

    // ---- what Hyprland says ----------------------------------------------------------------
    Connections {
        target: Hyprland
        enabled: root.realSession
        function onRawEvent(event) {
            const name = event.name
            if (name === "activewindowv2") {
                root.lastActiveAddress = Logic.addressOf(String(event.data || "").split(",")[0])
            } else if (name === "activewindow") {
                root.lastActiveClass = String(event.data || "").split(",")[0]
            } else if (name === "minimized") {
                root.request(String(event.data || ""))
            } else if (name === "activespecial") {
                const parked = Logic.openedParked(String(event.data || ""))
                if (parked.length) root.restoreWorkspace(parked)
            }
        }
    }
    // An app asked to be minimized, or to come back (MinimizeLogic.requestAction).
    function request(data) {
        const ask = Logic.parseRequest(data)
        if (!ask) return
        const action = Logic.requestAction(ask, { enabled: honoursRequests, window: record(toplevelFor(ask.address)),
                                                  activeAddress: lastActiveAddress, activeClass: lastActiveClass,
                                                  panelOpen: PanelService.active.length > 0 })
        if (action === "minimize") minimize(ask.address)
        else if (action === "restore") restore(ask.address, true, 0)
    }
    // A minimized window's special workspace opened over a workspace:
    // something focused the window. Its windows go back where they came from,
    // the special workspace closes once it is empty, and the window that took
    // the focus keeps it.
    function restoreWorkspace(name) {
        const windows = Hyprland.toplevels.values.map(record).filter(window => window && window.workspaceName === name)
        if (!windows.length) return
        const front = windows.find(window => window.address === lastActiveAddress) || windows[windows.length - 1]
        const plan = []
        for (const window of windows) {
            forget(window.address)
            plan.push.apply(plan, Logic.restorePlan(window.address, Logic.restoreTarget(window, focusedWorkspace()), false))
        }
        plan.push(HyprCompat.commands.focusWindow(front.address))
        HyprCompat.dispatchInOrder(plan)
    }

    // ---- the start ---------------------------------------------------------------------------
    // Windows a shell before this one minimized: back to their workspaces,
    // none to the front. Asked of Hyprland itself, once - Quickshell's own
    // list of the windows fills in over the first moments, and an answer from
    // the middle of that would leave some behind.
    Component.onCompleted: {
        if (realSession && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) startReader.running = true
    }
    Process {
        id: startReader
        command: ["hyprctl", "-j", "clients"]
        stderr: ErrorLog { label: "MinimizeService.startReader" }
        stdout: StdioCollector {
            onStreamFinished: {
                let clients = []
                try { clients = JSON.parse(text) } catch (error) { return }
                if (!Array.isArray(clients)) return
                const plan = Logic.restoreAllPlan(clients.map(Logic.fromClient), root.focusedWorkspace())
                if (plan.length) {
                    console.info("buchhwin-shell: " + plan.length + " minimized window(s) back to their workspaces")
                    HyprCompat.dispatchInOrder(plan)
                }
            }
        }
    }

    // For `window minimized`: counts and flags, never a title.
    function describe() {
        return JSON.stringify({ minimized: parkedNow().length, honoursRequests: honoursRequests,
                                realSession: realSession })
    }
}
