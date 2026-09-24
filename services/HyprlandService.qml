pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "hypr/HiddenWindows.js" as Hidden
import "hypr/FullscreenLogic.js" as Fullscreen
import "workspaces/WorkspaceLogic.js" as Workspaces

// Compositor state: focus, fullscreen, games and workspaces.
Singleton {
    id: root
    // Screen sharing (xdg-desktop-portal-hyprland reports "screencast>>1,0").
    property bool screencastActive: false
    // A config reload (file change, `hyprctl reload`) resets every option the
    // shell set at runtime; services re-apply theirs on this signal.
    signal configReloaded()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "screencast") root.screencastActive = String(event.data).split(",")[0] === "1"
            else if (event.name === "configreloaded") root.configReloaded()
        }
    }

    readonly property var activeToplevel: ToplevelManager.activeToplevel
    // Hidden helper windows (HiddenWindows.js) never count as the active window.
    readonly property bool activeHidden: Hidden.isHiddenClass(activeAppId)
    readonly property string activeTitle: activeToplevel && !activeHidden ? (activeToplevel.title || "") : ""
    readonly property string activeAppId: activeToplevel ? (activeToplevel.appId || "") : ""
    // The Wayland fullscreen state of the focused window. Hyprland's workspace
    // `hasfullscreen` is true for the maximized state as well, so it used to
    // report a merely maximized window as fullscreen and silenced every
    // notification popup.
    readonly property bool fullscreenActive: activeToplevel !== null && activeToplevel.fullscreen
    readonly property bool gameActive: /^(steam_app_\d+|gamescope)$/.test(activeAppId)
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var workspaces: Hyprland.workspaces.values.filter(workspace => workspace.id > 0)
        .sort((a, b) => a.id - b.id)

    function workspacesOn(screenName) {
        return workspaces.filter(workspace => workspace.monitor && workspace.monitor.name === screenName)
    }

    // ---- Workspaces per monitor ---------------------------------------------
    //
    // Hyprland keeps one global set and hands each workspace a monitor, so a
    // plain `workspace 3` means "go to whichever screen is holding 3". With
    // three monitors that makes a workspace *be* a monitor. The shell is the
    // only part of the session that knows which monitor has the focus, so the
    // keys come here and the arithmetic is in WorkspaceLogic.
    readonly property bool perMonitor: SettingsService.value("workspaces.perMonitor") === true
    // Name, x and y are all `monitorOrder` needs, and taking only those keeps
    // the value from changing every time a window moves.
    //
    // Only the outputs that are actually on: Hyprland lists a disabled monitor
    // too - the laptop panel with the lid shut is one - and a monitor nobody
    // can see must not take a block of numbers or collect workspace rules.
    // `Quickshell.screens` is the enabled set, and it is what every other
    // per-screen surface in the shell is built from.
    readonly property var monitorList: Hyprland.monitors.values
        .filter(monitor => Quickshell.screens.some(screen => screen.name === monitor.name))
        .map(monitor => ({ name: monitor.name, x: monitor.x, y: monitor.y }))
    readonly property string focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // Which workspace a given screen is showing - not the globally focused one.
    // Three bars comparing against the global focus left two of them with no
    // active pip at all.
    function activeWorkspaceOn(screenName) {
        const monitor = Hyprland.monitors.values.find(item => item.name === screenName)
        return monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    }

    // Where this screen's block of numbers starts. Zero when the setting is
    // off, which is also what a single monitor gets - so one screen behaves
    // exactly as it always did, down to the ids in `hyprctl`.
    function offsetFor(screenName) {
        return perMonitor ? Workspaces.offsetFor(monitorList, screenName) : 0
    }

    // What `Super+N` means: the Nth workspace *of the monitor under the focus*.
    function localToGlobal(localId) {
        if (!perMonitor) return Math.round(Number(localId))
        return Workspaces.globalId(localId, Workspaces.monitorIndex(monitorList, focusedMonitorName))
    }

    // Which monitor each block belongs to, told to the compositor whenever the
    // monitors change. Without it the first undock scatters the blocks and the
    // numbers stop meaning anything; with it a returning monitor takes its own
    // back. The rules are re-emitted after a config reload as well, because
    // that resets everything the shell set at runtime.
    function applyWorkspaceRules() {
        if (!perMonitor || !HyprCompat.detected) return
        const order = Workspaces.monitorOrder(monitorList)
        if (!order.length) return
        const rules = []
        for (let index = 0; index < order.length; ++index)
            for (let local = 1; local <= Workspaces.perMonitorBlock; ++local)
                rules.push(HyprCompat.commands.workspaceRule(Workspaces.globalId(local, index), order[index]))
        HyprCompat.configure(HyprCompat.commands.combine(rules))
        // A rule binds a workspace when it is *created*, and the compositor
        // creates one per monitor before the shell is up - so after every
        // reboot 3 sat on the second screen and 4 on the third, and the
        // handout called it a transition that "resolves itself". It did not.
        // The ones already in the wrong place are moved, windows and all;
        // that is what the rule would have done a second earlier.
        const placed = Hyprland.workspaces.values.map(workspace => ({
            id: workspace.id, monitor: workspace.monitor ? workspace.monitor.name : "" }))
        for (const move of Workspaces.misplaced(order, placed))
            HyprCompat.dispatch(HyprCompat.commands.moveWorkspaceToMonitor(move.id, move.monitor))
    }
    onMonitorListChanged: ruleTimer.restart()
    onPerMonitorChanged: ruleTimer.restart()
    Connections {
        target: root
        function onConfigReloaded() { ruleTimer.restart() }
    }
    // Monitors arrive one at a time while a dock settles; one batch after they
    // have stopped moving rather than one per monitor.
    Timer { id: ruleTimer; interval: 400; onTriggered: root.applyWorkspaceRules() }

    function switchLocal(localId) {
        const id = localToGlobal(localId)
        if (id > 0) focusWorkspace(id)
    }

    function moveLocal(localId) {
        const id = localToGlobal(localId)
        if (id > 0) HyprCompat.dispatch(HyprCompat.commands.moveActiveSilent(id))
    }

    // True while the workspace shown on this screen has a *fullscreen* window -
    // not a maximized one, and not one whose client has already let its
    // fullscreen go. `hasFullscreen` alone answers yes to all three, and the
    // third is why the notch stayed away after leaving a video: a client that
    // releases its own fullscreen leaves the window maximized, so the flag
    // never clears. FullscreenLogic has the measurements.
    //
    // `hasFullscreen` is still the first question, because it is cheap and it
    // is right whenever it says no; the windows are only consulted when it
    // says yes.
    function fullscreenOn(screen) {
        const monitor = screen ? Hyprland.monitorFor(screen) : null
        if (monitor === null || monitor.activeWorkspace === null) return false
        if (!monitor.activeWorkspace.hasFullscreen) return false
        return Fullscreen.hasFullscreenWindow(Hyprland.toplevels.values.map(window),
                                              monitor.activeWorkspace.id)
    }

    // One window, as the two questions that matter: which workspace it is on,
    // and whether it is really fullscreen.
    //
    // The fullscreen state comes from **Wayland**, not from Hyprland's IPC
    // record: `lastIpcObject` is only filled by an explicit `refreshToplevels`
    // and is empty the rest of the time (measured - `toplevels: 1` with an
    // empty record through a whole fullscreen toggle), so reading it answers
    // "no" to everything. The Wayland state is pushed by the client itself,
    // which is precisely the thing being asked about.
    function window(toplevel) {
        const wayland = toplevel ? toplevel.wayland : null
        const workspace = toplevel ? toplevel.workspace : null
        return {
            workspace: workspace ? workspace.id : null,
            fullscreen: wayland !== null && wayland.fullscreen === true
        }
    }

    // What the compositor says about this screen, for `notch get`. A stuck
    // notch is a question about three numbers nobody can see, and a screenshot
    // cannot answer it: how many windows the shell knows about at all, which
    // workspace it is asking about, and the fullscreen mode each window
    // reports. Costs nothing until something asks.
    function fullscreenReport(screen) {
        const monitor = screen ? Hyprland.monitorFor(screen) : null
        const workspace = monitor ? monitor.activeWorkspace : null
        const toplevels = Hyprland.toplevels.values
        return {
            workspace: workspace ? workspace.id : null,
            hasFullscreen: workspace ? workspace.hasFullscreen : null,
            toplevels: toplevels.length,
            modes: toplevels.map(toplevel => window(toplevel)),
            covered: fullscreenOn(screen)
        }
    }

    function focusWorkspace(id) {
        HyprCompat.dispatch(HyprCompat.commands.workspace(id))
    }
}
