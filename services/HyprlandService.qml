pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "hypr/HiddenWindows.js" as Hidden
import "hypr/FullscreenLogic.js" as Fullscreen
import "workspaces/WorkspaceLogic.js" as Workspaces
import "overview/OverviewLogic.js" as Overview

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
    //
    // The place comes from that screen, not from the HyprlandMonitor: under
    // Hyprland 0.56 a HyprlandMonitor's x, y, width, height and scale are all
    // 0, refreshMonitors() or not (testing.md pitfall 99; probed again
    // 17.10.: an empty lastIpcObject). With every monitor at 0,0 the order
    // fell back to the names - DP-10, DP-13, DP-8 at the desk instead of
    // DP-8, DP-10, DP-13 left to right - and the blocks of numbers no longer
    // matched the overview's (from `hyprctl monitors`) or the Displays page's.
    // A ShellScreen's x/y are logical, in the same space as Hyprland's.
    readonly property var monitorList: Hyprland.monitors.values
        .map(monitor => Quickshell.screens.find(screen => screen.name === monitor.name))
        .filter(screen => !!screen)
        .map(screen => ({ name: screen.name, x: screen.x, y: screen.y }))
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
    property string appliedRules: ""
    // The highest workspace id a rule was sent for since the last config
    // reload, for taking them back (releaseWorkspaceRules).
    property int ruledUpTo: 0
    function applyWorkspaceRules() {
        if (!perMonitor || !HyprCompat.detected) return
        const order = Workspaces.monitorOrder(monitorList)
        if (!order.length) return
        // The rules only when they say something new: this runs on every
        // workspace that comes or goes now, and the same thirty rules again
        // would be a process for nothing - and building them first, to throw
        // them away, cost 0.4 ms of the GUI thread each time at the desk. A
        // config reload forgets them.
        const ruleKey = order.join(",")
        if (ruleKey !== appliedRules) {
            const rules = []
            for (let index = 0; index < order.length; ++index)
                for (let local = 1; local <= Workspaces.perMonitorBlock; ++local)
                    rules.push(HyprCompat.commands.workspaceRule(Workspaces.globalId(local, index), order[index]))
            appliedRules = ruleKey
            ruledUpTo = Math.max(ruledUpTo, order.length * Workspaces.perMonitorBlock)
            HyprCompat.configure(HyprCompat.commands.combine(rules))
        }
        // A rule binds a workspace when it is *created*, and the compositor
        // creates one per monitor before the shell is up - so after every
        // reboot 3 sat on the second screen and 4 on the third, and the
        // handout called it a transition that "resolves itself". It did not.
        // The ones already in the wrong place are moved, windows and all;
        // that is what the rule would have done a second earlier.
        const placed = Hyprland.workspaces.values.map(workspace => ({
            id: workspace.id, monitor: workspace.monitor ? workspace.monitor.name : "",
            windows: workspace.toplevels.values.length }))
        const moves = Workspaces.misplaced(order, placed)
        const steps = moves.map(move => HyprCompat.commands.moveWorkspaceToMonitor(move.id, move.monitor))
        // And every screen whose view the moves changed - one left showing
        // someone else's (Hyprland fills an emptied monitor with the next
        // free number), one a workspace was moved to - is shown what it
        // should (Workspaces.views), the focus put back where the hand is
        // afterwards.
        const actives = Hyprland.monitors.values
            .filter(monitor => order.indexOf(monitor.name) >= 0)
            .map(monitor => ({ monitor: monitor.name, id: monitor.activeWorkspace ? monitor.activeWorkspace.id : 0 }))
        const views = Workspaces.views(order, placed, actives, moves)
        for (const view of views) {
            steps.push(HyprCompat.commands.focusMonitor(view.monitor))
            steps.push(HyprCompat.commands.workspace(view.id))
        }
        if (views.length && focusedMonitorName.length) steps.push(HyprCompat.commands.focusMonitor(focusedMonitorName))
        HyprCompat.dispatchInOrder(steps)
    }
    onMonitorListChanged: {
        keepMonitors = Math.max(keepMonitors, monitorList.length)
        ruleTimer.restart()
    }
    // A workspace appearing or going is where the strays come from (see
    // `Workspaces.views`), so the check runs then too. Idempotent: with every
    // block in place it sends nothing.
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            if (root.perMonitor) ruleTimer.restart()
            if (root.closing.length) root.closing = root.closing.filter(id => root.workspaces.some(item => item.id === id))
        }
    }
    // Turned off, the rules that were sent are taken back (Lua config; see
    // HyprCommands.releaseWorkspaceRule), or a workspace created later still opens
    // on the monitor its old block named. Turned on again, they are sent
    // anew: `appliedRules` is cleared either way.
    onPerMonitorChanged: {
        if (!perMonitor) releaseWorkspaceRules()
        ruleTimer.restart()
    }
    // A held workspace's `persistent` lives in the same merged rule as its
    // block's monitor, so the release took it along (Lua): the empty held
    // ones went at once and keepEmpty stopped holding them, since keptOn
    // still named them. They are held again in the same request.
    function releaseWorkspaceRules() {
        const ids = Workspaces.ruledIds(ruledUpTo)
        appliedRules = ""
        ruledUpTo = 0
        if (ids.length && HyprCompat.detected && HyprCompat.lua)
            HyprCompat.configure(HyprCompat.commands.releaseRules(ids, keepsEmpty ? keptOn : ({})))
    }
    Connections {
        target: root
        function onConfigReloaded() { root.appliedRules = ""; root.ruledUpTo = 0; ruleTimer.restart() }
    }
    // The rules wait for the dialect, and at login the monitors and the
    // first workspaces have usually settled before the probe answers -
    // nothing else would ask again, and the workspaces stayed scattered.
    Connections {
        target: HyprCompat
        function onDetectedChanged() { if (HyprCompat.detected) ruleTimer.restart() }
    }
    // Monitors arrive one at a time while a dock settles; one batch after they
    // have stopped moving rather than one per monitor.
    //
    // And not while a layout is on its way (DisplayService.layoutPending): a
    // config reload puts every monitor back to the config's rules - auto
    // positions and scales, a lid-shut panel on again - until the saved
    // layout is back, and the blocks planned from that moment moved 1, 3 and
    // 5 with their windows to another screen and back a second later, with
    // an empty 1 left on the first one. Nor during the Displays page's
    // countdown: an arrangement that is reverted moved every block twice for
    // nothing; kept, it moves them once.
    Timer {
        id: ruleTimer
        interval: 400
        onTriggered: {
            if (DisplayService.layoutPending || DisplayService.confirming) restart()
            else root.applyWorkspaceRules()
        }
    }
    Connections {
        target: DisplayService
        function onConfirmingChanged() { if (!DisplayService.confirming) ruleTimer.restart() }
    }

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

    // ---- Empty workspaces held open (workspaces.keepEmpty) ----------------
    //
    // Off, Hyprland forgets an empty workspace the moment no monitor shows it,
    // as it always did. On, the shell holds every workspace open with a
    // `persistent` rule naming the monitor it is on (Workspaces.keepPlan says
    // why it must) until the overview's × closes it (closeWorkspace).
    readonly property bool keepsEmpty: SettingsService.value("workspaces.keepEmpty") === true
    // { id: monitor } the shell sent a rule for since the last config reload.
    // Only these are let go again: a persistent workspace of the user's own
    // config is never touched.
    property var keptOn: ({})
    // Ids the × is closing, held back from keepAll until they are gone.
    property var closing: []
    property bool keepCapped: false
    // The most monitors this session has had: the limit of held workspaces
    // (Workspaces.keepLimit) goes by it. Counted from the monitors of the
    // moment, an undock from the desk with 25 held put the limit at 20 -
    // the runaway warning fired for nothing, and every new workspace on the
    // laptop went again when it was left, the setting on or not.
    property int keepMonitors: 1
    // The monitors of the moment count as well: a change handler does not
    // run for a binding's first value, so monitors already known when this
    // service was made would never have reached keepMonitors.
    function holdLimit() { return Workspaces.keepLimit(Math.max(keepMonitors, monitorList.length)) }
    // Where every workspace is: a new one, one gone or one moved to another
    // monitor is looked at again (a moved one gets its rule anew).
    //
    // Not at once: while monitors come, go or are rearranged, Hyprland makes
    // workspaces in passing (an emptied monitor gets the next free number,
    // a new one its first), and holding those kept them for good - three
    // empty ones on the first screen of the desk before anything was opened,
    // three more after each config reload, one beyond every block. Once the
    // blocks have settled (ruleTimer), the passing ones are gone. A
    // workspace switched to is still held first (focusWorkspace).
    readonly property string keptPlacement: keepsEmpty
        ? workspaces.map(item => item.id + "@" + (item.monitor ? item.monitor.name : "")).join(",") : ""
    onKeptPlacementChanged: if (keepsEmpty) keepSoon.restart()
    Timer {
        id: keepSoon
        interval: 500
        onTriggered: {
            if (ruleTimer.running) restart()
            else root.keepAll()
        }
    }
    // Whether a workspace stays when it is empty and not shown: one the
    // shell holds with the setting on (Workspaces.isKept), else one a
    // persistent rule holds (Hyprland's `ispersistent`, as last read).
    function keeps(workspace) {
        if (!workspace) return false
        const ipc = workspace.lastIpcObject
        return Workspaces.isKept(workspace.id, keepsEmpty, keptOn, closing, !!(ipc && ipc.ispersistent === true))
    }
    function keepAll() {
        if (!keepsEmpty || !HyprCompat.detected) return
        const existing = workspaces.map(item => ({ id: item.id, monitor: item.monitor ? item.monitor.name : "" }))
        const limit = holdLimit()
        const plan = Workspaces.keepPlan(existing, keptOn, closing, perMonitor ? Workspaces.monitorOrder(monitorList) : [], limit)
        const ids = Object.keys(plan).map(Number)
        const held = Object.keys(keptOn).length
        const wanted = held + ids.filter(id => keptOn[id] === undefined).length
        // Warned once per time the limit is reached: below it again (the ×
        // closed some), a second runaway is news again.
        if (keepCapped && wanted < limit) keepCapped = false
        if (!keepCapped && wanted >= limit) {
            keepCapped = true
            console.warn("buchhwin-shell: " + limit + " workspaces held open, holding no more")
        }
        if (!ids.length) return
        keptOn = Object.assign({}, keptOn, plan)
        HyprCompat.configure(HyprCompat.commands.combine(ids.map(id => HyprCompat.commands.keepWorkspaceRule(id, true, plan[id]))))
    }
    function releaseAll() {
        const ids = Object.keys(keptOn).map(Number)
        keptOn = ({})
        closing = []
        keepCapped = false
        if (ids.length && HyprCompat.detected)
            HyprCompat.configure(HyprCompat.commands.combine(ids.map(id => HyprCompat.commands.keepWorkspaceRule(id, false))))
    }
    onKeepsEmptyChanged: keepsEmpty ? keepAll() : releaseAll()
    // A reload forgets the rules, and the empty workspaces they held go with
    // them; sent again, each rule brings its workspace back on its monitor.
    // At once: each names the monitor it was held on, and a reload renames
    // no monitor, so nothing has to wait for the block rules - sent 600 ms
    // later, the held pips went away for that long and the notch's width
    // jumped twice. Sent again after that, in case the first came too early.
    function rehold() {
        const ids = Object.keys(keptOn).map(Number)
        if (!keepsEmpty || !ids.length || !HyprCompat.detected) return
        HyprCompat.configure(HyprCompat.commands.combine(ids.map(id =>
            HyprCompat.commands.keepWorkspaceRule(id, true, keptOn[id]))))
    }
    Connections {
        target: root
        function onConfigReloaded() {
            if (!root.keepsEmpty) return
            root.rehold()
            keepTimer.restart()
        }
    }
    Timer { id: keepTimer; interval: 600; onTriggered: root.rehold() }
    Connections {
        target: HyprCompat
        function onDetectedChanged() { if (HyprCompat.detected && root.keepsEmpty) keepSoon.restart() }
    }

    // The overview's ×: its windows to the workspace before it on its monitor
    // (else the one after), the view too when it is the one shown, and the
    // workspace let go - never a window closed. False for the monitor's only
    // workspace, which has nothing to close into.
    function closeWorkspace(id) {
        const workspace = Hyprland.workspaces.values.find(item => item.id === id)
        if (!workspace || id <= 0) return false
        const monitor = workspace.monitor ? workspace.monitor.name : ""
        const target = Workspaces.closeTarget(workspaces
            .filter(item => (item.monitor ? item.monitor.name : "") === monitor).map(item => item.id), id)
        if (target < 0) return false
        closing = closing.concat([id])
        const left = Object.assign({}, keptOn)
        delete left[id]
        keptOn = left
        const steps = []
        for (const toplevel of workspace.toplevels.values) {
            const address = "0x" + Overview.normalizeAddress(toplevel.address)
            if (/^0x[0-9a-f]+$/.test(address)) steps.push(HyprCompat.commands.moveWindowSilent(target, address))
        }
        if (activeWorkspaceOn(monitor) === id) steps.push(HyprCompat.commands.workspace(target))
        HyprCompat.dispatchInOrder(steps)
        HyprCompat.configure(HyprCompat.commands.keepWorkspaceRule(id, false))
        return true
    }

    // Shown, and held open first when the setting is on: a workspace kept a
    // moment after it was switched to could already be gone again. Held on
    // the monitor it is on, or - a new one - the one its block belongs to,
    // else the focused one; one the blocks are about to move is not held.
    function keepMonitorFor(id) {
        const workspace = workspaces.find(item => item.id === id)
        const order = perMonitor ? Workspaces.monitorOrder(monitorList) : []
        if (workspace) {
            const placed = [{ id: id, monitor: workspace.monitor ? workspace.monitor.name : "" }]
            return Workspaces.misplaced(order, placed).length ? "" : placed[0].monitor
        }
        const index = Workspaces.monitorIndexOf(id)
        return perMonitor && index < order.length ? order[index] : focusedMonitorName
    }
    function focusWorkspace(id) {
        const monitor = keepsEmpty && HyprCompat.detected && id > 0 && keptOn[id] === undefined
            && closing.indexOf(id) < 0 && Object.keys(keptOn).length < holdLimit()
            ? keepMonitorFor(id) : ""
        if (monitor.length) {
            const next = Object.assign({}, keptOn)
            next[id] = monitor
            keptOn = next
            HyprCompat.configure(HyprCompat.commands.withDispatch(HyprCompat.commands.keepWorkspaceRule(id, true, monitor),
                                                                  HyprCompat.commands.workspace(id)))
            return
        }
        HyprCompat.dispatch(HyprCompat.commands.workspace(id))
    }
}
