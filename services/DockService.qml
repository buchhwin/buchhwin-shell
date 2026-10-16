pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.theme
import "dock/DockLogic.js" as Logic
import "model/KeyedLogic.js" as Keyed
import "overview/OverviewLogic.js" as Overview

// The dock's apps and what they do (shell/dock/Dock.qml draws them). Created
// the first time something asks: Dock.qml reads `dock.enabled` from the
// settings itself, so with the dock off nothing reaches this - and once it is
// here, everything that listens or polls is gated on `enabled`.
//
// The apps are the dock's own pins (LayoutService.dockLayout.pins - ids, or
// the session's defaults @files/@terminal/@browser and the shell's @settings)
// and the apps that have windows (Hyprland's toplevels), in DockLogic.build's
// order. The dock draws them through its "apps" widget (shell/widgets/
// AppsWidget.qml), beside whatever else its zones hold.
// Intellihide reads the windows' geometry, which only Hyprland's IPC has:
// `refreshToplevels()` after the events that may move a window over a dock,
// and every second while a floating window - which moves without an event -
// is on a dock's workspace. Off, always or edge-only: no reads at all.
//
// The lock face never reaches this (testing.md pitfall 86): nothing under
// shell/lock/ or theme/ may name it.
Singleton {
    id: root

    readonly property bool enabled: SettingsService.value("dock.enabled") === true
    readonly property string visibility: SettingsService.value("dock.visibility")
    readonly property string position: SettingsService.value("dock.position")
    readonly property string span: SettingsService.value("dock.span")
    readonly property int iconSize: SettingsService.value("dock.iconSize")
    readonly property int margin: SettingsService.value("dock.margin")
    readonly property bool showRunning: SettingsService.value("dock.showRunning") !== false
    // Magnification is movement: Reduced and Off have none.
    readonly property bool magnifies: SettingsService.value("dock.magnification") === true && Animations.motionEnabled
    readonly property bool reserves: visibility === "always"
    readonly property bool intellihide: enabled && visibility === "intellihide"
    readonly property var screenNames: Logic.screensFor(SettingsService.value("dock.screens"),
                                                        Quickshell.screens.map(screen => screen.name))
    readonly property var screens: Quickshell.screens.filter(screen => screenNames.indexOf(screen.name) >= 0)

    // ---- windows ------------------------------------------------------------------
    // When each window was first seen, for an order that does not jump: kept
    // here and handed out in `windows`, assigned when the list changes, never
    // inside the binding that reads it (pitfall 34).
    property var seen: ({})
    property int nextSeq: 1
    // Addresses, the window used last first (activewindowv2).
    property var mru: []

    function addressOf(toplevel) {
        const text = toplevel ? Overview.normalizeAddress(toplevel.address) : ""
        return text.length ? "0x" + text : ""
    }
    function classOf(toplevel) {
        const wayland = toplevel ? toplevel.wayland : null
        if (wayland && wayland.appId) return wayland.appId
        const ipc = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : {}
        return ipc.class || ipc.initialClass || ""
    }
    function syncSeen() {
        if (!enabled) return
        const next = {}
        let seq = nextSeq
        let changed = false
        for (const toplevel of Hyprland.toplevels.values) {
            const address = addressOf(toplevel)
            if (!address.length) continue
            if (seen[address] !== undefined) next[address] = seen[address]
            else { next[address] = seq++; changed = true }
        }
        if (changed || Object.keys(next).length !== Object.keys(seen).length) {
            nextSeq = seq
            seen = next
            mru = mru.filter(address => next[address] !== undefined)
        }
    }
    Connections {
        target: Hyprland.toplevels
        enabled: root.enabled
        function onValuesChanged() { root.syncSeen() }
    }

    // The windows as the apps need them: no geometry here, so a window that
    // moves rebuilds nothing.
    readonly property var windows: enabled ? Hyprland.toplevels.values.map(toplevel => ({
        address: addressOf(toplevel),
        appClass: classOf(toplevel),
        workspace: toplevel.workspace ? toplevel.workspace.id : -1,
        workspaceName: toplevel.workspace ? toplevel.workspace.name : "",
        monitor: toplevel.monitor ? toplevel.monitor.name : "",
        activated: addressOf(toplevel) === activeAddress,
        urgent: toplevel.urgent === true,
        seq: seen[addressOf(toplevel)] || 0
    })).filter(window => window.address.length) : []
    // The window with the focus, from Hyprland's own record: the toplevels'
    // `activated` stayed false for every window in the nested checks, so a
    // click on the active app focused the window it was already on.
    readonly property string activeAddress: enabled && Hyprland.activeToplevel ? addressOf(Hyprland.activeToplevel) : ""

    // ---- apps -----------------------------------------------------------------------
    function pinOf(entry) {
        return { id: entry.id, name: entry.name, icon: entry.icon, startupClass: entry.startupClass }
    }
    // The session's default apps, for @files/@terminal/@browser: read once
    // when a pin asks for them (default-apps.py list), again when Settings >
    // Default apps changes one.
    readonly property var defaultCategories: DefaultAppsService.categories
    readonly property bool needsDefaults: enabled && (LayoutService.dockLayout.pins || []).some(pin => Logic.pinCategory(pin).length > 0)
    onNeedsDefaultsChanged: if (needsDefaults && !defaultCategories.length && !DefaultAppsService.loading) DefaultAppsService.refresh()
    // A stored pin as the entry it stands for now; null when it is not there
    // (an app not installed, a default not read yet).
    function resolvePin(pin) {
        if (pin === "@settings")
            return { id: "shell-settings", name: "Settings", icon: "", startupClass: "", pin: pin, special: "settings", glyph: Icons.settings }
        const id = Logic.pinCategory(pin).length ? Logic.defaultFor(pin, defaultCategories) : pin
        const entry = id.length ? DesktopEntries.byId(id) : null
        if (!entry || entry.noDisplay) return null
        return Object.assign(pinOf(entry), { pin: pin })
    }
    readonly property var pins: enabled
        ? (LayoutService.dockLayout.pins || []).map(pin => resolvePin(pin)).filter(Boolean) : []
    function lookup(cls) {
        const entry = DesktopEntries.heuristicLookup(cls) || DesktopEntries.byId(cls)
            || DesktopEntries.byId(String(cls).toLowerCase())
        return entry ? pinOf(entry) : null
    }
    // What the model was handed last, outside any binding's dependencies: the
    // same objects come back for the apps that did not change, which is the
    // only way Quickshell's ScriptModel matches them right (pitfall 76).
    // A field of a held object, not a property of its own: the binding below
    // reads it, and assigning a property it reads would be a binding loop.
    property var store: ({ items: [] })
    function kept(next) {
        const list = Keyed.keep(store.items, next, "key", { windows: "address" })
        store.items = list
        return list
    }
    readonly property var items: enabled
        // The fields added before the keeping, so a change of them makes a
        // new object and the delegate hears of it.
        ? kept(Logic.build(pins, windows, lookup, { showRunning: showRunning }).map(item => Object.assign(item, {
            // The shell's Settings has no window of its own: it is "running"
            // while its panel is open.
            running: item.special === "settings" ? PanelService.active === "settings" : item.running,
            active: item.special === "settings" ? PanelService.active === "settings" : item.active,
            launching: launching[item.key] !== undefined })))
        : []
    readonly property int pinnedCount: items.filter(item => item.pinned).length
    readonly property int runningCount: items.filter(item => item.running).length

    function itemFor(key) { return items.find(item => item.key === key) || null }
    // A window's title, for the menu: read where it is asked, so the apps
    // themselves never rebuild for a title that changed.
    function titleOf(address) {
        const toplevel = Hyprland.toplevels.values.find(item => addressOf(item) === address)
        return toplevel && toplevel.title ? toplevel.title : ""
    }
    function entryOf(item) { return item && item.entryId && !item.special ? DesktopEntries.byId(item.entryId) : null }

    // ---- intellihide -----------------------------------------------------------------
    // Each dock's body on the screen (global, logical), as Dock.qml reports it.
    property var bodies: ({})
    // The special workspace open on each monitor (activespecial), "" for none.
    property var specials: ({})
    function reportBody(name, rect) {
        if (JSON.stringify(bodies[name] || null) === JSON.stringify(rect || null)) return
        const next = Object.assign({}, bodies)
        if (rect) next[name] = rect
        else delete next[name]
        bodies = next
    }
    function viewFor(screen) {
        const monitor = Hyprland.monitorFor(screen)
        const workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
        return { monitor: screen.name, workspace: workspace, special: specials[screen.name] || "" }
    }
    // The windows with their geometry, while intellihide needs it. Read from
    // `lastIpcObject`, which only `refreshToplevels()` fills.
    readonly property var coverWindows: intellihide ? Hyprland.toplevels.values.map(toplevel => {
        const ipc = toplevel.lastIpcObject || {}
        return {
            appClass: classOf(toplevel),
            monitor: toplevel.monitor ? toplevel.monitor.name : "",
            workspace: toplevel.workspace ? toplevel.workspace.id : -1,
            workspaceName: toplevel.workspace ? toplevel.workspace.name : "",
            at: ipc.at, size: ipc.size, floating: ipc.floating === true,
            hidden: ipc.hidden === true, mapped: ipc.mapped !== false, pinned: ipc.pinned === true
        }
    }) : []
    readonly property var views: intellihide ? screens.map(screen => viewFor(screen)) : []
    readonly property var coveredOn: {
        const result = {}
        for (const view of views) result[view.monitor] = Logic.covered(bodies[view.monitor], coverWindows, view, Metrics.dockCoverSlack)
        return result
    }
    readonly property bool polling: intellihide && Logic.needsPoll(coverWindows, views)
    function covered(name) { return coveredOn[name] === true }

    function refresh() { if (intellihide) Hyprland.refreshToplevels() }
    onIntellihideChanged: if (intellihide) refresh()
    Component.onCompleted: { syncSeen(); refresh() }
    Timer {
        id: refreshTimer
        interval: Animations.dockCoverRefresh
        onTriggered: root.refresh()
    }
    Timer {
        interval: Animations.dockCoverPoll
        repeat: true
        running: root.polling
        onTriggered: root.refresh()
    }
    Connections {
        target: Hyprland
        enabled: root.enabled
        function onRawEvent(event) {
            const name = event.name
            if (name === "activewindowv2") {
                const address = "0x" + Overview.normalizeAddress(String(event.data || "").split(",")[0])
                if (address.length > 2) root.mru = [address].concat(root.mru.filter(item => item !== address)).slice(0, 64)
            } else if (name === "activespecial") {
                // NAME,MONITOR - an empty name: the special workspace closed.
                const parts = String(event.data || "").split(",")
                const monitor = parts.pop()
                const next = Object.assign({}, root.specials)
                next[monitor] = parts.join(",")
                root.specials = next
            }
            if (root.intellihide && Logic.COVER_EVENTS.indexOf(name) >= 0) refreshTimer.restart()
        }
    }

    // ---- what the docks show, per screen ------------------------------------------
    // Shown or not, reported by each dock, for the OSD above it and `get`.
    property var shownOn: ({})
    function reportShown(name, shown) {
        if ((shownOn[name] === true) === shown) return
        const next = Object.assign({}, shownOn)
        next[name] = shown
        shownOn = next
    }
    // How far a shown bottom dock reaches into its screen: the OSD stands
    // above it rather than on it.
    property var reachOn: ({})
    function reportReach(name, reach) {
        if (reachOn[name] === reach) return
        const next = Object.assign({}, reachOn)
        next[name] = reach
        reachOn = next
    }
    function liftFor(name) {
        return enabled && position === "bottom" && shownOn[name] === true ? (reachOn[name] || 0) : 0
    }
    // The apps' places on each screen, for `dock rects` (tests aim with it).
    property var rectsOn: ({})
    function reportRects(name, list) {
        const next = Object.assign({}, rectsOn)
        if (list) next[name] = list
        else delete next[name]
        rectsOn = next
    }
    function forget(name) {
        reportBody(name, null)
        reportRects(name, null)
        reportShown(name, false)
    }

    // Where each dock's surface sits on its screen, for the apps' menu and the
    // panels a dock widget opens (Dock.qml reports it).
    property var originOn: ({})
    function reportOrigin(name, point) {
        const current = originOn[name]
        if (current && current.x === point.x && current.y === point.y) return
        const next = Object.assign({}, originOn)
        next[name] = { x: point.x, y: point.y }
        originOn = next
    }

    // ---- the key and the keyboard ----------------------------------------------------
    // The screen the key showed the dock on, "" for none, and the screen whose
    // dock has the keyboard.
    property string hotkeyScreen: ""
    property string keyboardScreen: ""
    // The app the keys are on (an index into `items`).
    property int keyIndex: 0
    // The menu key on the dock: the apps widget on that screen opens the menu
    // of the app the keys are on.
    signal menuWanted()
    function moveKey(delta) { keyIndex = Math.max(0, Math.min(items.length - 1, keyIndex + delta)) }
    onKeyboardScreenChanged: if (keyboardScreen.length) {
        const active = items.findIndex(item => item.active)
        keyIndex = Math.max(0, active)
    }
    function focusedName() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    }
    // Super+Shift+D: an off dock is switched on, a dock the key showed goes
    // again, any other is shown and takes the keyboard. The key never turns
    // the dock off; that is Settings > Dock. Says what it did.
    function toggleFromKey() {
        if (PanelService.active.length) PanelService.close()
        const target = Logic.revealTarget(focusedName(), screenNames)
        if (!enabled) {
            SettingsService.set("dock.enabled", true)
            hotkeyScreen = target
            return "on"
        }
        if (hotkeyScreen.length && hotkeyScreen === target) {
            conceal()
            return "hidden"
        }
        hotkeyScreen = target
        keyboardScreen = target
        return "shown"
    }
    function reveal(name) {
        hotkeyScreen = name !== undefined ? name : Logic.revealTarget(focusedName(), screenNames)
    }
    function conceal() {
        hotkeyScreen = ""
        keyboardScreen = ""
    }
    function endKeyboard(name) {
        if (name === undefined || keyboardScreen === name) keyboardScreen = ""
        if (name === undefined || hotkeyScreen === name) hotkeyScreen = ""
    }
    // Any panel but the dock's own menu takes the keyboard from the dock.
    Connections {
        target: PanelService
        enabled: root.keyboardScreen.length > 0
        function onActiveChanged() { if (PanelService.active.length && PanelService.active !== "dockMenu") root.endKeyboard() }
    }

    // ---- drag and menu --------------------------------------------------------------
    property string dragKey: ""
    property string dragScreen: ""
    function menuOpenOn(name) {
        return PanelService.active === "dockMenu" && PanelService.args && PanelService.args.onScreen === name
    }

    // ---- what the apps do ----------------------------------------------------------
    // A window to the front. With the keyboard on the dock, after the dock has
    // let it go: Hyprland hands the focus back to a layer that still holds it
    // (the overview's and the switcher's reason, Animations.overviewDispatchDelay).
    property string pendingFocus: ""
    function focusWindow(address) {
        if (!address) return
        if (keyboardScreen.length || PanelService.active === "dockMenu") {
            pendingFocus = address
            endKeyboard()
            if (PanelService.active === "dockMenu") PanelService.close("dockMenu")
            focusTimer.restart()
        } else {
            HyprCompat.dispatch(HyprCompat.commands.focusWindow(address))
        }
    }
    Timer {
        id: focusTimer
        interval: Animations.overviewDispatchDelay
        onTriggered: {
            if (root.pendingFocus.length) HyprCompat.dispatch(HyprCompat.commands.focusWindow(root.pendingFocus))
            root.pendingFocus = ""
        }
    }
    function closeWindow(address) {
        if (address) HyprCompat.dispatch(HyprCompat.commands.closeWindow(address))
    }

    // A click: start it, its window to the front, or the next of its windows.
    function activate(key) {
        const item = itemFor(key)
        if (!item) return false
        const target = Logic.clickTarget(item, activeAddress, mru)
        if (target.action === "launch") return launch(item)
        if (target.action === "focus") focusWindow(target.address)
        else endKeyboard()
        return target.action !== "none"
    }
    function launch(item) {
        if (!item) return false
        endKeyboard()
        if (item.special === "settings") {
            PanelService.open("settings")
            return true
        }
        // A default goes the way its hotkey does (launch-default.sh: the
        // browser's wallet, the terminal's opacity), the rest as the
        // launcher starts them.
        const category = Logic.pinCategory(item.pin)
        if (category.length) {
            Quickshell.execDetached([Paths.script("launch-default.sh"), category])
        } else {
            const entry = entryOf(item)
            if (!entry) return false
            LauncherService.launchApp(entry, true)
        }
        markLaunching(item)
        return true
    }

    // ---- started, not open yet ------------------------------------------------
    // An app the dock started, until a window more than it had shows or a
    // while has passed: its icon breathes meanwhile (DockItem), so a click
    // that takes a second to answer is seen to have been taken.
    property var launching: ({})
    function markLaunching(item) {
        const next = Object.assign({}, launching)
        next[item.key] = { since: Date.now(), before: item.count || 0 }
        launching = next
        launchTimer.start()
    }
    Timer {
        id: launchTimer
        interval: Animations.dockLaunchCheck
        repeat: true
        onTriggered: {
            const now = Date.now()
            const next = {}
            for (const key of Object.keys(root.launching)) {
                const state = root.launching[key]
                const item = root.itemFor(key)
                if (item && !Logic.launchSettled(item.count, state.before, state.since, now, Animations.dockLaunchLimit)) next[key] = state
            }
            if (Object.keys(next).length !== Object.keys(root.launching).length) root.launching = next
            if (!Object.keys(next).length) stop()
        }
    }
    // A middle click or "New window": the entry's own new-window action when
    // it has one (a browser), else the app started again.
    function newWindow(key) {
        const item = itemFor(key)
        if (item && (item.special || Logic.pinCategory(item.pin).length)) return launch(item)
        const entry = entryOf(item)
        if (!entry) return false
        endKeyboard()
        const id = Logic.newWindowAction(entry.actions)
        const action = id.length ? Array.prototype.slice.call(entry.actions).find(candidate => candidate.id === id) : null
        if (action) LauncherService.launchAction(entry, action)
        else LauncherService.launchApp(entry, true)
        markLaunching(item)
        return true
    }
    function runAction(key, actionId) {
        const entry = entryOf(itemFor(key))
        if (!entry) return false
        const action = Array.prototype.slice.call(entry.actions || []).find(candidate => candidate.id === actionId)
        if (!action) return false
        endKeyboard()
        LauncherService.launchAction(entry, action)
        return true
    }
    function closeWindows(key) {
        const item = itemFor(key)
        if (!item) return false
        for (const window of item.windows) closeWindow(window.address)
        return item.windows.length > 0
    }
    // Pinned to the dock (its own list, LayoutService.dockLayout.pins).
    function togglePin(key) {
        const item = itemFor(key)
        if (!item || !item.pin) return false
        if (item.pinned) return LayoutService.dockUnpin(item.pin)
        if (LayoutService.dockPinsFull) return false
        return LayoutService.dockPin(item.pin)
    }
    // A drop among the pins (DockLogic.dropPlan). "full" when they are.
    function drop(key, index) {
        const plan = Logic.dropPlan(itemFor(key), index, LayoutService.dockLayout.pins || [], LayoutService.dockPinLimit)
        if (plan.action === "move" || plan.action === "pin") LayoutService.dockPin(plan.id, plan.index)
        return plan.action
    }

    // An app's menu, a panel of its own (shell/dock/DockMenu.qml), placed
    // beside the icon on the dock's screen.
    function openMenu(key, name, rect) {
        const item = itemFor(key)
        if (!item || !rect) return false
        const args = Object.assign({ key: key, onScreen: name, originX: rect.x, originY: rect.y,
                                     originWidth: rect.width, originHeight: rect.height },
                                   Logic.panelAnchor(position, rect, Metrics.spaceSm))
        PanelService.open("dockMenu", args)
        return true
    }

    // For `dock get`: counts and flags, never a name or a title.
    function describe() {
        return JSON.stringify({
            enabled: enabled, visibility: visibility, position: position, span: span, iconSize: iconSize, margin: margin,
            screens: screens.length, items: items.length, pinned: pinnedCount, running: runningCount,
            windows: windows.length, shown: screens.filter(screen => shownOn[screen.name] === true).length,
            covered: screens.filter(screen => covered(screen.name)).length, polling: polling,
            hotkey: hotkeyScreen.length > 0, keyboard: keyboardScreen.length > 0,
            menuOpen: PanelService.active === "dockMenu", dragging: dragKey.length > 0
        })
    }
    // The apps' places on the screens, for tests: by index, screen-local,
    // with pinned/running flags.
    function describeRects() {
        return JSON.stringify(rectsOn)
    }
}
