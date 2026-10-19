pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
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
// could come over a drawn dock or leave it (DockLogic.needsPoll). Off,
// always or edge-only: no reads at all.
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
    // Each dock's running apps are its own screen's (DockLogic.RUNNING_ON),
    // or those of every screen.
    readonly property bool perScreen: SettingsService.value("dock.runningOn") === "screen"
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
    // moves rebuilds nothing - and no focus, which each icon reads for itself
    // (activeOf), so a focus change rebuilds nothing either.
    readonly property var windows: enabled ? Hyprland.toplevels.values.map(toplevel => ({
        address: addressOf(toplevel),
        appClass: classOf(toplevel),
        workspace: toplevel.workspace ? toplevel.workspace.id : -1,
        workspaceName: toplevel.workspace ? toplevel.workspace.name : "",
        monitor: toplevel.monitor ? toplevel.monitor.name : "",
        urgent: toplevel.urgent === true,
        seq: seen[addressOf(toplevel)] || 0
    })).filter(window => window.address.length) : []
    // The window with the focus, from Hyprland's own record: the toplevels'
    // `activated` stayed false for every window in the nested checks, so a
    // click on the active app focused the window it was already on. And only
    // while it is in front (DockLogic.frontAddress): on an empty workspace
    // Hyprland focuses no window, but Quickshell keeps the last one as
    // `activeToplevel` - it drops the empty `activewindowv2` (0.3.2) - so a
    // click on VS Code from an empty workspace was a click on the app in
    // front, with one window: nothing.
    readonly property string activeAddress: {
        const toplevel = enabled ? Hyprland.activeToplevel : null
        if (!toplevel) return ""
        const ipc = toplevel.lastIpcObject || {}
        return Logic.frontAddress({ address: addressOf(toplevel), workspace: toplevel.workspace ? toplevel.workspace.id : 0,
                                    pinned: ipc.pinned === true },
                                  Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)
    }

    // ---- apps -----------------------------------------------------------------------
    // The desktop entries are read in the background after the start, and
    // DesktopEntries.byId() and heuristicLookup() notify no binding of it: a
    // pin resolved before the scan was done stayed missing until the layout
    // changed. Every binding that resolves an entry reads this, which moves
    // once per scan (coalesced: a scan is one step).
    property int entriesRevision: 0
    function entriesChanged() { entriesRevision += 1 }
    Connections {
        target: DesktopEntries.applications
        enabled: root.enabled
        function onValuesChanged() { Qt.callLater(root.entriesChanged) }
    }

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
    // (an app not installed). A default (@files …) that names nothing the
    // dock can draw - not read yet, none set, a hidden helper - keeps its
    // place with its category's glyph (DockLogic.defaultPlaceholder) rather
    // than leaving the dock without a word.
    readonly property var defaultGlyphs: ({ files: Icons.folder, terminal: "󰆍", browser: "󰖟" })
    function resolvePin(pin) {
        if (pin === "@settings")
            return { id: "shell-settings", name: "Settings", icon: "", startupClass: "", pin: pin, special: "settings", glyph: Icons.settingsApp }
        const category = Logic.pinCategory(pin)
        const id = category.length ? Logic.defaultFor(pin, defaultCategories) : pin
        const entry = id.length ? DesktopEntries.byId(id) : null
        if (entry && !entry.noDisplay) return Object.assign(pinOf(entry), { pin: pin })
        return category.length ? Logic.defaultPlaceholder(pin, defaultCategories.length > 0, defaultGlyphs) : null
    }
    readonly property var pins: enabled && entriesRevision >= 0
        ? (LayoutService.dockLayout.pins || []).map(pin => resolvePin(pin)).filter(Boolean) : []
    // Whether an app could be pinned and still be drawn: a hidden entry
    // (NoDisplay) would be stored and then never shown.
    function pinnable(pin) { return String(pin || "").length > 0 && resolvePin(pin) !== null }
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
    // And when nothing changed at all, the list itself (DockLogic.sameObjects):
    // the binding then notifies nobody, and no dock lays its icons out again.
    property var store: ({ items: [], screens: {} })
    function kept(next, name) {
        const previous = name === undefined ? store.items : (store.screens[name] || [])
        const list = Keyed.keep(previous, next, "key", { windows: "address" })
        if (Logic.sameObjects(previous, list)) return previous
        if (name === undefined) store.items = list
        else store.screens[name] = list
        return list
    }
    // One resolver (DockLogic.resolver) for as long as the pins are the same
    // list, held the same way.
    property var resolverStore: ({ pins: null, find: null })
    function resolverFor(list) {
        if (resolverStore.pins !== list || !resolverStore.find) {
            resolverStore.pins = list
            resolverStore.find = Logic.resolver(list, lookup)
        }
        return resolverStore.find
    }
    // The fields added before the keeping, so a change of them makes a new
    // object and the delegate hears of it.
    function decorated(list) {
        return list.map(item => Object.assign(item, {
            pinnable: item.pinned || pinnable(item.pin),
            launching: launching[item.key] !== undefined }))
    }
    readonly property var items: enabled && entriesRevision >= 0
        ? kept(decorated(Logic.build(pins, windows, lookup, { showRunning: showRunning, resolve: resolverFor(pins) })))
        : []
    // Each screen's own apps, while the docks show only their screen's
    // running apps: the pins with the windows they have there, and the apps
    // with a window there. Built only then.
    readonly property var screenItems: {
        if (!enabled || !perScreen || entriesRevision < 0) return ({})
        const result = {}
        const find = resolverFor(pins)
        for (const name of screenNames)
            result[name] = kept(decorated(Logic.build(pins, Logic.windowsOn(windows, name), lookup,
                                                      { showRunning: showRunning, resolve: find })), name)
        return result
    }
    // The apps a dock on that screen shows.
    function itemsOn(name) {
        return perScreen && name && screenItems[name] ? screenItems[name] : items
    }
    readonly property int pinnedCount: items.filter(item => item.pinned).length
    readonly property int runningCount: items.filter(item => runningOf(item)).length

    // The shell's Settings has no window of its own: it is running and in
    // front while its panel is open. Read by each icon for itself, as is
    // which app is in front: a panel opened or closed and a focus change then
    // rebuild no app, and only the icons that change hear of it.
    readonly property bool settingsOpen: enabled && PanelService.active === "settings"
    function runningOf(item) {
        return !!item && (item.special === "settings" ? settingsOpen : item.running === true)
    }
    function activeOf(item) {
        return !!item && (item.special === "settings" ? settingsOpen : Logic.isActive(item, activeAddress))
    }

    // An app by its key: as the dock on `name` shows it (its own windows,
    // when the docks show their own screen's), else as every dock knows it.
    function itemFor(key, name) {
        return itemsOn(name).find(item => item.key === key) || items.find(item => item.key === key) || null
    }
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
            address: addressOf(toplevel),
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
    // Only for a floating window that could come over a drawn dock or leave
    // it (DockLogic.needsPoll): the focused one, one on the dock, one not
    // placed yet.
    readonly property bool polling: intellihide && Logic.needsPoll(coverWindows, views, bodies, activeAddress, Metrics.dockCoverSlack)
    function covered(name) { return coveredOn[name] === true }

    function refresh() { if (intellihide) Hyprland.refreshToplevels() }
    onIntellihideChanged: if (intellihide) { refresh(); seedSpecials() }
    Component.onCompleted: {
        syncSeen()
        refresh()
        if (intellihide) seedSpecials()
    }
    // Switched on again (a profile with the dock, Settings > Dock): what
    // happened meanwhile was not heard. The windows opened while it was off
    // get their place in the order now, in the toplevels' order (close to
    // the order they opened in) - they had none and sorted first, then
    // jumped to the end at the next window -, and the window in front
    // counts as used last. Switched off, it lets the keys and the key's
    // look go: a dock that came back held them at once.
    onEnabledChanged: {
        if (!enabled) {
            conceal()
            return
        }
        syncSeen()
        const front = addressOf(Hyprland.activeToplevel)
        if (front.length) mru = [front].concat(mru.filter(address => address !== front)).slice(0, 64)
    }

    // The special workspaces open when intellihide begins (DockLogic.
    // specialsFrom): read once, merged under what activespecial said since.
    property var freshSpecials: ({})
    function seedSpecials() {
        if (specialsReader.running) return
        freshSpecials = {}
        specialsReader.running = true
    }
    Process {
        id: specialsReader
        command: ["hyprctl", "-j", "monitors"]
        stderr: ErrorLog { label: "DockService.specialsReader" }
        stdout: StdioCollector {
            onStreamFinished: {
                let read = null
                try { read = Logic.specialsFrom(JSON.parse(text)) } catch (error) { return }
                root.specials = Logic.seededSpecials(root.specials, read, root.freshSpecials)
            }
        }
    }
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
                // Newer than a read of the monitors still under way.
                if (specialsReader.running) root.freshSpecials[monitor] = true
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
        if (JSON.stringify(rectsOn[name] || null) === JSON.stringify(list || null)) return
        const next = Object.assign({}, rectsOn)
        if (list) next[name] = list
        else delete next[name]
        rectsOn = next
    }
    // A screen's dock that is gone (the screen unplugged, the dock moved off
    // it, switched off): every report it made goes with it, and so do the
    // keys and a drag on it - a dock made there again later (docked again,
    // switched on again) took the keyboard at once, or stayed shown for a
    // drag that had no end.
    function forget(name) {
        reportBody(name, null)
        reportRects(name, null)
        reportShown(name, false)
        reportPlace(name, null)
        reportOrigin(name, null)
        reportAppsRoom(name, null)
        reportAppsRest(name, null)
        edgePointer(name, false)
        endKeyboard(name)
        endDrag(name)
    }

    // Where each dock's surface sits on its screen, for the apps' menu and the
    // panels a dock widget opens (Dock.qml reports it).
    property var originOn: ({})
    function reportOrigin(name, point) {
        const current = originOn[name]
        if (!point) {
            if (!current) return
            const rest = Object.assign({}, originOn)
            delete rest[name]
            originOn = rest
            return
        }
        if (current && current.x === point.x && current.y === point.y) return
        const next = Object.assign({}, originOn)
        next[name] = { x: point.x, y: point.y }
        originOn = next
    }
    // Each dock's body as drawn at rest, on its screen (screen-local): the
    // panels out of the dock stand a gap off it (DockLogic.panelAnchor).
    property var placeOn: ({})
    function reportPlace(name, rect) {
        if (JSON.stringify(placeOn[name] || null) === JSON.stringify(rect || null)) return
        const next = Object.assign({}, placeOn)
        if (rect) next[name] = rect
        else delete next[name]
        placeOn = next
    }
    function placeOf(name) { return placeOn[name] || null }
    // The room each dock has for its apps along the body (DockLogic.appsRoom),
    // -1 for none: the apps widget fits its icons into it.
    property var appsRoomOn: ({})
    function reportAppsRoom(name, room) {
        if (appsRoomOn[name] === room || (room === null && !(name in appsRoomOn))) return
        const next = Object.assign({}, appsRoomOn)
        if (room === null) delete next[name]
        else next[name] = room
        appsRoomOn = next
    }
    // How long the apps are at rest, unmagnified: the dock reports its body
    // at rest for intellihide and the panels, and only its input mask follows
    // the magnified icons.
    property var appsRestOn: ({})
    function reportAppsRest(name, length) {
        if (appsRestOn[name] === length || (length === null && !(name in appsRestOn))) return
        const next = Object.assign({}, appsRestOn)
        if (length === null) delete next[name]
        else next[name] = length
        appsRestOn = next
    }
    // The pointer at the outer edge of a bar that shares the dock's edge: the
    // dock stands beyond that bar, so its own strip is the bar's inner line,
    // and a pointer pushed to the screen edge lands on the bar. The bar says
    // so here (true while it rests there), and the hidden dock comes as from
    // its own strip.
    property string edgePointerScreen: ""
    function edgePointer(name, on) {
        if (on) edgePointerScreen = name
        else if (edgePointerScreen === name) edgePointerScreen = ""
    }

    // ---- the key and the keyboard ----------------------------------------------------
    // The screen the key showed the dock on, "" for none, and the screen whose
    // dock has the keyboard.
    property string hotkeyScreen: ""
    property string keyboardScreen: ""
    // Where the keys are: an index into the apps of the dock with the
    // keyboard, or an item beside them that opens something - the start
    // button, a taskbar's status, notifications and clock - before the apps
    // (-1, -2 ...) or after them (from the apps' count on): DockLogic.keyRange.
    property int keyIndex: 0
    // The menu key on the dock: the apps widget on that screen opens the menu
    // of the app the keys are on.
    signal menuWanted()
    readonly property var keyItems: itemsOn(keyboardScreen)
    // The items beside the apps on a dock, before and after them along it,
    // from where its pills and its apps reported they are.
    function sidesOn(name) {
        const items = Logic.layoutTypes(LayoutService.dockLayout).map(type => ({ type: type, rect: LayoutService.dockItemRect(name, type) }))
        const apps = (rectsOn[name] || [])[0] || LayoutService.dockItemRect(name, "apps")
        return Logic.keySides(items, apps, Logic.vertical(position), type => WidgetRegistry.actionOf(type).length > 0)
    }
    readonly property var keySides: keyboardScreen.length ? sidesOn(keyboardScreen) : ({ before: [], after: [] })
    readonly property var keyStop: keyboardScreen.length
        ? Logic.keyStop(keyIndex, keyItems.length, keySides.before, keySides.after) : null
    readonly property bool keyOnStart: keyStop !== null && keyStop.kind === "item" && keyStop.type === "start"
    // The item the keys are on beside the apps, "" for none (Dock.qml rings it).
    readonly property string keyItemType: keyStop !== null && keyStop.kind === "item" ? keyStop.type : ""
    function keyRangeNow() { return Logic.keyRange(keyItems.length, keySides.before.length, keySides.after.length) }
    function moveKey(delta) {
        const range = keyRangeNow()
        keyIndex = Math.max(range.low, Math.min(range.high, keyIndex + delta))
    }
    function keyHome() { keyIndex = keyRangeNow().low }
    function keyEnd() { keyIndex = keyRangeNow().high }
    // An app that went (its last window closed), or an item beside them, must
    // not leave the keys nowhere.
    function clampKey() {
        if (!keyboardScreen.length) return
        const range = keyRangeNow()
        if (keyIndex < range.low || keyIndex > range.high) keyIndex = Math.max(range.low, Math.min(range.high, keyIndex))
    }
    onKeyItemsChanged: clampKey()
    onKeySidesChanged: clampKey()
    // A drag whose app went from its dock meanwhile never hears its end
    // (DockLogic.dragLost).
    function checkDrag() {
        if (dragKey.length && Logic.dragLost(dragKey, itemsOn(dragScreen))) endDrag()
    }
    onItemsChanged: {
        checkDrag()
        if (Object.keys(launching).length) Qt.callLater(settleLaunches)
    }
    onScreenItemsChanged: checkDrag()
    onKeyboardScreenChanged: if (keyboardScreen.length) {
        const active = itemsOn(keyboardScreen).findIndex(item => activeOf(item))
        keyIndex = Math.max(0, active)
        // A dock with items but no apps: on the nearest item.
        clampKey()
    }
    function focusedName() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    }
    // An item's panel - the start button's start menu (or the launcher), the
    // status' popups, the clock's dashboard -, opened out of the item the
    // way its click opens it (Pill.qml).
    function openItem(name, type) {
        const rect = LayoutService.dockItemRect(name, type)
        const panel = WidgetRegistry.actionOf(type)
        if (!rect || !panel.length) return false
        const entry = WidgetRegistry.type(type)
        endKeyboard()
        return PanelService.open(panel, Object.assign({ onScreen: name,
            originX: rect.x, originY: rect.y, originWidth: rect.width, originHeight: rect.height },
            Logic.panelAnchor(position, rect, Metrics.dockPanelGap, placeOf(name)), entry && entry.actionArgs ? entry.actionArgs : {}))
    }
    // Super+Shift+D: an off dock is switched on and shown for a moment, a dock
    // the key showed goes again, any other is shown and takes the keyboard -
    // never under a fullscreen window, where it is not drawn (its keys would
    // have waited for the fullscreen to end and then taken the keyboard). The
    // key never turns the dock off; that is Settings > Dock. Says what it did.
    function toggleFromKey() {
        const target = Logic.revealTarget(focusedName(), screenNames)
        const screen = screens.find(item => item.name === target) || null
        const action = Logic.keyAction({ enabled: enabled, target: target, hotkey: hotkeyScreen, peeking: peekTimer.running,
                                         fullscreen: screen !== null && HyprlandService.fullscreenOn(screen) })
        if (action === "fullscreen" || action === "none") return action
        if (PanelService.active.length) PanelService.close()
        if (action === "on") {
            SettingsService.set("dock.enabled", true)
            // Shown while the OSD says so; then it does what its setting says.
            hotkeyScreen = target
            peekTimer.restart()
        } else if (action === "hidden") {
            conceal()
        } else {
            peekTimer.stop()
            hotkeyScreen = target
            keyboardScreen = target
        }
        return action
    }
    Timer {
        id: peekTimer
        interval: Metrics.osdTimeout
        onTriggered: if (!root.keyboardScreen.length) root.hotkeyScreen = ""
    }
    function reveal(name) {
        peekTimer.stop()
        hotkeyScreen = name !== undefined ? name : Logic.revealTarget(focusedName(), screenNames)
    }
    function conceal() {
        peekTimer.stop()
        hotkeyScreen = ""
        keyboardScreen = ""
    }
    function endKeyboard(name) {
        if (name === undefined || keyboardScreen === name) keyboardScreen = ""
        if (name === undefined || hotkeyScreen === name) hotkeyScreen = ""
    }
    // Any panel but the dock's own menu takes the keyboard from the dock.
    // The menu holds the keys for the dock while it is open (`keysWithMenu`:
    // the dock's grab steps aside, Dock.qml), and an Escape in it gives them
    // back (DockLogic.keysAfterPanel).
    property bool keysWithMenu: false
    property bool menuEscaped: false
    function noteMenuEscape() { menuEscaped = true }
    Connections {
        target: PanelService
        enabled: root.keyboardScreen.length > 0 || root.keysWithMenu
        function onActiveChanged() {
            const next = Logic.keysAfterPanel(PanelService.active, root.keysWithMenu, root.menuEscaped)
            if (PanelService.active === "dockMenu") root.menuEscaped = false
            // The keyboard first, then the menu's hold: the dock's grab must
            // not come back for an instant on its way out.
            if (!next.keep) root.endKeyboard()
            root.keysWithMenu = next.withMenu
        }
    }

    // ---- drag and menu --------------------------------------------------------------
    property string dragKey: ""
    property string dragScreen: ""
    // A drag is over without its icon's word: the app went, the dock on that
    // screen (`name`) went.
    function endDrag(name) {
        if (name !== undefined && dragScreen !== name) return
        dragKey = ""
        dragScreen = ""
    }
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

    // A click: start it, its window to the front, or the next of its windows -
    // of those on `name` when the docks show their own screen's.
    function activate(key, name) {
        const item = itemFor(key, name)
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
        // A default that names no app: where one is chosen.
        if (item.special === "choose") {
            PanelService.open("settings", { page: "defaultApps" })
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
    // An app the dock started, until a window more than it had shows, it
    // comes to the front, or a while has passed (DockLogic.launchDone): its
    // icon breathes meanwhile (DockItem), so a click that takes a second to
    // answer is seen to have been taken. Decided when the apps or the window
    // in front change, and at the next deadline - no poll.
    property var launching: ({})
    function markLaunching(item) {
        // Its windows on every screen, as they are counted when it settles:
        // a dock of one screen's apps may know fewer.
        const all = itemFor(item.key) || item
        const next = Object.assign({}, launching)
        next[item.key] = { since: Date.now(), before: all.count || 0, active: activeOf(all) }
        launching = next
        settleLaunches()
    }
    function settleLaunches() {
        const now = Date.now()
        const next = {}
        for (const key of Object.keys(launching)) {
            const state = launching[key]
            const item = itemFor(key)
            if (item && !Logic.launchDone(state, { count: item.count, active: activeOf(item) }, now, Animations.dockLaunchLimit))
                next[key] = state
        }
        if (Object.keys(next).length !== Object.keys(launching).length) launching = next
        const wait = Logic.launchWait(next, now, Animations.dockLaunchLimit)
        if (wait < 0) {
            launchTimer.stop()
        } else {
            launchTimer.interval = Math.max(1, Math.ceil(wait))
            launchTimer.restart()
        }
    }
    onActiveAddressChanged: if (Object.keys(launching).length) Qt.callLater(settleLaunches)
    Timer {
        id: launchTimer
        onTriggered: root.settleLaunches()
    }
    // A middle click or "New window": the entry's own new-window action when
    // it has one (a browser), else the app started again.
    function newWindow(key) {
        const item = itemFor(key)
        if (item && (item.special || Logic.pinCategory(item.pin).length)) return launch(item)
        const entry = entryOf(item)
        if (!entry) return false
        endKeyboard()
        const id = Logic.newWindowAction(entry.actions, entry.command)
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
    // Its windows - those on `name` when the docks show their own screen's.
    function closeWindows(key, name) {
        const item = itemFor(key, name)
        if (!item) return false
        for (const window of item.windows) closeWindow(window.address)
        return item.windows.length > 0
    }
    // Pinned to the dock (its own list, LayoutService.dockLayout.pins).
    function togglePin(key) {
        const item = itemFor(key)
        if (!item || !item.pin) return false
        if (item.pinned) return LayoutService.dockUnpin(item.pin)
        if (LayoutService.dockPinsFull || !pinnable(item.pin)) return false
        return LayoutService.dockPin(item.pin)
    }
    // A drop among the pins (DockLogic.dropPlan). "full" when they are. The
    // slot is counted over the pins the dock shows; the stored list may also
    // hold some it cannot draw (DockLogic.storedSlot).
    function drop(key, slot) {
        const item = itemFor(key)
        if (!item || (!item.pinned && !pinnable(item.pin))) return "none"
        const stored = LayoutService.dockLayout.pins || []
        const index = Logic.storedSlot(slot, pins.map(pin => pin.pin), stored, item.pin)
        const plan = Logic.dropPlan(item, index, stored, LayoutService.dockPinLimit)
        if (plan.action === "move" || plan.action === "pin") LayoutService.dockPin(plan.id, plan.index)
        return plan.action
    }
    // Pulled off the dock (DockLogic.dragOutcome): unpinned, one undo step.
    function unpinByDrag(key) {
        const item = itemFor(key)
        return item && item.pinned ? LayoutService.dockUnpin(item.pin) : false
    }

    // An app's menu, a panel of its own (shell/dock/DockMenu.qml), placed
    // beside the icon on the dock's screen.
    function openMenu(key, name, rect) {
        const item = itemFor(key, name)
        if (!item || !rect) return false
        const args = Object.assign({ key: key, onScreen: name, originX: rect.x, originY: rect.y,
                                     originWidth: rect.width, originHeight: rect.height },
                                   Logic.panelAnchor(position, rect, Metrics.dockPanelGap, placeOf(name)))
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
            menuOpen: PanelService.active === "dockMenu", dragging: dragKey.length > 0,
            perScreen: perScreen, keyOnItem: keyItemType.length > 0
        })
    }
    // The apps' places on the screens, for tests: by index, screen-local,
    // with pinned/running flags.
    function describeRects() {
        return JSON.stringify(rectsOn)
    }
}
