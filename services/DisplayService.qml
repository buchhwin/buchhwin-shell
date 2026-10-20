pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "display/DisplayLogic.js" as Logic
import "display/ProjectionLogic.js" as Projection
import "lock/LockLogic.js" as LockLogic

// Monitor configuration: edit a draft, apply it as Hyprland monitor rules
// (HyprCompat: keyword or Lua), then keep it within 15 seconds or it reverts
// on its own. Kept settings are stored in ~/.config/buchhwin-shell/monitors.json and applied
// when the shell starts or a monitor is connected. Hyprland's own config files
// are never modified.
Singleton {
    id: root

    property var monitors: []          // live state
    property var draft: []             // edited copy
    property var previous: []          // state before the last apply
    property var saved: null
    property bool savedLoaded: false
    property bool startupApplied: false
    property int countdown: 0
    readonly property int confirmSeconds: 15
    readonly property bool confirming: countdown > 0
    readonly property bool dirty: draft.length > 0 && Logic.changed(monitors, draft)
    // A draft with changes that a refresh could not keep (a monitor came or
    // went): Settings > Displays says they were discarded, until the next
    // change.
    property bool draftDropped: false
    onDirtyChanged: if (dirty) draftDropped = false
    // No apply while anything overlaps: Hyprland keeps explicit positions as
    // given and only warns, with input landing on the wrong screen. The
    // page's moves never produce an overlap (Logic.placeApart), so this only
    // catches a layout edited by hand.
    //
    // At least one screen with a place of its own, and every mirror's source
    // there, on and not a mirror itself: Hyprland refuses a mirror of a
    // mirror and shows a mirror of nothing as a screen of its own. The page
    // offers only sources that can be (Logic.mirrorChoices).
    readonly property bool valid: Logic.shownCount(draft) > 0 && !Logic.overlapping(draft) && Logic.settleMirrors(draft) === draft
    readonly property bool overlapping: Logic.overlapping(draft)
    readonly property var transforms: Logic.TRANSFORMS
    readonly property var vrrModes: Logic.VRR

    // ---- Mirrors and the display switcher ----------------------------------
    //
    // The monitors that show another one's picture now, by name. Hyprland
    // takes a mirror out of its plain monitor list (Quickshell's
    // Hyprland.monitors, which the per-monitor blocks of workspaces are made
    // from) and moves its workspaces to another screen; `mirrorNames` is what
    // the blocks and keepEmpty leave out.
    readonly property var mirrorNames: Projection.mirrorNames(monitors)
    readonly property bool mirroring: mirrorNames.length > 0
    // What the monitors are doing, as the switcher's four choices
    // (ProjectionLogic.current), and which of them can be made now.
    readonly property string currentProjection: Projection.current(monitors, internalName)
    readonly property var projectionChoices: Projection.choices(monitors, internalName, lidClosed)
    // The switcher's choice in force: laid over the saved layout whenever
    // that is applied (a config reload, the lid), until the monitors
    // connected change (`projectionKey`) or another choice is made. Runtime
    // only - Settings > Displays' Keep is what is saved. "" for none.
    property string projection: ""
    property string projectionKey: ""
    // The monitors the choice switched off or made a mirror: what taking it
    // back puts back (ProjectionLogic.undo), until a layout without it has
    // been applied.
    property var projectionTouched: []
    // Where those stood before the choice (ProjectionLogic.placesOf): a
    // screen that stops mirroring goes back there.
    property var projectionPlaces: ({})
    // The projector key pressed again while the switcher is open: it moves
    // to the next choice (DisplaySwitcher).
    signal switcherStepped()
    function stepSwitcher() { switcherStepped() }

    function focusedName() { return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "" }

    // The layout to apply: the saved one over the monitors as they would be
    // without the switcher's choice, with the choice laid over it (when there
    // is one) and the lid's adjustment after both (ProjectionLogic.plan).
    // Null when there is nothing to apply. `mode` overrides the choice in
    // force, for a new one; the plan's `touched` names the monitors it
    // touches.
    function layoutTarget(mode) {
        return Projection.plan(monitors, saved, mode === undefined ? projection : mode,
                               { touched: projectionTouched, places: projectionPlaces },
                               { internalName: internalName, lidClosed: lidClosed, lidKnown: lidKnown, focused: focusedName() })
    }

    // A choice of the switcher (Super+Shift+P, the projector key, IPC
    // `displays setProjection`), applied at once - as Windows' and KDE's
    // are. False when it cannot be made (ProjectionLogic.available) or while
    // Settings > Displays waits for a Keep.
    function setProjection(mode) {
        if (lockProcess || confirming || !monitors.length) return false
        if (!Projection.available(mode, monitors, internalName, lidClosed)) return false
        const plan = layoutTarget(mode)
        if (!plan) return false
        const stays = shownViews(Projection.staying(monitors, plan.target))
        const changes = Logic.changed(monitors, plan.target)
        if (changes && !send(plan.target)) return false
        if (changes) {
            stayViews = stays
            stayExpiry.restart()
        }
        projection = mode
        projectionKey = Projection.setKey(monitors)
        // Kept with what an earlier choice touched until a layout without
        // either has been applied.
        projectionPlaces = Projection.placesOf(monitors, plan.touched, projectionPlaces)
        projectionTouched = projectionTouched.concat(plan.touched.filter(name => projectionTouched.indexOf(name) < 0))
        return true
    }

    // A layout to Hyprland, in the steps it can take it in
    // (ProjectionLogic.steps): the screens that come on first, the whole
    // layout once they are read back on (the monitors' read below). False
    // for a layout with no screen on, which is never sent.
    property var followUp: null
    property var followNames: []
    property string followKey: ""
    function send(layout) {
        const parts = Projection.steps(monitors, layout)
        if (!parts.length) return false
        keepMirrorViews(layout)
        followUp = parts.length > 1 ? parts[1] : null
        followNames = parts.length > 1 ? parts[0].map(entry => entry.name) : []
        followKey = parts.length > 1 ? Projection.setKey(monitors) : ""
        if (followUp) followWait.restart()
        else followWait.stop()
        run(parts[0])
        refreshSoon.restart()
        return true
    }
    // The first step that never came in (a mode the screen refused, a
    // monitor unplugged meanwhile): the rest is not sent - the screens that
    // are on stay on.
    Timer {
        id: followWait
        interval: 3000
        onTriggered: { root.followUp = null; root.followNames = []; root.followKey = "" }
    }

    // The workspace each screen showed when a layout made it a mirror or
    // switched it off, by name ({ id, mirrored }). Hyprland hands a screen
    // that stops mirroring the next free number, which the blocks' rules had
    // all given to the screens left - "Duplicate" then "Extend" brought the
    // screen back on 21, a block of its own with keepEmpty holding it - and
    // one switched on again the lowest number free and ruled to it: with
    // keepEmpty holding its workspaces on the other screen, "Laptop only"
    // then "Extend" brought it back on an empty 12 instead of its 11.
    // HyprlandService shows it this one again (WorkspaceLogic.views) and
    // says so (`mirrorViewsShown`).
    property var mirrorViews: ({})
    // The screens back from mirroring or from being off, with that
    // workspace: read as a mirror or off once and as a screen of their own
    // since. Not before the read that shows it gone - until then the monitor
    // list still holds the screen as it was, and the blocks would have sent
    // it "back" at once.
    readonly property var mirrorReturns: {
        const result = {}
        for (const name of Object.keys(mirrorViews)) {
            const entry = mirrorViews[name]
            if (entry.mirrored && Logic.shown(monitors.find(item => item.name === name) || null)) result[name] = entry.id
        }
        return result
    }
    function keepMirrorViews(layout) {
        const names = Projection.leaving(monitors, layout)
        if (!names.length) return
        const next = Object.assign({}, mirrorViews)
        const shown = shownViews(names)
        for (const name of Object.keys(shown)) next[name] = { id: shown[name], mirrored: false }
        mirrorViews = next
    }
    function mirrorViewsShown(names) {
        const next = Object.assign({}, mirrorViews)
        for (const name of names) delete next[name]
        mirrorViews = next
    }
    // The workspace each screen that stays on showed when a choice of the
    // switcher was sent, by name, until the next pass of the blocks of
    // workspaces (HyprlandService). A screen coming back on takes the
    // workspaces Hyprland last moved off it - one another screen shows
    // among them - and that screen is given a new number: "External only",
    // "Laptop only", then "Extend" took the panel's 1 to the projector and
    // back, and left the panel on a new, empty 2 that keepEmpty held. Such a
    // screen is put back (WorkspaceLogic.stayedViews). Only for a choice
    // that sent something, and never for longer than the layout can take:
    // kept, a workspace switched to later was taken for one the switch had
    // made, and the screen was sent back.
    property var stayViews: ({})
    function stayViewsShown() {
        stayExpiry.stop()
        if (Object.keys(stayViews).length) stayViews = ({})
    }
    Timer { id: stayExpiry; interval: 10000; onTriggered: root.stayViewsShown() }
    // { name: the workspace it shows } for the screens named that show one.
    function shownViews(names) {
        const result = {}
        for (const name of names) {
            const monitor = Hyprland.monitors.values.find(item => item.name === name) || null
            const id = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
            if (id > 0) result[name] = id
        }
        return result
    }

    // The choice ends: the layout without it, at once (the projector
    // unplugged, the lid shut on "Laptop only").
    function dropProjection() {
        if (!projection.length) return
        projection = ""
        projectionKey = ""
    }

    // The lock screen's process (lock.qml) can create this service too - its
    // calendar reaches AppearanceService, whose X11 scale reads `monitors` -
    // and there it only reads. The saved layout and the lid are the shell's:
    // a copy in the lock is never told the lid is shut, so applying the file
    // from there would switch the laptop panel back on behind the shell's
    // back (16.10. review, with the lock's own IdleService).
    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell)

    // Lid "screen off" (Settings > Power): runtime only, never saved - a
    // Keep with the lid shut saves the panel as it is without the lid
    // (Logic.kept), and a saved "off" for it counts only when it was kept
    // with the lid open (Logic.withEntry).
    property bool lidClosed: false
    property bool lidDpms: false          // internal panel switched off with dpms
    property var lidRestore: null         // internal panel before it was disabled
    readonly property string internalName: {
        const forced = Quickshell.env("BUCHHWIN_NESTED") === "1" ? (Quickshell.env("BUCHHWIN_INTERNAL_OUTPUT") || "") : ""
        if (forced.length) return forced
        const panel = monitors.find(item => Logic.isInternal(item.name))
        return panel ? panel.name : ""
    }

    // Whether the lid is known: IdleService's check at start has answered (or
    // failed), a lid switch has been seen, or 3 s have passed (busctl gives
    // up after 2). Until then a startup apply leaves a panel that is off now
    // off (Logic.lidPending), and `lidHeld` says one was held back.
    property bool lidKnown: false
    property bool lidHeld: false
    function lidChecked() {
        if (lockProcess || lidKnown) return
        lidKnown = true
        lidWait.stop()
        if (lidHeld) {
            lidHeld = false
            applySavedIfNeeded()
        }
    }
    Timer { id: lidWait; interval: 3000; running: !root.lockProcess; onTriggered: root.lidChecked() }

    function setLidClosed(closed) {
        if (lockProcess) return
        // A lid event is an answer too. A panel held back while the lid was
        // believed open gets the saved layout again; for a shut lid the
        // plan below decides.
        const held = lidHeld
        lidKnown = true
        lidHeld = false
        lidWait.stop()
        if (closed === lidClosed) {
            if (held) savedDelay.restart()
            return
        }
        lidClosed = closed
        // "Laptop only" behind a shut lid would leave every screen dark: the
        // choice ends, and the layout without it comes back first.
        if (closed && projection === "internal") {
            dropProjection()
            applySavedIfNeeded()
            refreshSoon.restart()
            return
        }
        // A panel the other screens mirror ("Duplicate"): switched off on
        // its own, it took the copies' picture with it and left Hyprland no
        // screen to move the workspaces to. The layout with the lid goes in
        // steps instead (send): the copies become screens of their own
        // first, then the panel goes off.
        if (closed && internalName.length && monitors.some(item => !item.disabled && item.mirror === internalName)) {
            applySavedIfNeeded()
            refreshSoon.restart()
            return
        }
        const name = internalName
        if (!name.length) return
        const panel = monitors.find(item => item.name === name)
        if (closed) {
            const plan = Logic.lidPlan(monitors, name)
            // A panel that is off already (switched off in Settings >
            // Displays) is not the lid's to bring back.
            if (plan === "disable" && panel && !panel.disabled) {
                lidRestore = panel
                run([Object.assign({}, panel, { disabled: true })])
            } else if (plan === "dpms") {
                setPanelPower(false)
            }
        } else {
            // Back at its saved place, or after the other screens
            // (Logic.lidOpenTarget); one kept off stays off, and so does one
            // the switcher's "External only" keeps off - switched on here, it
            // would light up until the saved apply below took it again.
            const back = projection === "external" ? null : Logic.lidOpenTarget(monitors, saved, name, lidRestore)
            if (back) run([back])
            if (lidDpms) setPanelPower(true)
            lidRestore = null
            savedDelay.restart()
        }
        refreshSoon.restart()
    }

    // Only setLidClosed and reassertLid lead here, and neither does anything
    // in the lock process; the guard keeps it that way for a new caller.
    function setPanelPower(on) {
        if (lockProcess) return
        lidDpms = !on
        HyprCompat.dispatch(HyprCompat.commands.dpms(on, internalName))
    }

    // After a global "dpms on" (idle wake) the closed laptop panel stays dark.
    function reassertLid() { if (lidClosed && lidDpms) setPanelPower(false) }

    // A request while hyprctl is running is kept for one more run after it:
    // docking adds two monitors, and the second refresh, dropped, left the
    // snapshot (and applySavedIfNeeded) without the second screen.
    property bool refreshQueued: false
    // A config reload puts every monitor back to the config's rules; the
    // saved layout goes back as soon as the monitors are read again, not
    // 800 ms later (savedDelay stays as the second try) - the workspace
    // blocks were planned from the positions in between.
    property bool reapplyQueued: false
    // A saved layout is on its way (a reload, a monitor plugged in, the lid)
    // or has just been sent and not read back (refreshSoon): HyprlandService
    // plans the workspace blocks after it. Without the second half the
    // blocks were planned 2 ms after the layout was sent, from the old
    // positions.
    // And while Quickshell's monitor list catches up with a mirror that came
    // or went (`mirrorSettle`): Hyprland sends no event for it, and the
    // blocks planned from a list that still holds the mirror would send
    // workspaces to a screen that cannot show them.
    // And while the second step of a layout waits for the first (send).
    readonly property bool layoutPending: savedDelay.running || reapplyQueued || refreshSoon.running || mirrorSettle.running
                                          || followWait.running
    function refresh() {
        if (monitorsProc.running) { refreshQueued = true; return }
        monitorsProc.running = true
    }

    function monitor(name) { return draft.find(item => item.name === name) || null }
    function resolutions(name) { const target = monitor(name); return target ? Logic.resolutions(target) : [] }
    function refreshRates(name) { const target = monitor(name); return target ? Logic.refreshRates(target, target.width, target.height) : [] }
    function scaleChoices(name) { const target = monitor(name); return target ? Logic.scaleChoices(target.scale) : Logic.SCALES }
    function logicalSize(target) { return Logic.logicalSize(target) }
    function snap(name, x, y, threshold) { return Logic.snap(draft, name, x, y, threshold) }

    function edit(name, patch) {
        if (confirming) return
        draft = Logic.update(draft, name, patch)
    }
    // An edit that changes a monitor's size (mode, scale, rotation) or brings
    // one back: its neighbours are pushed clear afterwards (Logic.spread), so
    // a bigger screen never ends up under the next one.
    function resize(name, patch) {
        if (confirming) return
        draft = Logic.spread(Logic.update(draft, name, patch))
    }
    function setResolution(name, value) {
        const target = monitor(name)
        if (!target) return
        const parts = String(value).split("x").map(Number)
        const modes = target.modes.filter(mode => mode.width === parts[0] && mode.height === parts[1])
        if (!modes.length) return
        const sameRate = modes.find(mode => Math.abs(mode.refresh - target.refresh) < 0.5)
        const mode = sameRate || modes[0]
        resize(name, { width: mode.width, height: mode.height, refresh: mode.refresh })
    }
    function setRefresh(name, value) { edit(name, { refresh: Number(value) }) }
    function setScale(name, value) { resize(name, { scale: Number(value) }) }
    function setTransform(name, value) { resize(name, { transform: Number(value) }) }
    function setVrr(name, value) { edit(name, { vrr: Number(value) }) }
    function setPosition(name, x, y) { edit(name, { x: Math.round(x), y: Math.round(y) }) }

    // One arrow-key step, and a neighbour's edge within a step catches it. The
    // threshold *is* the step: "if an edge is closer than one press, land on
    // it" is the rule that makes the last press before an edge line the two up
    // instead of stopping short.
    //
    // It goes through `edit`, so it is refused while the confirmation
    // countdown is running - the same gate the drag respects.
    function nudge(name, dx, dy, step) {
        if (confirming) return
        const next = Logic.nudge(draft, name, dx, dy, step, step)
        if (next) setPosition(name, next.x, next.y)
    }
    function setEnabled(name, value) {
        // A monitor switched off takes its mirrors' source with it: they are
        // screens of their own again (Logic.settleMirrors).
        const next = Logic.settleMirrors(Logic.update(draft, name, { disabled: !value }))
        // A monitor coming back keeps its old place, which may be under a
        // neighbour that moved in the meantime.
        if (Logic.enabledCount(next) > 0 && !confirming) draft = value ? Logic.spread(next) : next
    }
    // Settings > Displays' "Mirror": `source` "" for a screen of its own. A
    // monitor others mirror cannot mirror in turn (Hyprland refuses a
    // mirror of a mirror), so those become screens of their own; one that
    // stops mirroring goes back to its place, or after the others where that
    // is taken.
    function setMirror(name, source) {
        if (confirming || !monitor(name)) return false
        const wanted = String(source || "")
        if (wanted.length && Logic.mirrorChoices(draft, name).indexOf(wanted) < 0) return false
        let next = Logic.settleMirrors(Logic.update(draft, name, { mirror: wanted }))
        if (!wanted.length) next = Projection.placeBack(next, [name])
        draft = next
        return true
    }
    function mirrorChoices(name) { return Logic.mirrorChoices(draft, name) }
    function discard() { if (!confirming) draft = monitors.slice() }

    // The monitors' rules in one request (ProjectionLogic.layoutCommand: a
    // mirror's rule names its source). Everything goes out through `send`,
    // which takes a layout in steps where Hyprland needs them, but for the
    // lid's one panel.
    function run(list) {
        HyprCompat.configure(Projection.layoutCommand(list))
    }

    function apply() {
        if (!dirty || !valid || confirming) return false
        const before = monitors.slice()
        const next = Logic.normalize(draft)
        if (!send(next)) return false
        previous = before
        draft = next
        countdown = confirmSeconds
        countdownTimer.restart()
        return true
    }

    // Merged into the file, so the screens of a desk that is not connected
    // now keep their entries; see Logic.kept for the lid. A repair still
    // waiting was made from the file before this one and would write it
    // back over the Keep.
    function keep() {
        if (!confirming) return false
        countdown = 0
        countdownTimer.stop()
        repaired = null
        repairWrite.stop()
        saved = Logic.kept(saved, draft, internalName, lidClosed, lidRestore)
        savedFile.setText(JSON.stringify(saved, null, 2) + "\n")
        // What was kept is the layout now: a switcher's choice before it
        // (which the page showed and the draft was made from) ends here.
        dropProjection()
        projectionTouched = []
        projectionPlaces = ({})
        // The draft is still in the order it was edited in, and `dirty`
        // compares in the order the monitors are read: a mirror is read at
        // its source's place, and a screen dragged past another comes back
        // after it, so the kept layout read "Unsaved changes" until the next
        // read. One read now hands the draft the monitors' order
        // (Logic.refreshedDraft).
        refresh()
        return true
    }

    function revert() {
        if (!confirming) return false
        countdown = 0
        countdownTimer.stop()
        send(previous)
        draft = previous.slice()
        return true
    }

    function applySavedIfNeeded() {
        if (lockProcess || !savedLoaded) return
        // The switcher's choice lasts while the same monitors are there.
        if (projection.length && projectionKey !== Projection.setKey(monitors)) dropProjection()
        const plan = layoutTarget()
        // Without a choice in force, whatever an earlier one touched is
        // back once this is sent.
        if (!projection.length) { projectionTouched = []; projectionPlaces = ({}) }
        if (!plan) return
        const base = plan.base
        const target = plan.target
        if (plan.held) lidHeld = true
        if (lidClosed && internalName.length) {
            const panel = target.find(item => item.name === internalName)
            const live = monitors.find(item => item.name === internalName)
            // Docked again: remember the panel before disabling it. Last display
            // gone: the panel comes back but stays dark.
            if (panel && panel.disabled && live && !live.disabled) lidRestore = live
            if (panel && !panel.disabled) Qt.callLater(() => root.setPanelPower(false))
        }
        if (Logic.changed(monitors, target)) {
            // After a reload, an output switched off again takes the focus
            // with it (reloadFocus).
            const switchesOff = target.some(item => item.disabled && monitors.some(other => other.name === item.name && !other.disabled))
            if (reloadFocus.length && switchesOff && target.some(item => item.name === reloadFocus && !item.disabled))
                focusBack.restart()
            send(target)
        }
        // A file whose positions had to be spread apart is rewritten with the
        // corrected ones, once, so the next login does not start by
        // correcting it again. From the lid-free layout (the lid's disabling
        // is runtime only), and from a timer rather than from here, which may
        // be running inside the file's own `loaded` handler: one FileView
        // write per turn, or the read is dropped.
        if (saved && !confirming) {
            const corrected = Logic.repairSaved(saved, base, internalName)
            if (corrected) { repaired = corrected; repairWrite.restart() }
        }
    }
    property var repaired: null
    Timer {
        id: repairWrite
        interval: 1500
        onTriggered: {
            if (root.repaired && !root.confirming) {
                root.saved = root.repaired
                savedFile.setText(JSON.stringify(root.saved, null, 2) + "\n")
            }
            root.repaired = null
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1
            if (root.countdown <= 0) {
                root.countdown = 1
                root.revert()
            }
        }
    }

    Timer { id: refreshSoon; interval: 400; onTriggered: root.refresh() }
    // Quickshell's lists answer within a few milliseconds; this is the
    // bound on how long the blocks of workspaces wait for them. And once
    // more at its end: a screen that stops mirroring is made again from the
    // workspace it is given, which may arrive after the first answer, and
    // its active workspace is only filled in by a monitor read after that.
    Timer { id: mirrorSettle; interval: 600; onTriggered: Hyprland.refreshMonitors() }

    Process {
        id: monitorsProc
        stderr: ErrorLog { label: "DisplayService.monitorsProc" }
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = []
                try { parsed = Logic.parseMonitors(text) } catch (error) { return }
                const before = root.monitors
                root.monitors = parsed
                // A mirror came or went. Hyprland tells nobody (setMirror posts
                // no event), so Quickshell's monitor and workspace lists are
                // asked again: the mirror leaves Hyprland.monitors and the
                // per-monitor blocks with it, and a screen that stops
                // mirroring comes back with the workspace it is given.
                if (Projection.mirrorNames(before).join(",") !== Projection.mirrorNames(parsed).join(",")) {
                    Hyprland.refreshWorkspaces()
                    Hyprland.refreshMonitors()
                    mirrorSettle.restart()
                }
                // The rest of a layout sent in steps (send), once the screens
                // the first step brought up are on; with another set of
                // monitors it is not sent at all.
                if (root.followUp && Projection.setKey(parsed) !== root.followKey) {
                    root.followUp = null
                    followWait.stop()
                } else if (root.followUp && Projection.cameUp(parsed, root.followNames)) {
                    const rest = root.followUp
                    root.followUp = null
                    followWait.stop()
                    if (Logic.changed(parsed, rest)) {
                        root.run(rest)
                        refreshSoon.restart()
                    }
                }
                // A screen made a mirror or switched off is read as one
                // (`mirrorReturns`); one unplugged meanwhile has no view to go
                // back to.
                const gone = Object.keys(root.mirrorViews).filter(name => !parsed.some(item => item.name === name))
                if (gone.length) root.mirrorViewsShown(gone)
                const mirroredNow = Object.keys(root.mirrorViews).filter(name => !root.mirrorViews[name].mirrored
                    && parsed.some(item => item.name === name && !Logic.shown(item)))
                if (mirroredNow.length) {
                    const marked = Object.assign({}, root.mirrorViews)
                    for (const name of mirroredNow) marked[name] = { id: marked[name].id, mirrored: true }
                    root.mirrorViews = marked
                }
                // Another set of monitors ends a switcher's choice; a monitor
                // taken away does not bring a saved apply by itself (unless
                // the lid is shut), so the layout without the choice is asked
                // for here - unplugging the projector under "External only"
                // has to bring the panel back, and after an "Extend" that
                // touched nothing a screen the saved layout keeps off goes
                // off again.
                if ((root.projection.length || root.projectionTouched.length) && Projection.setKey(parsed) !== root.projectionKey) {
                    root.dropProjection()
                    savedDelay.restart()
                }
                // Changes not applied yet stay while the same monitors are
                // there (Logic.refreshedDraft): reopening the page, a config
                // reload or a moved shortcut threw them away without a word.
                if (!root.confirming) {
                    const next = Logic.refreshedDraft(before, parsed, root.draft)
                    root.draft = next.draft
                    if (next.dropped) root.draftDropped = true
                }
                if (!root.startupApplied && root.savedLoaded) {
                    root.startupApplied = true
                    root.reapplyQueued = false
                    root.applySavedIfNeeded()
                } else if (root.reapplyQueued && root.startupApplied) {
                    root.reapplyQueued = false
                    root.applySavedIfNeeded()
                }
            }
        }
        onExited: {
            if (!root.refreshQueued) return
            root.refreshQueued = false
            Qt.callLater(root.refresh)
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // A config reload resets monitors to the config rules.
            if (event.name === "configreloaded") {
                root.reloadFocus = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
                root.reapplyQueued = true
                root.refresh()
                savedDelay.restart()
            } else if (event.name === "monitoraddedv2" || event.name === "monitorremovedv2") {
                root.refresh()
                if (event.name === "monitoraddedv2" || root.lidClosed) savedDelay.restart()
            }
        }
    }
    // Also the bound on reapplyQueued: a refresh that fails leaves it set.
    Timer {
        id: savedDelay
        interval: 800
        onTriggered: {
            root.reapplyQueued = false
            root.applySavedIfNeeded()
            if (!focusBack.running) root.reloadFocus = ""
        }
    }

    // The monitor that had the focus when the config reloaded. The reload
    // switches an output the saved layout keeps off (the panel behind a shut
    // lid) on again, the layout switches it off, and Hyprland hands the focus
    // to the first monitor - the keys went to another screen than the one
    // the hand was on. It goes back once the layout is in.
    property string reloadFocus: ""
    Timer {
        id: focusBack
        interval: 400
        onTriggered: {
            const name = root.reloadFocus
            root.reloadFocus = ""
            const now = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            if (name.length && now !== name && root.monitors.some(item => item.name === name && !item.disabled))
                HyprCompat.dispatch(HyprCompat.commands.focusMonitor(name))
        }
    }

    FileView {
        id: savedFile
        path: Paths.configDir + "/monitors.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try { root.saved = JSON.parse(text()) } catch (error) { root.saved = null }
            root.savedLoaded = true
            root.refresh()
        }
        // No file is a file read: the startup apply still runs on the first
        // monitors, because a lid shut at login needs it even without one
        // (Logic.savedTarget). It was marked done here, and when the lid's
        // answer came before the first monitors - it usually does - the
        // panel stayed on behind the shut lid with a workspace on it.
        onLoadFailed: {
            root.savedLoaded = true
            root.refresh()
        }
    }

    // "Identify": every screen shows its own number for a few seconds, so the
    // numbers on the arrangement canvas can be matched to the monitors on the
    // desk. Drawn by shell/displays/IdentifyOverlay.qml.
    readonly property int identifySeconds: 4
    property bool identifying: false

    function identify() {
        identifying = true
        identifyTimer.restart()
    }

    // The number a monitor carries on this page, by name. The overlay is built
    // from `Quickshell.screens` and the draft is sorted by position, so the two
    // are not in the same order - an overlay numbering by its own index would
    // label the screens differently from the page it belongs to.
    function displayNumber(name) {
        const index = draft.findIndex(item => item.name === name)
        return index < 0 ? 0 : index + 1
    }

    Timer {
        id: identifyTimer
        interval: root.identifySeconds * 1000
        onTriggered: root.identifying = false
    }

    Component.onCompleted: refresh()
}
