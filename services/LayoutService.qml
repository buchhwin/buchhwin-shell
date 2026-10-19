pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "LayoutLogic.js" as Logic
import "launcher/LauncherCatalogue.js" as LauncherCatalogue
import "profile/ProfileLogic.js" as Profile
import "bar/BarLogic.js" as BarLogic
import "../config/migrations/Migrations.js" as Migrations

// Desktop widget layout (layout.json, schema v3): two levels. A **profile**
// holds its own five **modes** (minimal, work, gaming, laptop, docked), and a
// mode holds a whole desktop - widgets and groups per monitor, which surface it
// shows, the bar, the quick panel, the dashboard and the appearance it wants.
// ProfileLogic defines both words and which settings a mode owns.
//
// "Desktop mode" is a third thing and keeps its own name here: `desktopMode` is
// which surface a mode shows (widgets, bar or notch). It was called `mode`
// until v3, when the thing holding it became a mode itself.
//
// Migrations, undo and read-only protection as before.
Singleton {
    id: root

    property var config: Migrations.emptyConfig()
    // Counts the changes to `config`, for the two readers that act on each
    // one (the editor's selection, Settings > Widgets). Everything else here
    // reads `config` itself, which is a new object with every change - never
    // changed in place - so reading this beside it only ran each of those
    // bindings twice.
    property int revision: 0
    property bool loaded: false
    property bool readOnly: false
    property string readOnlyReason: ""
    // Why layout.json is there but could not be read (its mode, a file root
    // owns, a directory in its place), "" otherwise. That is no fresh layout:
    // read-only like a file from a newer version, so the next change is not
    // written over it; the watch reading it later ends it (SettingsService
    // does the same for settings.json).
    property string unreadableReason: ""
    // A write that fails says so once a start.
    property bool saveFailedWarned: false
    property bool editMode: false
    property var undoStack: []
    property var templates: ({})
    // The five modes every profile has, and the profiles themselves - the
    // first list is fixed (each one has a factory template), the second is the
    // user's.
    readonly property var modeNames: Logic.MODE_NAMES
    readonly property var profileNames: Logic.profileNames(config)
    readonly property string activeProfile: config.activeProfile || Logic.DEFAULT_PROFILE
    readonly property string activeMode: config.activeMode || Logic.MODE_NAMES[0]
    readonly property string activeProfileLabel: Logic.profileLabel(config, activeProfile)
    readonly property string layoutPath: Paths.configDir + "/layout.json"
    // The bounds every grid cell in a layout file is sanitized against. A
    // surface that drags a cell to a size clamps to the same numbers, so the
    // preview stops where the write would have stopped it anyway.
    readonly property int gridMaxColumns: Logic.GRID_MAX_W
    readonly property int gridMaxRows: Logic.GRID_MAX_H

    // Placement geometry reported by the desktop host (screen-relative pixels),
    // used by notification popups to appear below the clock.
    property var placementRects: ({})

    // The active mode of the active profile. A mode that is not in the file
    // yet reads as an empty one rather than as nothing at all.
    function modeConfig() {
        return Logic.modeConfig(config, activeProfile, activeMode)
    }

    // ---- desktop mode and pill bar -----------------------------------------
    readonly property string desktopMode: Logic.desktopModeName(modeConfig().desktopMode)
    readonly property string desktopModeLabel: Logic.desktopModeLabel(desktopMode)
    readonly property var shows: Logic.desktopModeShows(desktopMode)
    readonly property bool widgetsShown: shows.widgets
    readonly property bool barShown: shows.bar
    // Desktop mode "notch": only the notch at the top centre (shell/notch).
    readonly property bool notchShown: shows.notch
    readonly property var bar: modeConfig().bar || Logic.defaultBar()
    readonly property var desktopModes: Logic.DESKTOP_MODES
    readonly property var zones: Logic.ZONES
    // Bottom edge of the pill bar per screen (screen-relative pixels), reported
    // by the bar so panels and popups open below it.
    property var barBottoms: ({})
    property var barEdges: ({})
    // Collapsed notch per screen ({ x, y, width, height }, screen-relative),
    // reported by the notch: panels open centred below it.
    property var notchRects: ({})

    // Exactly one surface at a time; legacy names like "both" are refused (a
    // stored "both" migrates to "pills" when the layout is read).
    function setDesktopMode(name) {
        if (Logic.DESKTOP_MODES.indexOf(name) < 0 || readOnly) return false
        beginChange()
        mutate(mode => { mode.desktopMode = name })
        save()
        return true
    }

    // Apply a pure bar operation, e.g. changeBar(Logic.addPill, "left", "clock").
    function changeBar(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        const after = operation.apply(null, [JSON.parse(JSON.stringify(bar))].concat(args))
        // Nothing changed (a display or a size it has already, an item moved
        // past its end): true as before, but no undo step and no write, as
        // changeDockLayout does.
        if (JSON.stringify(after) === JSON.stringify(bar)) return true
        beginChange()
        mutate(mode => { mode.bar = after })
        save()
        return true
    }

    function barAddPill(zone, type, display) {
        if (!pillTypeAllowed("bar", type)) return false
        return changeBar(Logic.addPill, zone, type, display || defaultDisplay(type))
    }
    function barAddItem(pillId, type, display) {
        if (!pillTypeAllowed("bar", type)) return false
        return changeBar(Logic.addItem, pillId, type, display || defaultDisplay(type))
    }
    function barRemoveItem(pillId, index) { return changeBar(Logic.removeItem, pillId, index) }
    function barMoveItem(pillId, index, delta) { return changeBar(Logic.moveItem, pillId, index, delta) }
    function barSetDisplay(pillId, index, display) { return changeBar(Logic.setItemDisplay, pillId, index, display) }
    // One item can be larger than its neighbours; the bar's own scale is the
    // size of the whole strip.
    function barSetItemSize(pillId, index, size) { return changeBar(Logic.setItemSize, pillId, index, size) }
    function barMovePill(pillId, delta) { return changeBar(Logic.movePill, pillId, delta) }
    function barMovePillTo(pillId, zone, index) { return changeBar(Logic.movePillTo, pillId, zone, index) }
    function barSplitItem(pillId, index) { return changeBar(Logic.splitItem, pillId, index) }
    function barMergeWithNext(pillId) { return changeBar(Logic.mergeWithNext, pillId) }
    function barRemovePill(pillId) { return changeBar(Logic.removePill, pillId) }
    function barPlace(pillId) { return Logic.findPill(bar, pillId) }

    // ---- the dock's zones and pins -------------------------------------------
    // The dock (shell/dock/Dock.qml) is laid out like the bar - zones of pills
    // of widgets - and lives outside the modes like the notch: one dock in all
    // five, kept in a profile's state. Its options are settings (dock.*).
    readonly property var dockLayout: config.dock || Logic.defaultDock()
    // False, with no undo step and no write, when the operation changed
    // nothing: a pin refused (the limit, an id no entry can have), a drag
    // dropped where it started. Every such call used to leave an empty step
    // behind and rewrite layout.json.
    function changeDockLayout(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        const before = Logic.copyDock(dockLayout)
        const after = Logic.copyDock(operation.apply(null, [Logic.copyDock(dockLayout)].concat(args)))
        if (JSON.stringify(after) === JSON.stringify(before)) return false
        beginChange()
        mutate((mode, next) => { next.dock = after })
        save()
        return true
    }
    function dockPin(pin, index) { return changeDockLayout(Logic.dockPinAt, pin, index) }
    function dockUnpin(pin) { return changeDockLayout(Logic.dockUnpin, pin) }
    function dockPinned(pin) { return Logic.dockPinned(dockLayout, pin) }
    // Whether the dock would take this id as a pin at all (LayoutLogic.
    // dockPinName): a menu offers "Pin to dock" switched off for one it would
    // refuse, rather than a row that does nothing.
    function dockPinnable(pin) { return Logic.dockPinName(pin).length > 0 }
    readonly property bool dockHasStart: Logic.dockHasType(dockLayout, "start")
    readonly property int dockPinLimit: Logic.DOCK_PIN_LIMIT
    readonly property bool dockPinsFull: (dockLayout.pins || []).length >= Logic.DOCK_PIN_LIMIT

    // Which surface of pills the layout editor edits: "bar" or "dock". The
    // functions below take it, so the editor's overlay, its inspector and its
    // keys serve both; the bar's own names above stay for everything else.
    property string editTarget: "bar"
    function zonesOf(target) { return target === "dock" ? dockLayout : bar }
    function changeZones(target, operation) {
        const args = Array.prototype.slice.call(arguments, 2)
        if (target === "dock") return changeDockLayout((dock) => Logic.dockZoneOp(dock, operation, args))
        return changeBar.apply(null, [operation].concat(args))
    }
    function pillAdd(target, zone, type, display) {
        if (!pillTypeAllowed(target, type)) return false
        return changeZones(target, Logic.addPill, zone, type, display || defaultDisplay(type))
    }
    function pillAddItem(target, pillId, type, display) {
        if (!pillTypeAllowed(target, type)) return false
        return changeZones(target, Logic.addItem, pillId, type, display || defaultDisplay(type))
    }
    // Whether a widget of this type may go onto the bar or the dock. The
    // dock's own pieces (WidgetRegistry `dockOnly`: its apps, the start
    // button) need the dock around them, and the ones it holds once
    // (`once`) are not added a second time - from the editor's picker, IPC
    // or anywhere else.
    function pillTypeAllowed(target, type) {
        if (target !== "dock") return !WidgetRegistry.isDockOnly(type)
        return !WidgetRegistry.isOnce(type) || !Logic.dockHasType(dockLayout, type)
    }
    function pillRemoveItem(target, pillId, index) { return changeZones(target, Logic.removeItem, pillId, index) }
    function pillMoveItem(target, pillId, index, delta) { return changeZones(target, Logic.moveItem, pillId, index, delta) }
    function pillSetDisplay(target, pillId, index, display) { return changeZones(target, Logic.setItemDisplay, pillId, index, display) }
    function pillSetItemSize(target, pillId, index, size) { return changeZones(target, Logic.setItemSize, pillId, index, size) }
    function pillMove(target, pillId, delta) { return changeZones(target, Logic.movePill, pillId, delta) }
    function pillMoveTo(target, pillId, zone, index) { return changeZones(target, Logic.movePillTo, pillId, zone, index) }
    function pillSplit(target, pillId, index) { return changeZones(target, Logic.splitItem, pillId, index) }
    function pillMerge(target, pillId) { return changeZones(target, Logic.mergeWithNext, pillId) }
    function pillRemove(target, pillId) { return changeZones(target, Logic.removePill, pillId) }
    function pillPlace(target, pillId) { return Logic.findPill(zonesOf(target), pillId) }
    function pillIds(target) { return Logic.barPillIds(zonesOf(target)) }
    // Adds a pill and returns its id, or "" when nothing was added.
    function pillAddId(target, zone, type, display) {
        const before = pillIds(target)
        if (!pillAdd(target, zone, type, display)) return ""
        const added = pillIds(target).filter(id => before.indexOf(id) < 0)
        return added.length ? added[0] : ""
    }

    // ---- dock presets -----------------------------------------------------
    // A whole dock at once: its layout and the options that shape it
    // (LayoutLogic.DOCK_PRESET_OPTIONS). The user's own pins stay; a preset's
    // pins only replace the defaults (LayoutLogic.dockFromPreset). Files in
    // config/dock-presets/, in the picker's order: the taskbar first, then
    // the dock as it was before there were presets.
    //
    // Applying one is a single undo step, the layout and the settings
    // together. The settings go into the step itself (beginChange's
    // `settings`) rather than into undoKeys: every Ctrl+Z would otherwise
    // take back the dock options set in Settings > Dock since. `enable`
    // switches the dock on in the same step (Settings > Dock's cards: choosing
    // a dock is asking for one), and dock.enabled is in the step either way,
    // so undoing a preset that was switched on beside it switches it off.
    readonly property var builtinDockPresetNames: ["taskbar", "dock"]
    property var builtinDockPresets: []
    function dockPreset(id) {
        for (const preset of builtinDockPresets) if (preset.id === id) return preset
        return null
    }
    function applyDockPreset(id, enable) {
        const preset = dockPreset(id)
        if (!preset || readOnly) return false
        const before = { "dock.enabled": SettingsService.value("dock.enabled") }
        for (const key of Logic.DOCK_PRESET_OPTIONS) before["dock." + key] = SettingsService.value("dock." + key)
        beginChange(null, before)
        mutate((mode, next) => { next.dock = Logic.dockFromPreset(next.dock, preset.layout) })
        const values = {}
        for (const key of Object.keys(preset.options)) values["dock." + key] = preset.options[key]
        if (enable === true) values["dock.enabled"] = true
        if (Object.keys(values).length) SettingsService.setAll(values)
        save()
        return true
    }

    // ---- quick settings ---------------------------------------------------
    // The control center's tiles, on the same model as the bar. They are
    // edited inside the control center itself rather than in the layout
    // editor: the editor is a full-screen surface with exclusive keyboard
    // focus, and so is the control center - two of them at once is the trap
    // that keeps Alt+Tab out of the panel system.
    // The notch's two lists. Outside the modes, because the notch is the same
    // in all five - the rest of its options are in settings.json, which
    // cannot hold a list at all (see the note in LayoutLogic). This is the
    // notch in use; each profile keeps its own in its state and puts it back
    // here when it is entered (enterProfile).
    readonly property var notchLayout: config.notch || Logic.defaultNotch()
    property bool notchEditing: false
    // "collapsed" or "expanded": which shape the notch editor is working on.
    property string notchEditZone: "expanded"

    function changeNotchLayout(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        beginChange()
        mutate((mode, next) => {
            next.notch = operation.apply(null, [next.notch || Logic.defaultNotch()].concat(args))
        })
        save()
        return true
    }
    function notchMoveTo(id, zone, index) { return changeNotchLayout(Logic.moveNotchItemTo, id, zone, index) }
    function notchRemove(id) { return changeNotchLayout(Logic.removeNotchItem, id) }
    function notchSetSize(id, w, h) { return changeNotchLayout(Logic.setNotchItemSize, id, w, h) }
    // The size of the notch itself. It lives in settings.json with the rest of
    // the notch's options, so it takes changeNotch's undo step.
    function notchResize(width, height) {
        if (notchEditZone === "collapsed") return changeNotch("notch.collapsedWidth", Math.round(width))
        beginChange()
        // One write: two `set` calls in the same turn of the event loop each
        // replace the file and the first is dropped in flight.
        SettingsService.setAll({ "notch.expandedWidth": Math.round(width),
                                 "notch.expandedHeight": Math.round(height) })
        return true
    }
    function notchAdd(type, zone) {
        if (WidgetRegistry.isDockOnly(type)) return false
        return changeNotchLayout(Logic.addNotchItem, type, zone)
    }
    function notchResetLayout() { return changeNotchLayout(() => Logic.defaultNotch()) }

    // ---- notch presets ----------------------------------------------------
    // A whole notch at once: both lists and the options that shape it. The
    // built-in ones are files in config/notch-presets/, the user's own live in
    // the layout file next to the notch. Applying one is a single undo step,
    // the layout and the settings together.
    // In the picker's order. Classic is the notch as it was before Island:
    // the time alone, the overview of five on hover.
    readonly property var builtinNotchPresetNames: ["island", "classic"]
    property var builtinNotchPresets: []
    readonly property var notchPresets: builtinNotchPresets.concat(config.notchPresets || [])
    function notchPreset(id) {
        for (const preset of notchPresets) if (preset.id === id) return preset
        return null
    }
    function applyNotchPreset(id) {
        const preset = notchPreset(id)
        if (!preset || readOnly) return false
        beginChange()
        mutate((mode, next) => { next.notch = Logic.copyNotch(preset.layout) })
        const values = {}
        for (const key of Object.keys(preset.options)) values["notch." + key] = preset.options[key]
        if (Object.keys(values).length) SettingsService.setAll(values)
        save()
        return true
    }
    // The notch as it is now, under a name of the user's choosing.
    function saveNotchPreset(label) {
        if (readOnly) return ""
        const options = {}
        for (const key of Logic.NOTCH_PRESET_OPTIONS) options[key] = SettingsService.value("notch." + key)
        const result = Logic.addNotchPreset(config, label, notchLayout, options,
                                            builtinNotchPresets.map(preset => preset.id))
        if (!result.id.length) return ""
        config = Logic.sanitize(result.config)
        revision++
        save()
        return result.id
    }
    function renameNotchPreset(id, label) {
        if (readOnly) return false
        config = Logic.sanitize(Logic.renameNotchPreset(config, id, label))
        revision++
        return save()
    }
    function removeNotchPreset(id) {
        if (readOnly) return false
        config = Logic.sanitize(Logic.removeNotchPreset(config, id))
        revision++
        return save()
    }

    // The lock screen's grid. Outside the modes like the notch (and kept in a
    // profile's state like it): there is one lock screen whatever the desktop
    // mode says about monitors. The lock screen itself is another process and
    // only ever reads this file; it is arranged in Settings, on a preview,
    // because editing a surface whose whole job is to be modal is a trap.
    readonly property var lockLayout: config.lock || Logic.defaultLock()
    readonly property var lockTypes: Logic.lockTypes(lockLayout)
    readonly property var lockItems: Logic.lockItems(lockLayout)
    property bool lockEditing: false

    function changeLockLayout(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        beginChange()
        mutate((mode, next) => {
            next.lock = operation.apply(null, [next.lock || Logic.defaultLock()].concat(args))
        })
        save()
        return true
    }
    function lockMoveTo(id, index) { return changeLockLayout(Logic.moveLockItemTo, id, index) }
    function lockRemove(id) { return changeLockLayout(Logic.removeLockItem, id) }
    function lockSetSize(id, w, h) { return changeLockLayout(Logic.setLockItemSize, id, w, h) }
    function lockAdd(type) { return changeLockLayout(Logic.addLockItem, type) }
    function lockResetLayout() { return changeLockLayout(() => Logic.defaultLock()) }

    readonly property var quick: modeConfig().quick || Logic.defaultQuick()
    readonly property var quickTypes: Logic.quickTypes(quick)
    readonly property var quickItems: Logic.quickItems(quick)
    property bool quickEditing: false

    function changeQuick(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        beginChange()
        mutate(mode => { mode.quick = operation.apply(null, [mode.quick || Logic.defaultQuick()].concat(args)) })
        save()
        return true
    }

    function quickMoveTo(tileId, index) { return changeQuick(Logic.moveQuickTileTo, tileId, index) }
    function quickSetSize(tileId, w, h) { return changeQuick(Logic.setQuickTileSize, tileId, w, h) }
    function quickRemove(tileId) { return changeQuick(Logic.removeQuickTile, tileId) }
    function quickAdd(type) {
        if (WidgetRegistry.isDockOnly(type)) return false
        return changeQuick(Logic.addQuickTile, type, isKnownType)
    }
    function quickReset() { return changeQuick(() => Logic.defaultQuick()) }

    // ---- the dashboard ------------------------------------------------------
    // The same surface as the control center's tiles, with its own catalogue:
    // one zone, one card per pill, each carrying its own grid size.
    readonly property var dashboard: modeConfig().dashboard || Logic.defaultDashboard()
    readonly property var dashboardTypes: Logic.dashboardTypes(dashboard)
    readonly property var dashboardItems: Logic.dashboardItems(dashboard)
    property bool dashboardEditing: false

    function changeDashboard(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        beginChange()
        mutate(mode => { mode.dashboard = operation.apply(null, [mode.dashboard || Logic.defaultDashboard()].concat(args)) })
        save()
        return true
    }

    function dashboardMoveTo(cardId, index) { return changeDashboard(Logic.moveDashboardCardTo, cardId, index) }
    function dashboardSetSize(cardId, w, h) { return changeDashboard(Logic.setDashboardCardSize, cardId, w, h) }
    function dashboardRemove(cardId) { return changeDashboard(Logic.removeDashboardCard, cardId) }
    function dashboardAdd(type) {
        if (WidgetRegistry.isDockOnly(type)) return false
        return changeDashboard(Logic.addDashboardCard, type, isKnownType)
    }
    function dashboardReset() { return changeDashboard(() => Logic.defaultDashboard()) }

    // ---- the launcher -------------------------------------------------------
    // The same surface as the control center's tiles and the dashboard's
    // cards, with its own catalogue: one zone, one block per pill, each
    // carrying its own size in a grid of four columns and eight rows. The
    // difference is that a row is an eighth of the card rather than a fixed
    // height, so the result list reaches the bottom of whatever size the
    // window was dragged to - see `LauncherCatalogue`.
    readonly property var launcher: modeConfig().launcher || Logic.defaultLauncher()
    readonly property var launcherTypes: Logic.launcherTypes(launcher)
    readonly property var launcherItems: Logic.launcherItems(launcher)
    property bool launcherEditing: false

    function changeLauncher(operation) {
        if (readOnly) return false
        const args = Array.prototype.slice.call(arguments, 1)
        beginChange()
        mutate(mode => { mode.launcher = operation.apply(null, [mode.launcher || Logic.defaultLauncher()].concat(args)) })
        save()
        return true
    }

    function launcherMoveTo(id, index) { return changeLauncher(Logic.moveLauncherBlockTo, id, index) }
    function launcherSetSize(id, w, h) { return changeLauncher(Logic.setLauncherBlockSize, id, w, h) }
    function launcherRemove(id) { return changeLauncher(Logic.removeLauncherBlock, id) }
    function launcherAdd(type) { return changeLauncher(Logic.addLauncherBlock, type) }
    function launcherReset() { return changeLauncher(() => Logic.defaultLauncher()) }

    function launcherLabel(type) { return LauncherCatalogue.label(type) }
    function launcherMinSize(type) { return Logic.launcherBlockMinSize(type) }
    // What the picker offers - the blocks that are not on the launcher. No
    // widgets here, unlike the dashboard: a search surface is at heart its
    // result list, and a grid of widgets on one is a result list two rows high.
    function launcherChoices() { return LauncherCatalogue.missing(launcherTypes) }

    // Its own size, the way the control center keeps its own.
    function dashboardResize(width, height) {
        if (readOnly) return false
        const w = Math.round(width)
        const h = Math.round(height)
        if (SettingsService.value("desktop.dashboardWidth") === w
                && SettingsService.value("desktop.dashboardHeight") === h) return false
        beginChange()
        SettingsService.setAll({ "desktop.dashboardWidth": w, "desktop.dashboardHeight": h })
        return true
    }

    // The panel's own size. It lives in settings.json rather than in the
    // layout file, so it takes an undo step of its own the way the notch's
    // size does - the Undo button sits in the very same row as the grip, and
    // it used to be the one thing in the arrange mode it could not reach.
    //
    // It writes nothing when nothing changed: the grip seeded its drag from
    // the card as it was clamped at that moment, so on a narrower screen one
    // click on it silently rewrote the stored size down to what fitted.
    function quickResize(width, height) {
        if (readOnly) return false
        const w = Math.round(width)
        const h = Math.round(height)
        if (SettingsService.value("desktop.quickWidth") === w
                && SettingsService.value("desktop.quickHeight") === h) return false
        beginChange()
        SettingsService.setAll({ "desktop.quickWidth": w, "desktop.quickHeight": h })
        return true
    }

    // Adds a pill and returns its id, or "" when nothing was added.
    function barAddPillId(zone, type, display) {
        if (!barAddPill(zone, type, display)) return ""
        const list = bar[zone] || []
        return list.length ? list[list.length - 1].id : ""
    }

    function defaultDisplay(type) {
        const entry = WidgetRegistry.type(type)
        return entry && entry.pillDisplay ? entry.pillDisplay : "full"
    }

    // Options of the bar itself; "style", "position" and "edge" only take
    // known values.
    function setBarOption(key, value) {
        if (["reserve", "fullscreen", "scale", "style", "position", "edge",
             "panelSpot", "notificationSpot"].indexOf(key) < 0 || readOnly) return false
        if ((key === "panelSpot" || key === "notificationSpot") && BarLogic.SPOTS.indexOf(value) < 0) return false
        if (key === "style" && BarLogic.STYLES.indexOf(value) < 0) return false
        if (key === "position" && BarLogic.POSITIONS.indexOf(value) < 0) return false
        if (key === "edge" && BarLogic.EDGES.indexOf(value) < 0) return false
        if (key === "fullscreen" && Logic.FULLSCREEN.indexOf(value) < 0) return false
        // The value it has already: no undo step that undoes nothing, no write.
        if (JSON.stringify(bar[key]) === JSON.stringify(value)) return true
        beginChange()
        mutate(mode => {
            const next = JSON.parse(JSON.stringify(mode.bar || Logic.defaultBar()))
            next[key] = value
            mode.bar = next
        })
        save()
        return true
    }

    // Which screens carry the bar. Its own function rather than a case in
    // `setBarOption`, which validates scalars by value; this one is a list and
    // an empty list is the meaningful default ("every screen").
    //
    // A caller that names every screen there is gets an empty list stored, so
    // the answer stays "all" when the next monitor arrives instead of quietly
    // excluding it.
    function setBarScreens(names, allNames) {
        if (readOnly) return false
        const wanted = (Array.isArray(names) ? names : [])
            .filter(name => typeof name === "string" && name.length)
        const all = Array.isArray(allNames) ? allNames : []
        const covers = all.length > 0 && all.every(name => wanted.indexOf(name) >= 0)
        return changeBar(bar => {
            const next = JSON.parse(JSON.stringify(bar))
            next.screens = covers ? [] : wanted
            return next
        })
    }

    function resetBar() {
        const template = templates[activeMode]
        return changeBar(() => Logic.sanitizeBar(template && template.bar ? template.bar : null))
    }

    // How far into the screen the bar reaches on a screen, and from which
    // edge. The two travel together: a caller that only had the number had to
    // assume it came from the top, which was true only while that was the
    // only edge there was.
    function reportBarInset(screenName, inset, edge) {
        if (barBottoms[screenName] === inset && barEdges[screenName] === edge) return
        const next = Object.assign({}, barBottoms)
        next[screenName] = inset
        barBottoms = next
        const edges = Object.assign({}, barEdges)
        edges[screenName] = edge
        barEdges = edges
    }

    // Where a widget type sits on the bar, by screen. Unlike `surfaceRects`
    // this is reported the whole time the bar is up, because it is what tells
    // a notification and an OSD where to come from - and a thing that appears
    // on its own cannot wait for the editor to be opened first. Keyed by type
    // rather than by pill, because that is the question being asked: "where is
    // the volume widget", not "which pill holds it".
    property var barItemRects: ({})
    function reportBarItemRect(screenName, type, rect) {
        const key = screenName + "/" + type
        const current = barItemRects[key] || null
        if (JSON.stringify(current) === JSON.stringify(rect)) return
        const next = Object.assign({}, barItemRects)
        if (rect === null) delete next[key]
        else next[key] = rect
        barItemRects = next
    }

    function barItemRect(screenName, type) {
        if (!barShown) return null
        return barItemRects[screenName + "/" + type] || null
    }

    // The same for a widget on the dock: every item on it reports
    // (Pill.reportRects), so the start menu and a panel opened by a key can
    // come out of the item a click would have used. A pill takes back only
    // what it reported itself, so two items of one type no longer wipe each
    // other's report; the last report wins.
    property var dockItemRects: ({})
    function reportDockItemRect(screenName, type, rect) {
        const key = screenName + "/" + type
        if (JSON.stringify(dockItemRects[key] || null) === JSON.stringify(rect)) return
        const next = Object.assign({}, dockItemRects)
        if (rect === null) delete next[key]
        else next[key] = rect
        dockItemRects = next
    }
    function dockItemRect(screenName, type) {
        return dockItemRects[screenName + "/" + type] || null
    }

    function reportNotchRect(screenName, rect) {
        const current = notchRects[screenName] || null
        if (JSON.stringify(current) === JSON.stringify(rect)) return
        const next = Object.assign({}, notchRects)
        next[screenName] = rect
        notchRects = next
    }

    function notchRect(screenName) {
        if (!notchShown) return null
        return notchRects[screenName] || null
    }

    // How far the bar (or the notch) reaches into a screen from its own edge,
    // or -1. `barEdge` says which edge that is; a notch is always at the top.
    function barBottom(screenName) {
        if (notchShown) {
            const rect = notchRect(screenName)
            return rect ? rect.y + rect.height : -1
        }
        if (!barShown) return -1
        const value = barBottoms[screenName]
        return value === undefined ? -1 : value
    }

    function barEdge(screenName) {
        if (notchShown || !barShown) return "top"
        return barEdges[screenName] || "top"
    }

    // Where a panel and where a notification open along the bar. Only in bar
    // mode: in notch mode they come out of the notch, which is what a notch is
    // for, and in widgets mode there is no bar to place anything along.
    function barPanelSpot() { return barShown && !notchShown ? BarLogic.spot(bar.panelSpot) : "widget" }
    function barNotificationSpot() { return barShown && !notchShown ? BarLogic.spot(bar.notificationSpot) : "widget" }

    function isKnownType(type) {
        return WidgetRegistry.isAvailable(type)
    }

    // What a tile surface offers beside its own catalogue: every desktop
    // widget, the way the notch already does. The list is built here and not
    // in the catalogues, because the registry is a QML singleton and those are
    // plain libraries.
    //
    // `own` is the surface's own entries, already filtered to what is not on
    // it; `taken` is every type it carries, so a widget already placed is not
    // offered twice. The dock's own pieces are not offered (availableTypes).
    function widgetChoices(taken) {
        return WidgetRegistry.availableTypes()
            .filter(widget => (taken || []).indexOf(widget.name) < 0)
            .map(widget => ({ type: widget.name, label: widget.label, icon: widget.icon }))
    }
    function tileChoices(own, taken) {
        return (own || []).concat(widgetChoices(taken))
    }

    function placementIds(screenName, includeHidden) {
        return Logic.placements(modeConfig(), screenName, includeHidden === true)
            .filter(id => {
                const entry = root.widget(id)
                return !entry || isKnownType(entry.type)
            })
    }

    function widget(id) {
        return modeConfig().widgets.find(item => item.id === id) || null
    }

    function group(id) {
        return modeConfig().groups.find(item => item.id === id) || null
    }

    function item(id) {
        return widget(id) || group(id)
    }

    function members(groupId) {
        const target = group(groupId)
        if (!target) return []
        return target.members.map(id => widget(id)).filter(entry => entry && isKnownType(entry.type))
    }

    // ---- persistence -------------------------------------------------------

    function load() {
        const text = layoutFile.text()
        // The watch reads back every write of our own, and that text is what
        // `config` already holds (the write timer keeps it as fileText).
        // Parsed, migrated and sanitized again, it bought a revision that
        // re-ran every binding on the layout, after every edit. Nothing waits
        // for that read: the one-shots, the built-in profiles and the settling
        // all ran on the config it was written from, and a file this shell
        // wrote is never one to migrate.
        if (loaded && text === fileText) return
        // A reload can catch the file while it is being replaced (empty, missing
        // or half written): keep the current layout rather than resetting to an
        // empty one that the next change would save over the user's pills and
        // widgets.
        if (loaded && !readOnly && !text.trim().length) return
        const result = Migrations.migrate(text)
        if (loaded && !readOnly && !result.ok) {
            console.warn("buchhwin-shell: layout file unreadable, keeping current layout:", result.error)
            return
        }
        fileText = text
        readOnly = result.readOnly || unreadableReason.length > 0
        readOnlyReason = unreadableReason.length ? unreadableReason : result.error || ""
        if (readOnly)
            console.warn("buchhwin-shell: layout is read-only:", readOnlyReason)
        // Every migration keeps the file it read, named after the version it
        // was. It used to be v1 only, which was right while v1 was the only
        // migration there had ever been; a migration that turns out to be
        // wrong is exactly the moment the old file is worth having, and that
        // is not something the first one has a monopoly on.
        const migrated = result.ok && result.changed && result.from >= 1
        backupVersion = migrated ? result.from : 0
        config = Logic.sanitize(result.config)
        notchStored = !!(result.config && result.config.notch)
        if (!loaded) layoutWasEmpty = result.ok && !text.trim().length && !unreadableReason.length
        loaded = true
        decideFresh()
        ensureScreens()
        adoptOnce()
        resumeDndOnce()
        ensureBuiltinProfiles()
        revision++
        if (migrated) {
            pendingBackup = text
            backupTimer.restart()
            save()
        }
        settleActiveState()
    }

    // The notch used to be four booleans in settings.json. A layout file that
    // has no notch of its own yet takes them once, so an existing session keeps
    // the overview it had. The booleans stay where they are for now: removing
    // them in the same change would let SettingsService strip them on the first
    // unrelated write, before this ever ran.
    //
    // `sanitize` fills a missing notch in with the default, so whether the file
    // really carried one has to be remembered separately - and the settings may
    // still be loading when the layout arrives, which is why this is also tried
    // again from the Connections below rather than only once.
    property bool notchStored: false

    // The big time and the long date used to be a header the overview drew
    // above its list, whatever the list said. They are an item now, so a notch
    // stored before that gets one, once, at the front - otherwise a session
    // that had a clock in its notch would silently lose it. Marked in the
    // settings rather than in the layout file, because the layout file's
    // version is what tells a newer shell from an older one.
    property bool headerAdopted: false
    // Guarded by a marker in the layout file itself rather than in
    // settings.json, because the sizes it resets live in the layout file. The
    // old settings marker is still honoured so the run never repeats on a
    // session that has already had it.
    property bool quickSizesAdopted: false

    // Every one-shot in one pass, with one write of each file at the end: two
    // writes of the same file in the same turn of the event loop drop the
    // first one, which Quickshell says in the log and the smoke test fails on.
    function adoptOnce() {
        if (readOnly || !loaded || !SettingsService.loaded || !freshDecided) return
        const marks = {}
        let touched = false
        if (!headerAdopted) {
            headerAdopted = true
            if (SettingsService.value("notch.headerAdopted") !== true) {
                marks["notch.headerAdopted"] = true
                if (notchStored) {
                    config = Logic.sanitize(Object.assign({}, config, { notch: Logic.adoptNotchHeader(config.notch) }))
                    touched = true
                }
            }
        }
        if (!quickSizesAdopted) {
            quickSizesAdopted = true
            const marked = Logic.hasAdopted(config, "quickSizes")
            const ran = marked || SettingsService.value("desktop.quickSizesAdopted") === true
            if (!ran) {
                // An undo step, because this resets every size the user set:
                // it used to run through `mutate` alone, so the reset could
                // not be taken back.
                beginChange()
                mutate((mode, next) => {
                    mode.quick = Logic.adoptQuickSizes(mode.quick || Logic.defaultQuick())
                    next.adopted = Logic.withAdopted(next, "quickSizes")
                })
                touched = true
            } else if (!marked) {
                // It ran before the marker moved into this file. Carry it over
                // so a restored layout file cannot make it run again.
                mutate((mode, next) => { next.adopted = Logic.withAdopted(next, "quickSizes") })
                touched = true
            }
        }
        if (adoptModeAppearance()) touched = true
        if (dropAgendaCards()) touched = true
        if (dropLauncherCategories()) touched = true
        if (Object.keys(marks).length) SettingsService.setAll(marks)
        if (touched) save()
    }

    // The dashboard's "Week and day" card is gone - the dashboard always shows
    // the month now, so the card could only ever draw nothing and leave a hole
    // in the grid. A card the catalogue no longer knows is not removed on load
    // in general (the dashboard also accepts desktop widgets, and `sanitize`
    // cannot ask the registry), so this one is taken out by name, once.
    function dropAgendaCards() {
        if (Logic.hasAdopted(config, "dashboardAgenda")) return false
        const next = JSON.parse(JSON.stringify(config))
        for (const profileName of Object.keys(next.profiles)) {
            const modes = next.profiles[profileName].modes || {}
            for (const name of Object.keys(modes)) {
                const surface = modes[name].dashboard
                if (!surface || !Array.isArray(surface.dashboard)) continue
                surface.dashboard = surface.dashboard.filter(
                    pill => !(pill.items && pill.items[0] && pill.items[0].type === "agenda"))
            }
        }
        next.adopted = Logic.withAdopted(next, "dashboardAgenda")
        config = Logic.sanitize(next)
        revision++
        return true
    }

    // `launcher.categories` was a switch in Settings > Launcher. The block
    // being in the layout or not *is* that answer now, and two sources for one
    // truth is the drift this repository spends its time undoing everywhere
    // else - so a session that had the switch off has the block taken out
    // once, and the setting is gone.
    //
    // The setting is read here rather than in the sanitizer for the same
    // reason the notch's four booleans were: a sanitizer cannot ask
    // SettingsService, and it runs on every load rather than once.
    function dropLauncherCategories() {
        if (Logic.hasAdopted(config, "launcherCategories")) return false
        const off = SettingsService.value("launcher.categories") === false
        const next = JSON.parse(JSON.stringify(config))
        if (off) {
            for (const profileName of Object.keys(next.profiles)) {
                const modes = next.profiles[profileName].modes || {}
                for (const name of Object.keys(modes)) {
                    const surface = modes[name].launcher
                    if (!surface) continue
                    // `side` is gone as a zone but a stored file may still
                    // carry one; the sanitizer folds it into the column, and
                    // this runs before that, so both are swept.
                    for (const zone of ["stack", "side"]) {
                        if (!Array.isArray(surface[zone])) continue
                        surface[zone] = surface[zone].filter(
                            pill => !(pill.items && pill.items[0] && pill.items[0].type === "categories"))
                    }
                }
            }
        }
        next.adopted = Logic.withAdopted(next, "launcherCategories")
        config = Logic.sanitize(next)
        revision++
        return true
    }

    // Every mode owns the settings on ProfileLogic.MODE_SCOPED. Before v3 they
    // were one choice for the whole session, so on the first start after the
    // migration every mode is given **what is set right now** - which is why
    // switching modes still changes nothing that day. Where a template names a
    // value in its `effects`, that one wins, because entering the mode applied
    // it anyway.
    //
    // Without this a mode that owns nothing keeps whatever the mode before it
    // left behind, which is how `animationMode` used to leak out of Gaming and
    // stay reduced.
    //
    // It needs the templates, so it is tried again as each one arrives.
    function adoptModeAppearance() {
        if (Logic.hasAdopted(config, "modeAppearance")) return false
        // A first start has no modes from before mode-scoped appearance, so
        // there is nothing to carry over. Run there, it filled in every mode a
        // shipped Default leaves out whenever the templates were read after
        // the shipped profile (the reads race), and the mark alone is enough:
        // a mode that is not in the file is in its factory state.
        if (freshLayout) {
            config = Logic.sanitize(Object.assign({}, config, { adopted: Logic.withAdopted(config, "modeAppearance") }))
            revision++
            return true
        }
        if (modeNames.some(name => !templates[name])) return false
        const next = JSON.parse(JSON.stringify(config))
        for (const profileName of Object.keys(next.profiles)) {
            const modes = next.profiles[profileName].modes || {}
            for (const name of modeNames) {
                const effects = (templates[name] && templates[name].effects) ? templates[name].effects : {}
                const appearance = {}
                for (const leaf of Profile.MODE_SCOPED)
                    appearance[leaf] = effects[leaf] !== undefined
                        ? effects[leaf] : SettingsService.value(Profile.modeScopedPath(leaf))
                // A mode not in the file yet is made as entering it would
                // make it - with its template's desktop mode and bar - or it
                // would count as entered and show widgets for good: a
                // layout.json lost beside the settings gave every mode of
                // Default that placeholder.
                if (!modes[name]) modes[name] = Logic.freshMode(templates[name])
                modes[name].appearance = Object.assign(appearance, modes[name].appearance || {})
            }
            next.profiles[profileName].modes = modes
        }
        next.adopted = Logic.withAdopted(next, "modeAppearance")
        config = Logic.sanitize(next)
        revision++
        return true
    }

    Connections {
        target: SettingsService
        function onLoadedChanged() {
            if (!SettingsService.loaded) return
            root.noteSettings()
            root.ensureBuiltinProfiles()
            root.adoptOnce()
            root.settleActiveState()
        }
    }
    // A shell whose settings were in before this service was made.
    Component.onCompleted: if (SettingsService.loaded) noteSettings()

    // One write per turn of the event loop, and never from inside the load
    // that is finishing. `load()` and `adoptOnce()` run from the file's own
    // `loaded` handler, and a `setText` from there wrote the file inside the
    // callback of the read being finished - the FileView drops that read and
    // Quickshell logs "got operation finished from dropped operation", which
    // the smoke test fails on (docs/testing.md > Pitfalls; SettingsService
    // writes the same way). The text is taken when the write is asked for,
    // not when it runs, so a reload that lands in between cannot put an
    // older layout back on disk.
    // `config` is a sanitize result whenever it is set here (load, every
    // edit, every profile operation), so it is written as it is: checking it
    // a second time was a third of every edit's cost.
    property string pendingText: ""
    function save() {
        if (readOnly || !loaded) return false
        // The day's snapshot before the first write of a day (SnapshotService).
        SnapshotService.beforeWrite()
        pendingText = JSON.stringify(config, null, 2) + "\n"
        writeTimer.restart()
        return true
    }
    // The file as last read or written, for the backup before a profile
    // switch (backupToday); see SettingsService.fileText.
    property string fileText: ""
    Timer { id: writeTimer; interval: 0; onTriggered: { layoutFile.setText(root.pendingText); root.fileText = root.pendingText } }
    // The copy a migration keeps of the file it read, written the same way
    // and for the same reason: it is asked for from `load()`.
    property string pendingBackup: ""
    Timer { id: backupTimer; interval: 0; onTriggered: backupFile.setText(root.pendingBackup) }

    // Every edit lands in the active mode of the active profile. The callback
    // gets that mode and the whole config, because a few things it may change -
    // the notch, the dock, the lock screen, the adoption markers - are global.
    // Those and the mode are the callback's own copies; everything else is
    // shared with the config as it was and must not be changed
    // (LayoutLogic.edit). Each edit used to copy and check the whole layout,
    // every profile's state and every mode, and handed a new notch, dock and
    // bar to every screen for a change to one of them.
    function mutate(callback) {
        if (readOnly) return false
        config = Logic.edit(config, activeProfile, activeMode, callback)
        revision++
        return true
    }

    // The notch's options are not in the layout file but in settings.json (a
    // profile keeps them in its state with the rest). They are edited in the
    // editor, and Ctrl+Z there has to reach them, so an undo step carries them
    // along.
    readonly property var notchKeys: ["notch.eventCount", "notch.hoverMode", "notch.openDelay", "notch.closeDelay",
                                      "notch.clickAction", "notch.middleAction", "notch.rightAction", "notch.swipe", "notch.panelOrigin", "notch.accentGlyphs", "notch.reserve",
                                      "notch.fullscreen", "notch.shape", "notch.collapsedWidth",
                                      "notch.expandedWidth", "notch.expandedHeight",
                                      "notch.bodyHeight", "notch.bodyRadius", "notch.bodyPadding", "notch.dockDuplicates"]
    // Every setting an undo step carries along. The notch's options are edited
    // in the layout editor and the control center's size on the panel itself;
    // both have an undo within reach and both have to reach these.
    readonly property var undoKeys: notchKeys.concat(["desktop.quickWidth", "desktop.quickHeight",
                                                      "desktop.dashboardWidth", "desktop.dashboardHeight"])

    function notchSnapshot() {
        const values = {}
        for (const key of undoKeys) values[key] = SettingsService.value(key)
        return values
    }

    // A step keeps only what undo puts back. The profiles' stored states, the
    // saved notch presets and the one-shot markers are taken from the config
    // at hand when a step is undone (see undo), and the states - each
    // profile's settings, notch and lock screen - were a third of every step
    // with two profiles (10 of 30 KB, 15.10.), more with each profile, thirty
    // steps deep. The one state undo reads from a step is one the step's own
    // change took away with the steps kept, and that change hands it to its
    // step (`states`): removeProfile the removed profile's, resetProfile that
    // of a built-in one not in use (LayoutLogic.withUndoStates).
    //
    // This whole layout is a step of the profile level only
    // (beginProfileChange). Every other step holds the one mode an edit can
    // change and the global surfaces (beginChange, LayoutLogic.undoTarget).
    function undoConfig() {
        const kept = Object.assign({}, config)
        delete kept.notchPresets
        delete kept.adopted
        if (!config.profiles) return kept
        kept.profiles = {}
        for (const name of Object.keys(config.profiles)) {
            const profile = Object.assign({}, config.profiles[name])
            delete profile.state
            kept.profiles[name] = profile
        }
        return kept
    }

    // A step before an edit: which mode is in use, that mode as it is now and
    // the global surfaces beside it (notch, dock, lock screen) - all an edit
    // can change (mutate). `modeSwitch` marks the step of a mode switch the
    // user made, the only step whose undo takes the mode back
    // (LayoutLogic.modeAfterUndo); it holds the mode switched to as well, as
    // it was (none, when it is entered the first time). `settings` are
    // settings this step's change alone takes along, by path, as they were
    // before it (applyDockPreset; LayoutLogic.undoSettings).
    function beginChange(modeSwitch, settings) {
        if (readOnly) return
        const modes = Logic.modesOf(config, activeProfile)
        const list = {}
        for (const name of [activeMode].concat(modeSwitch && modeSwitch.to ? [modeSwitch.to] : []))
            list[name] = modes[name] || null
        const step = { config: { activeMode: activeMode, notch: config.notch, dock: config.dock, lock: config.lock },
                       modes: { profile: activeProfile, list: list }, notch: notchSnapshot() }
        if (modeSwitch) step.modeSwitch = modeSwitch
        if (settings && Object.keys(settings).length) step.settings = settings
        pushStep(step)
    }

    // A step before a change to the profiles themselves - one added,
    // duplicated, renamed, removed or reset: the whole layout (undoConfig).
    // `states` are the stored states the change takes away, which undo brings
    // back (LayoutLogic.withUndoStates). `appearance` names the modes whose
    // appearance the change replaces ({ profile: [mode, ...] }): undone, those
    // get the step's back, while every other mode keeps the appearance it has
    // then (LayoutLogic.withCurrentAppearance).
    function beginProfileChange(states, appearance) {
        if (readOnly) return
        const step = { config: undoConfig(), notch: notchSnapshot() }
        if (states) step.states = states
        if (appearance) step.appearance = appearance
        pushStep(step)
    }

    function pushStep(step) {
        const next = undoStack.slice()
        next.push(JSON.stringify(step))
        if (next.length > 30) next.shift()
        undoStack = next
    }

    // Notch options change settings only, so they take an undo step of their
    // own rather than going through changeBar/mutate.
    function changeNotch(key, value) {
        if (notchKeys.indexOf(key) < 0) return false
        // The value it has already (the editor's segments re-emit the one they
        // show): no undo step that undoes nothing.
        if (JSON.stringify(SettingsService.value(key)) === JSON.stringify(value)) return true
        beginChange()
        SettingsService.set(key, value)
        return true
    }

    function undo() {
        if (!undoStack.length || readOnly) return
        const next = undoStack.slice()
        const step = JSON.parse(next.pop())
        const before = config
        // Saved notch presets are not part of an edit: saving, renaming or
        // deleting one takes no undo step, so undoing the drag before it must
        // not take the preset with it (or bring a deleted one back).
        // Nor are the profiles' stored states and the one-shot markers. A
        // state is what a profile was left with, or what entering a built-in
        // one applied: Ctrl+Z right after that took the applied state away,
        // and the next switch stored nothing for it. A marker says a
        // migration has run, and an older list would run it again. A state
        // the step's change took away (a removal, a Reset of a built-in one
        // not in use) comes back from the step, which was handed it. A step
        // of one mode holds none of these, and every other mode and profile
        // stays as it is now (LayoutLogic.undoTarget).
        const target = Logic.undoTarget(step, before)
        // Nor is the mode, unless the step is the switch itself and its mode
        // still in use: an automatic switch takes no step, and undoing an
        // edit or a switch from before it keeps the mode the machine chose.
        const modeBefore = activeMode
        const appearanceBefore = Logic.modeConfig(before, activeProfile, modeBefore).appearance
        target.activeMode = Logic.modeAfterUndo(step, modeBefore)
        // Nor are the built-in profiles: a step taken before one was added
        // must not take it away again.
        config = Logic.addBuiltinProfiles(Logic.sanitize(target, before),
                                          builtinProfileNames.map(id => builtinProfiles[id]).filter(data => !!data)).config
        // The widgets of every monitor the mode in use has now. The step is
        // from before whatever was materialized since without a step of its
        // own - a monitor plugged in, an automatic switch into a mode first
        // used after the step (both kept: see modeAfterUndo) - and without
        // this the desktop of that mode or monitor stayed empty until the
        // next screen change. Returns at once when nothing is missing.
        ensureScreens()
        // Nor is a mode's appearance, which every mode-scoped setting changes
        // without a step: each mode keeps the one it has now - unless the
        // step's own change replaced it (a Reset), which is what undoing that
        // brings back. After ensureScreens, so a mode it made again keeps its
        // appearance too.
        config = Logic.withCurrentAppearance(config, before, step.appearance)
        // A switch undone is a switch back, with all that entering the mode
        // does: its widgets on every monitor (above), its appearance (gaps,
        // blur, animations) and Do Not Disturb - off again when the mode
        // undone turned it on. Without it the settings stayed those of the
        // mode undone, and the next mode-scoped edit was stored in the mode
        // restored. A Reset undone in the mode in use puts the appearance it
        // had back on screen too: before, the file had the old gaps and the
        // screen kept the reset's until the next switch.
        if (activeMode !== modeBefore) {
            applyModeSettings(activeMode)
            modeDndTransition(modeBefore, activeMode)
        } else if (JSON.stringify(Logic.modeConfig(config, activeProfile, activeMode).appearance)
                   !== JSON.stringify(appearanceBefore)) {
            applyModeSettings(activeMode)
        }
        const restored = Logic.undoSettings(step, undoKeys)
        if (Object.keys(restored).length) SettingsService.setAll(restored)
        undoStack = next
        revision++
        save()
    }

    // ---- profiles, modes and screens --------------------------------------

    // The active mode gets a widget set for every monitor it has not seen
    // before, from its factory template. This is also how a **profile** copies
    // the factory state rather than the Default profile: a new profile has no
    // modes at all, so each one is materialized from `config/profiles/<mode>.json`
    // the first time it is entered.
    function ensureScreens() {
        if (!loaded) return
        const target = Logic.modeConfig(config, activeProfile, activeMode)
        const template = templates[activeMode]
        const missing = Quickshell.screens.map(screen => screen.name).filter(name => target.screens.indexOf(name) < 0)
        if (!missing.length || !template) return
        // Materialized in memory; written with the next edit. Only this mode
        // is copied; the rest of the layout stays the objects it was.
        const stored = Logic.modesOf(config, activeProfile)[activeMode]
        // A mode used for the first time takes its desktop mode and its bar
        // from the template too.
        const nextMode = stored ? JSON.parse(JSON.stringify(stored)) : Logic.freshMode(template)
        for (const screen of missing) {
            const made = Logic.materialize(template, screen, nextMode.widgets.map(w => w.id)
                .concat(nextMode.groups.map(g => g.id)), type => WidgetRegistry.type(type) !== null)
            nextMode.widgets = nextMode.widgets.concat(made.widgets)
            nextMode.groups = nextMode.groups.concat(made.groups)
            nextMode.screens.push(screen)
        }
        config = Logic.withMode(config, activeProfile, activeMode, nextMode)
        revision++
    }

    // ---- the mode: one of the five ----------------------------------------
    // What `setActiveProfile` did before v3. The settings a mode owns
    // (ProfileLogic.MODE_SCOPED) are applied here, from the mode's own stored
    // block or, for a mode nobody has customized, from its template's
    // `effects`.
    //
    // A switch the user makes is an undo step, and undoing it switches back
    // (see undo). `automatic` is one the machine makes (AdaptiveService, a
    // monitor plugged in or taken away): it takes no step, so Ctrl+Z after
    // docking undoes the last edit rather than the dock, and keeps the mode.
    //
    // The mode in use asked for again (a click on the segment that is already
    // chosen) changes nothing and takes no step: it used to push an empty
    // step out of the thirty and write both files.
    function setActiveMode(name, automatic) {
        if (modeNames.indexOf(name) < 0 || readOnly) return false
        if (name === activeMode) return true
        // The step names the mode it goes to, so an automatic switch since
        // keeps its own (Logic.modeAfterUndo).
        if (automatic !== true) beginChange({ to: name })
        const modeBefore = activeMode
        // Only the mode in use changes: the notch, the dock, the lock screen
        // and every mode stay the objects they were, so nothing that shows
        // them hears of the switch.
        config = Logic.sanitize(Object.assign({}, config, { activeMode: name }), config)
        ensureScreens()
        applyModeSettings(name)
        modeDndTransition(modeBefore, name)
        revision++
        save()
        return true
    }

    // True while a mode's own settings are being written into SettingsService,
    // so the handler below does not write them straight back into the mode
    // they just came from.
    property bool applyingMode: false

    // What entering mode `name` sets, by path: only what differs from what
    // is set now. Two modes with the same appearance (buchhwin's work and
    // docked) used to write all ten settings at every switch between them,
    // which replaced every setting and re-ran every binding on one.
    function modeSettings(name) {
        const stored = Logic.modeConfig(config, activeProfile, name).appearance || {}
        const template = templates[name] || {}
        const effects = template.effects ? template.effects : {}
        // A mode of a profile made after the adoption below - a new profile
        // starts from the factory state - owns nothing and its template may
        // name nothing either. The factory state of a setting is its default,
        // so that is what it gets, rather than whatever the mode before it
        // happened to leave behind. Only once the adoption has run, though:
        // until then no mode owns anything and resetting them all to defaults
        // would be the one thing this change must not do.
        const adopted = Logic.hasAdopted(config, "modeAppearance")
        const values = {}
        for (const leaf of Profile.MODE_SCOPED) {
            const path = Profile.modeScopedPath(leaf)
            if (stored[leaf] !== undefined) values[path] = stored[leaf]
            else if (effects[leaf] !== undefined) values[path] = effects[leaf]
            else if (adopted) values[path] = SettingsService.defaultOf(path)
        }
        const changed = {}
        for (const path of Object.keys(values))
            if (SettingsService.value(path) !== values[path]) changed[path] = values[path]
        return changed
    }

    // `extra` are settings to write in the same go (a profile's own,
    // enterProfile): one write and one change of every setting, not two.
    function applyModeSettings(name, extra) {
        const values = Object.assign({}, extra || {}, modeSettings(name))
        if (!Object.keys(values).length) return
        applyingMode = true
        SettingsService.setAll(values)
        applyingMode = false
    }

    // Do Not Disturb is not a setting, it is session state, so it is not on
    // the mode-scoped list and applyModeSettings leaves it alone: it changes
    // only when the mode does. A mode that turns it on does so when it finds
    // it off, and turns it off again when it is left - unless the user
    // changed it in between (Logic.dndOnModeChange; NotificationService keeps
    // whose it is across shell restarts). Which modes do is each mode's
    // choice (Settings > Profiles, "Do Not Disturb in this mode":
    // Logic.modeDnd); one that has made none does what its template says, so
    // gaming turns it on and the other four do not.
    //
    // Only a mode that turns it on can own it (Logic.modeMayOwnDnd), so
    // between two others there is nothing to ask - and NotificationService is
    // not made for it: a unit test switching modes started the session's
    // notification server on the user's bus (pitfall 82). A template not read
    // yet is asked about as before.
    function modeDndTransition(from, to) {
        if (from === to) return
        const known = templates[from] !== undefined && templates[to] !== undefined
        if (known && !Logic.modeMayOwnDnd(config, from, (templates[from] || {}).effects)
                  && !Logic.modeMayOwnDnd(config, to, (templates[to] || {}).effects)) return
        if (typeof NotificationService === "undefined" || !NotificationService.setDnd) return
        const change = Logic.dndOnModeChange(NotificationService.dndBy, NotificationService.dndActive, from, to, modeDndEffects(to))
        if (change) NotificationService.setDnd(change.mode, change.by)
    }
    // Mode `name` of the profile in use: whether entering it turns Do Not
    // Disturb on, and its effects with that choice in them (AdaptiveService's
    // Focus hands the Do Not Disturb back by them).
    function modeDnd(name) {
        return Logic.modeDnd(Logic.modeConfig(config, activeProfile, name), (templates[name] || {}).effects).length > 0
    }
    function modeDndEffects(name) {
        return Logic.modeDndEffects(Logic.modeConfig(config, activeProfile, name), (templates[name] || {}).effects)
    }
    // The choice for the mode in use, kept in the mode as its appearance is:
    // no undo step of its own, and an undo keeps it (withCurrentAppearance).
    // It acts at once, as entering or leaving the mode would: switched on
    // with Do Not Disturb off, it turns it on as the mode's; switched off,
    // the mode's own ends, and one the user set stays.
    //
    // Not before the mode's template is in: until then the mode in use may not
    // be in the file yet, and an edit would make it a placeholder that shows
    // widgets for good (pitfall 119).
    function setModeDnd(on) {
        const name = activeMode
        if (readOnly || !loaded || templates[name] === undefined) return false
        const wanted = on === true
        if (modeDnd(name) === wanted) return true
        mutate(mode => { mode.dnd = wanted })
        save()
        if (typeof NotificationService === "undefined" || !NotificationService.setDnd) return true
        const kind = Logic.modeDnd(modeConfig(), (templates[name] || {}).effects)
        const change = Logic.dndOnModeChoice(NotificationService.dndBy, NotificationService.dndActive, name, kind)
        if (change) NotificationService.setDnd(change.mode, change.by)
        return true
    }

    // A reboot ends a manual Do Not Disturb, a mode's own with it
    // (NotificationLogic.dndAtBoot). Once the layout and the template of the
    // mode in use are both in, that mode is asked once and takes its own back
    // while it is still the one in use (NotificationService.resumeModeDnd):
    // gaming came back from a reboot without it. Only a mode that turns Do
    // Not Disturb on (its template's, or its own choice: modeDnd) asks, so a
    // start in any other mode - and every unit test that stays out of gaming
    // - never makes NotificationService (pitfall 82).
    property bool dndResumeAsked: false
    function resumeDndOnce() {
        if (dndResumeAsked || !loaded) return
        const template = templates[activeMode]
        if (template === undefined) return
        dndResumeAsked = true
        if (!modeDnd(activeMode)) return
        if (typeof NotificationService === "undefined" || !NotificationService.resumeModeDnd) return
        NotificationService.resumeModeDnd(activeMode)
    }

    // A setting a mode owns, changed anywhere in the shell, belongs to the mode
    // that is active while it is changed. `SettingsService.set` had no change
    // signal at all before this; it is the one piece that was missing.
    Connections {
        target: SettingsService
        function onSettingChanged(path, value) {
            if (root.applyingMode || root.readOnly || !root.loaded) return
            const leaf = Profile.modeScopedLeaf(path)
            if (!leaf.length) return
            // A value the mode has already is no change to it, and no write.
            if ((root.modeConfig().appearance || {})[leaf] === value) return
            root.mutate(mode => {
                const appearance = Object.assign({}, mode.appearance || {})
                appearance[leaf] = value
                mode.appearance = appearance
            })
            root.save()
        }
    }

    // ---- the profile: the level above --------------------------------------
    // A profile keeps everything the user sets: its five modes in `modes`, and
    // the rest in `state` (LayoutLogic.sanitizeProfileState) - every setting
    // that is a profile's (ProfileLogic.isProfileSetting), the notch and the
    // lock screen. The settings and the global notch and lock layouts are
    // what is live; a profile's state is a copy of them, taken when the
    // profile is left and put back when it is entered. The notch presets stay
    // global: they are a library to pick from, not a choice.

    // The state as it is right now, in the form a profile keeps it.
    function currentState() {
        return Logic.sanitizeProfileState({ settings: SettingsService.sanitized(), notch: config.notch, dock: config.dock,
                                            lock: config.lock })
    }

    // A state's or a shipped profile's settings, every one a profile owns:
    // what it names, and the default for what it does not
    // (ProfileLogic.completeLeaves) - the dock of the profile left must not
    // come along. Through the migrations settings.json goes through first, so
    // a state stored before one keeps the user's choice (LayoutLogic.
    // migrateSettings), and with the defaults' home paths as they are
    // (LayoutLogic.profileLeaves).
    function profileLeaves(tree) {
        return Logic.profileLeaves(Logic.migrateSettings(tree), SettingsService.defaults, Paths.home)
    }

    // The settings of a state (or of a shipped profile) this shell knows, as
    // it would take them - a value it refuses (the wrong type, one `allowed`
    // does not list) is the default rather than the setting of the profile
    // left - and that differ from what is set. A key from a newer shell is
    // left out here rather than warned about one by one in SettingsService.
    // `leaves` come complete (profileLeaves): a key the state does not name
    // is there at its default.
    function knownValues(leaves) {
        return Logic.knownSettings(leaves, path => SettingsService.defaultOf(path), SettingsService.allowed,
                                   path => SettingsService.value(path))
    }

    // A built-in profile without a state has not had its shipped one yet:
    // entered for the first time, its setup is being applied (one that could
    // not be takes what is set, finishBuiltin). Left now, it must not store
    // what happens to be set - that is the profile it came from - or the
    // shipped setup would never arrive.
    function waitingForShipped(name) {
        const id = Logic.builtinOf(config, name)
        return id.length > 0 && builtinProfiles[id] !== undefined && !Logic.stateOf(config, name)
    }

    function setActiveProfile(name) {
        if (profileNames.indexOf(name) < 0 || readOnly) return false
        if (name === activeProfile) {
            // Naming the profile one is already in re-applies its mode's
            // settings and nothing else - it is not a request to put its
            // stored state back over what is set; Restore is.
            beginChange()
            ensureScreens()
            applyModeSettings(activeMode)
            revision++
            save()
            return true
        }
        // A state taken before settings.json has been read would be the
        // defaults, stored over the profile being left.
        if (!loaded || !SettingsService.loaded) return false
        // A copy of the top two levels: enterProfile changes nothing deeper.
        const next = Object.assign({}, config, { profiles: Object.assign({}, config.profiles) })
        if (!waitingForShipped(activeProfile))
            next.profiles[activeProfile] = Object.assign({}, config.profiles[activeProfile], { state: currentState() })
        enterProfile(next, name)
        return true
    }

    // The switch itself, on a copy of the config the caller has already
    // changed: the state of the profile left stored (setActiveProfile), or
    // the profile left removed (removeProfile).
    //
    // Into a profile with a state: its settings - all a profile owns, the
    // default for one the state does not name (profileLeaves) -, notch, dock
    // and lock screen are put back. Into one without: a profile of the user's keeps what is set
    // and takes it as its state (a new profile starts from the session it was
    // made in, not from defaults); a built-in one gets its shipped setup
    // (startBuiltin), which becomes its state once it is in. The mode-scoped
    // appearance comes from the mode, as before.
    //
    // One save of layout.json, and one write of settings.json: the state's
    // settings and the mode's go in one `setAll` (pitfall 3), which also
    // re-runs every binding on a setting once rather than twice.
    //
    // `next` is the caller's own copy of the top level and of `profiles`;
    // the profiles in it may still be the config's own objects, so nothing
    // below them is changed here.
    function enterProfile(next, name) {
        const stored = next.profiles[name] ? next.profiles[name].state || null : null
        const id = Logic.builtinOf(next, name)
        const shipped = !stored && id.length > 0 && builtinProfiles[id] !== undefined
        // First, while nothing has changed yet - unless a shipped setup is
        // about to be applied: profile-apply.py backs the files up itself,
        // and the two started in the same turn raced for the same
        // backup-<day>. Its copy is of the files this switch has written,
        // which loses nothing: the profile left is in it, with its state.
        if (!shipped) backupToday()
        // An undo step from the profile left would put its layout back under
        // the settings of this one, and the next switch would store that mix
        // as its state. Undo starts again in every profile.
        undoStack = []
        next.activeProfile = name
        if (!stored && !shipped) {
            next.profiles = Object.assign({}, next.profiles)
            next.profiles[name] = Object.assign({}, next.profiles[name], { state: currentState() })
        }
        // Every mode and state the switch does not touch stays the object it
        // was (LayoutLogic.sanitize with the config it came from).
        config = stored ? Logic.restoreStateLayout(next, stored, config) : Logic.sanitize(next, config)
        const values = stored ? knownValues(profileLeaves(stored.settings)) : {}
        ensureScreens()
        applyModeSettings(activeMode, values)
        revision++
        save()
        if (shipped) startBuiltin(id, name)
    }

    // ---- once per start: the profile in use and its state ------------------
    // When the layout, the settings and every shipped profile are in (read or
    // missing), the profile in use gets a state if it has none, so the one
    // in use before the first switch - Default with its notch - holds what it
    // is now rather than nothing.
    //
    // A built-in one without a state gets its shipped setup instead (with the
    // backup first, as on entering it): on a first start that makes Default
    // the shipped Default. Not on the first start of this version over an
    // existing layout file, though (LayoutLogic.settleAction): an update must
    // not put a shipped setup back over what the user has.
    property bool stateSettled: false
    // id -> true once its profile.json has been read or found missing.
    property var builtinRead: ({})
    // A first start: layout.json and settings.json were both missing or
    // empty on their first read. The layout alone is not enough - a layout
    // file lost beside the user's settings is not a new user, and the
    // shipped Default's modes and setup would replace a desktop the settings
    // still describe. Decided once both have been read, in whichever order
    // they arrive (`decideFresh`); the adoptions, the built-in profiles and
    // the settling below wait for that, and the settling ends it - a layout
    // read again later in the session is not a first start.
    property bool freshLayout: false
    property bool freshDecided: false
    // What the two first reads found. The settings are taken the moment they
    // load, before anything has written them, so their text is still the
    // file's (SettingsService.fileText follows every write after that).
    property bool layoutWasEmpty: false
    property bool settingsSeen: false
    property bool settingsWereEmpty: false

    function noteSettings() {
        if (settingsSeen) return
        settingsSeen = true
        settingsWereEmpty = !SettingsService.fileText.trim().length
        decideFresh()
    }

    function decideFresh() {
        if (freshDecided || !loaded || !settingsSeen) return
        freshDecided = true
        freshLayout = layoutWasEmpty && settingsWereEmpty
    }

    function settleActiveState() {
        if (stateSettled || !loaded || readOnly || !SettingsService.loaded || !freshDecided) return
        if (!builtinProfileNames.every(id => builtinRead[id] === true)) return
        stateSettled = true
        const name = activeProfile
        const id = Logic.builtinOf(config, name)
        const action = Logic.settleAction(config, name, builtinProfiles[id] !== undefined, freshLayout)
        // Everything that asks has asked by now: the built-in profiles were
        // added as each file was read, and the one-shots ran with the second
        // of the two files.
        freshLayout = false
        if (!action.length && Logic.hasAdopted(config, "profileState")) return
        const next = JSON.parse(JSON.stringify(config))
        next.adopted = Logic.withAdopted(next, "profileState")
        if (action === "current") next.profiles[name].state = currentState()
        config = Logic.sanitize(next)
        revision++
        save()
        if (action === "shipped") startBuiltin(id, name)
    }

    function markBuiltinRead(id) {
        const next = Object.assign({}, builtinRead)
        next[id] = true
        builtinRead = next
        settleActiveState()
    }

    // ---- a backup before the first switch of a day ---------------------------
    // A switch rewrites settings.json from the profile entered. Nothing is
    // lost by that - the profile left keeps it as its state - but a mistake
    // in that would be, so the first switch of each day keeps both files in
    // the state directory first, as backup-<YYYY-MM-DD> (profile-apply.py
    // --backup-stdin; an existing backup of the day is never written into).
    //
    // The texts are taken now and handed over on stdin, not copied from disk
    // by the helper: its start is slower than the write timers below, and a
    // copy made after them would be of the files the switch just wrote.
    property string backupDay: ""

    function backupToday() {
        const day = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (backupDay === day || backupProc.running || !loaded) return
        backupDay = day
        backupProc.request = JSON.stringify({ "settings.json": SettingsService.fileText,
                                              "layout.json": fileText })
        backupProc.command = ["python3", Paths.script("profile-apply.py"), "--backup-stdin",
                              "--backup-dir", Paths.stateDir]
        backupProc.running = true
    }

    Process {
        id: backupProc
        property string request: "{}"
        stdinEnabled: true
        stderr: ErrorLog { label: "LayoutService.backupProc" }
        stdout: StdioCollector {}
        onStarted: {
            write(request + "\n")
            stdinEnabled = false
        }
        // Opened again for the next run; a backup that failed is tried again
        // on the next switch rather than counted as the day's.
        onExited: code => {
            stdinEnabled = true
            if (code !== 0) {
                console.warn("buchhwin-shell: the backup before a profile switch failed:", code)
                root.backupDay = ""
            }
        }
    }

    // A profile's own name, for a list that is not the active one.
    function profileLabelOf(name) {
        return Logic.profileLabel(config, name)
    }

    // Which of a profile's five modes have been set up, for the line under its
    // card. A mode that is not in the file has never been entered, so saying
    // "five modes" for a profile that has one would be a lie.
    function modeSummary(name) {
        const set = modeNames.filter(entry => Logic.modesOf(config, name)[entry] !== undefined)
        // A count rather than the names: this sits in a row that elides, and
        // three names elided after the first says less than a number.
        if (!set.length) return "Factory state, no mode set up yet"
        if (set.length === modeNames.length) return "All five modes set up"
        return set.length + " of five modes set up"
    }

    // `laptop` and `docked` are not renameable or removable anywhere, so a
    // profile only ever adds, duplicates, renames, removes or resets.
    //
    // A new profile has no state: entered the first time, it keeps the
    // settings, notch and lock screen in use then (enterProfile).
    function addProfile(label) {
        if (readOnly) return ""
        beginProfileChange()
        const step = Logic.addProfile(config, label)
        config = step.config
        revision++
        save()
        return step.name
    }

    // A copy with the source's state: the profile in use is copied as it is
    // set now, any other with the state it was left with.
    function duplicateProfile(name, label) {
        if (readOnly) return ""
        beginProfileChange()
        const state = name === activeProfile && SettingsService.loaded ? currentState() : null
        const step = Logic.duplicateProfile(config, name, label, state)
        config = step.config
        revision++
        save()
        return step.name
    }

    function renameProfile(name, label) {
        if (readOnly) return false
        beginProfileChange()
        config = Logic.renameProfile(config, name, label)
        revision++
        save()
        return true
    }

    // Removing the profile in use is a switch to the one that takes its place
    // (the first left), with that one's state put back - and without storing
    // the state of the one removed, which goes with it.
    function removeProfile(name) {
        if (readOnly || profileNames.length < 2 || isBuiltinProfile(name)) return false
        if (name === activeProfile) {
            if (!loaded || !SettingsService.loaded) return false
            const next = Logic.removeProfile(config, name)
            enterProfile(JSON.parse(JSON.stringify(next)), next.activeProfile)
            return true
        }
        // Its state leaves with it, and the step is the only way back.
        const removed = config.profiles[name]
        const states = {}
        if (removed && removed.state) states[name] = removed.state
        beginProfileChange(Object.keys(states).length ? states : null)
        config = Logic.removeProfile(config, name)
        revision++
        ensureScreens()
        applyModeSettings(activeMode)
        save()
        return true
    }

    // Back to the factory state - one mode of a profile, or all five. Asked for
    // explicitly, because Default itself gets changed and there was no way back
    // from that. A built-in profile goes back to the modes it shipped with,
    // and not before they have been read: the factory templates in their
    // place would be a reset to the wrong state.
    //
    // All five of a built-in profile also bring back its shipped state: at
    // once when it is the profile in use (startBuiltin, with its backup),
    // otherwise by forgetting the stored one, so entering it applies the
    // shipped setup as the first time did. A profile of the user's keeps its
    // state (see LayoutLogic.resetProfile).
    function resetProfile(name, modeName) {
        if (readOnly) return false
        const id = Logic.builtinOf(config, name)
        const shipped = id.length && builtinProfiles[id] ? builtinProfiles[id].modes : null
        if (id.length && !shipped) return false
        const all = !modeName
        // Not while a shipped setup is being applied, like Restore: the run
        // in flight is refused a second start (startBuiltin), and the reset
        // would bring back the modes without the rest.
        if (id.length && all && name === activeProfile && (applyProc.running || builtinApplying.length)) return false
        // A built-in one not in use forgets its state below, which the steps
        // do not hold: its step is handed it, so Undo brings back the user's
        // settings, notch and lock screen with the modes. And the day's backup
        // first, as Restore takes one for the same forgetting (applyBuiltin).
        const dropped = id.length && all && name !== activeProfile ? Logic.stateOf(config, name) : null
        if (dropped) backupToday()
        // The modes reset are the step's, appearance and all: undone, they
        // come back as they were (LayoutLogic.withCurrentAppearance).
        beginProfileChange(dropped ? { [name]: dropped } : null, { [name]: all ? modeNames.slice() : [String(modeName)] })
        config = Logic.resetProfile(config, name, modeName || "", shipped)
        if (id.length && all && name !== activeProfile) config = Logic.withState(config, name, null)
        revision++
        ensureScreens()
        applyModeSettings(activeMode)
        save()
        if (id.length && all && name === activeProfile) startBuiltin(id, name)
        return true
    }

    // ---- built-in profiles ---------------------------------------------------
    // Profiles the repository ships, read from config/builtin-profiles/<id>/
    // the way the notch presets are read from config/notch-presets/. Each one
    // is always in the layout file (added once it has loaded), cannot be
    // removed, and resets to what it shipped with. "default" is the Default
    // profile every layout has (adopted, see LayoutLogic.addBuiltinProfiles),
    // "buchhwin" the user's own setup; both are written by
    // scripts/profile-export.py. A missing file is a profile that is not built
    // in yet, and everything about it stays as it was.
    readonly property var builtinProfileNames: ["default", "buchhwin"]
    // id -> the shipped profile, sanitized (LayoutLogic.sanitizeBuiltinProfile).
    property var builtinProfiles: ({})
    // The id being applied right now, "" when none is; and why the last
    // attempt applied nothing, for the Profiles page.
    property string builtinApplying: ""
    property string builtinError: ""
    // The same per built-in id, so a card can show its own: id -> why its
    // last attempt applied nothing, gone once one goes through.
    property var builtinErrors: ({})
    signal builtinApplied(string id)

    function builtinErrorOf(id) {
        return builtinErrors[String(id)] || ""
    }
    function setBuiltinError(id, error) {
        const next = Object.assign({}, builtinErrors)
        if (error.length) next[id] = error
        else delete next[id]
        builtinErrors = next
    }

    function builtinOf(name) {
        return Logic.builtinOf(config, name)
    }
    function isBuiltinProfile(name) { return builtinOf(name).length > 0 }

    // Every shipped profile the file does not carry yet. One save, through the
    // write timer like every other (pitfall 3), and none when nothing was
    // missing - this runs on every load of the file and as each shipped one
    // and the settings arrive.
    //
    // On a first start the adopted Default takes the shipped modes, and the
    // mode in use was materialized from its template a moment before: it is
    // filled in again from the shipped one, with that mode's appearance.
    // Whether it is one is known once the settings have been read too, so
    // nothing is added before that (decideFresh).
    function ensureBuiltinProfiles() {
        if (!loaded || readOnly || !freshDecided) return
        const shipped = builtinProfileNames.map(id => builtinProfiles[id]).filter(data => !!data)
        if (!shipped.length) return
        const step = Logic.addBuiltinProfiles(config, shipped, freshLayout)
        if (!step.added.length) return
        config = step.config
        if (freshLayout && step.added.indexOf(activeProfile) >= 0) {
            ensureScreens()
            applyModeSettings(activeMode)
        }
        revision++
        save()
    }

    // A built-in profile's shipped setup again: the Restore button and
    // `buchhwin profile restore <name>`. Takes a built-in id or the name of
    // the profile that carries one.
    //
    // For the profile in use it is applied now, after a backup (startBuiltin).
    // Any other one forgets its stored state, so entering it brings the
    // shipped setup back exactly as the first time did; nothing that is set
    // now changes, because it is not that profile's.
    function applyBuiltin(name) {
        const id = builtinProfileNames.indexOf(name) >= 0 ? name : Logic.builtinOf(config, name)
        if (!id.length || !builtinProfiles[id] || readOnly) return false
        const holder = Logic.builtinProfileName(config, id)
        if (!holder.length) return false
        if (holder === activeProfile) return startBuiltin(id, holder)
        backupToday()
        // No undo step: undo leaves the stored states alone (see undo), so
        // it would be a step that takes nothing back.
        config = Logic.withState(config, holder, null)
        revision++
        save()
        return true
    }

    // The whole setup of a built-in profile, for the profile `forProfile`
    // that carries it and is in use: entered without a state, restored, or
    // reset.
    //
    // Nothing is overwritten before the copy of what is there now has been
    // made: profile-apply.py backs up settings.json, layout.json and the
    // session's default-app lists into the state directory first, then puts
    // fastfetch's files in place (with a copy of a different fastfetch.jsonc
    // kept beside it), and answers which of the shipped default apps are
    // installed here, and whether its cursor theme is. Only once it has
    // answered does the rest happen, in `finishBuiltin`. A switch away
    // before then (the profile key pressed twice) means the setup is no
    // longer wanted, and the profile that is active by then keeps its
    // settings.
    function startBuiltin(id, forProfile) {
        if (!id.length || !builtinProfiles[id] || readOnly || applyProc.running) return false
        builtinError = ""
        setBuiltinError(id, "")
        builtinApplying = id
        applyProc.builtinId = id
        applyProc.forProfile = forProfile
        applyProc.command = ["python3", Paths.script("profile-apply.py"),
                             "--from", Quickshell.shellPath("config/builtin-profiles/" + id),
                             "--config-dir", Paths.configDir, "--backup-dir", Paths.stateDir]
        applyProc.running = true
        return true
    }

    // What profile-apply.py answered for the run started for `forProfile`.
    function finishBuiltin(id, forProfile, exitCode, text) {
        builtinApplying = ""
        let result = null
        try {
            const lines = String(text || "").trim().split("\n")
            result = JSON.parse(lines[lines.length - 1])
        } catch (error) {
            result = null
        }
        const data = builtinProfiles[id]
        if (exitCode !== 0 || !result || result.ok !== true) {
            builtinError = result && result.error ? String(result.error) : "The built-in profile could not be applied"
            setBuiltinError(id, builtinError)
            // Nothing of the shipped setup arrived, and it is not tried again
            // on its own: the profile keeps what is set, as one of the user's
            // would, until Restore. Left waiting for it, every switch away
            // stored nothing and every start applied it again.
            if (!readOnly && SettingsService.loaded && activeProfile === forProfile && waitingForShipped(forProfile)) {
                config = Logic.withState(config, forProfile, currentState())
                revision++
                save()
            }
            return
        }
        builtinError = ""
        setBuiltinError(id, "")
        if (!data || readOnly) return
        if (activeProfile !== forProfile) return
        // No undo step, and the ones there are go: entering a profile is not
        // an edit (setActiveProfile starts undo again too), and a step from
        // before the apply would put the old notch and lock screen back under
        // the shipped settings.
        undoStack = []
        // The settings this shell knows, in one write.
        const values = knownValues(profileLeaves(data.settings))
        // The cursor theme only where it is installed (profile-apply.py
        // looks where Xcursor does): a name nothing answers to leaves
        // Hyprland and every toolkit to a fallback cursor of its own.
        const cursor = result.cursor && typeof result.cursor === "object" ? result.cursor : {}
        if (cursor.installed !== true || cursor.theme !== values["appearance.cursorTheme"])
            delete values["appearance.cursorTheme"]
        if (Object.keys(values).length) SettingsService.setAll(values)
        config = Logic.applyBuiltinLayout(config, data)
        // What was applied is the profile's state from now on: it keeps the
        // user's changes to it, and the next entry restores those rather than
        // the shipped setup.
        config = Logic.withState(config, activeProfile, currentState())
        revision++
        save()
        // Only what the script found installed: default-apps.py refuses an id
        // that is not, and that refusal would be the page's error line.
        const apps = result.apps && typeof result.apps === "object" ? result.apps : {}
        for (const category of ["terminal", "files"])
            if (typeof apps[category] === "string" && apps[category] === data.defaultApps[category])
                DefaultAppsService.setDefault(category, apps[category])
        builtinApplied(id)
    }

    // The profile in use is a built-in one still waiting for its shipped
    // setup, entered while another one's was being applied (startBuiltin
    // refuses a second run): its turn comes once that one is done. Only after
    // a run for a profile that is no longer in use, so a run that failed is
    // not simply started again and again.
    function resumeShipped() {
        if (applyProc.running || !waitingForShipped(activeProfile)) return
        startBuiltin(Logic.builtinOf(config, activeProfile), activeProfile)
    }

    Process {
        id: applyProc
        stderr: ErrorLog { label: "LayoutService.applyProc" }
        property string builtinId: ""
        property string forProfile: ""
        // The output may arrive before or after the exit; judge once both are in.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function done() {
            if (!outputDone || exitCode < 0) return
            const left = forProfile !== root.activeProfile
            root.finishBuiltin(builtinId, forProfile, exitCode, output)
            if (left) Qt.callLater(root.resumeShipped)
        }
        stdout: StdioCollector { onStreamFinished: { applyProc.output = text; applyProc.outputDone = true; applyProc.done() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; done() }
    }

    // ---- editing -----------------------------------------------------------

    function updateItem(id, patch) {
        return mutate(mode => {
            const target = mode.widgets.find(entry => entry.id === id) || mode.groups.find(entry => entry.id === id)
            if (target) Object.assign(target, patch)
        })
    }

    function addWidget(screenName, type) {
        const entry = WidgetRegistry.type(type)
        // Not the dock's own pieces: an Apps widget on the desktop is empty
        // while the dock is off, and a start button there opens nothing.
        if (!entry || !entry.available || entry.dockOnly === true) return ""
        let createdId = ""
        mutate(mode => {
            const taken = mode.widgets.map(w => w.id).concat(mode.groups.map(g => g.id))
            createdId = Logic.uniqueId(type + "-" + screenName, taken)
            const widget = Object.assign({ visible: true, scale: 1, group: "", options: entry.options || {} },
                                         entry.defaults, { id: createdId, type: type, screen: screenName })
            mode.widgets.push(widget)
            if (mode.screens.indexOf(screenName) < 0) mode.screens.push(screenName)
        })
        return createdId
    }

    function removeItem(id) {
        return removeItems([id])
    }

    // Several at once - the editor's selection - in one edit rather than one
    // per item.
    function removeItems(ids) {
        const list = (Array.isArray(ids) ? ids : []).map(String)
        if (!list.length) return false
        return mutate(mode => {
            for (const id of list) {
                const target = mode.groups.find(entry => entry.id === id)
                if (target) {
                    mode.widgets = mode.widgets.filter(entry => target.members.indexOf(entry.id) < 0)
                    mode.groups = mode.groups.filter(entry => entry.id !== id)
                } else {
                    mode.widgets = mode.widgets.filter(entry => entry.id !== id)
                    for (const entry of mode.groups) entry.members = entry.members.filter(member => member !== id)
                }
            }
        })
    }

    function moveToScreen(id, screenName) {
        return mutate(mode => {
            const target = mode.widgets.find(entry => entry.id === id) || mode.groups.find(entry => entry.id === id)
            if (!target) return
            target.screen = screenName
            if (target.members)
                for (const entry of mode.widgets)
                    if (target.members.indexOf(entry.id) >= 0) entry.screen = screenName
            if (mode.screens.indexOf(screenName) < 0) mode.screens.push(screenName)
        })
    }

    function groupItems(ids) {
        const widgets = ids.map(id => widget(id)).filter(entry => entry && !entry.group.length)
        if (widgets.length < 2) return ""
        let groupId = ""
        mutate(mode => {
            const first = widgets[0]
            const taken = mode.widgets.map(w => w.id).concat(mode.groups.map(g => g.id))
            groupId = Logic.uniqueId("group-" + first.screen, taken)
            const sorted = widgets.slice().sort((a, b) => a.x - b.x).map(entry => entry.id)
            mode.groups.push({ id: groupId, screen: first.screen, anchorX: first.anchorX, x: first.x, y: first.y,
                                  scale: 1, style: "capsule", visible: true, members: sorted })
            for (const entry of mode.widgets)
                if (sorted.indexOf(entry.id) >= 0) { entry.group = groupId; entry.screen = first.screen }
        })
        return groupId
    }

    function ungroup(groupId) {
        return mutate(mode => {
            const target = mode.groups.find(entry => entry.id === groupId)
            if (!target) return
            let offset = 0
            for (const memberId of target.members) {
                const entry = mode.widgets.find(item => item.id === memberId)
                if (!entry) continue
                entry.group = ""
                entry.anchorX = target.anchorX
                entry.x = target.x
                entry.y = Math.min(1, target.y + offset)
                offset += 0.06
            }
            mode.groups = mode.groups.filter(entry => entry.id !== groupId)
        })
    }

    function moveMember(groupId, memberId, delta) {
        return mutate(mode => {
            const target = mode.groups.find(entry => entry.id === groupId)
            if (!target) return
            const index = target.members.indexOf(memberId)
            const next = index + delta
            if (index < 0 || next < 0 || next >= target.members.length) return
            target.members.splice(index, 1)
            target.members.splice(next, 0, memberId)
        })
    }

    // A widget window reports on every change of its position or size, and
    // most of those are the same rectangle again (its position is rebound
    // when the screen's size changes, its implicit size whenever a child's
    // does). Everything that reads `placementRects` rebuilds on the signal,
    // so a report that changes nothing stays out of it - the way the cell
    // reports below do.
    function reportRect(screenName, id, rect) {
        const key = screenName + "/" + id
        const current = placementRects[key]
        if (current && rect && current.x === rect.x && current.y === rect.y
                && current.width === rect.width && current.height === rect.height) return
        const next = Object.assign({}, placementRects)
        next[key] = rect
        placementRects = next
    }

    // Where the parts of a surface the editor cannot host are on screen, so it
    // can work on the real thing instead of on a copy of it below. The bar and
    // the notch are each their own layer surface, and the editor covers both.
    // Keys: a pill id, `pill#index` for one of its items, `zone:left`,
    // `notch:<id>` and `notchzone:collapsed`. Reported only while the editor
    // is open, and dropped when it closes.
    property var surfaceRects: ({})
    // The pill the editor has selected, so the real bar can hold that one
    // still while its neighbours lean.
    property string editorSelection: ""
    // The pill the editor is dragging right now, so a test can see that the
    // drag really started rather than only that the drop landed.
    property string editorDragging: ""
    // The id an arrange surface is dragging right now, "" when none is. It is
    // here rather than in the surface so Escape and the panel's own close path
    // can see it, and so a test can ask whether a drag is running without a
    // screenshot (`editor get`).
    property string arrangeDragging: ""

    function reportSurfaceRect(screenName, key, rect) {
        const full = screenName + "/" + key
        const current = surfaceRects[full] || null
        if (JSON.stringify(current) === JSON.stringify(rect)) return
        const next = Object.assign({}, surfaceRects)
        if (rect === null) delete next[full]
        else next[full] = rect
        surfaceRects = next
    }

    function surfaceRect(screenName, key) {
        return surfaceRects[screenName + "/" + key] || null
    }

    // Where the control center's tiles are resting, in the grid's own
    // coordinates. A drag cannot be screenshotted - it is over before a
    // screenshot can catch it - so this is how a test asks where a tile
    // really landed rather than believing that it did. Reported while the
    // panel is open and dropped when it closes; the resting cells, never an
    // item's own animated x and y.
    property var quickCells: ({})
    function reportQuickCells(cells) {
        if (JSON.stringify(quickCells) === JSON.stringify(cells)) return
        quickCells = cells || ({})
    }

    // The same, for the dashboard's cards.
    property var dashboardCells: ({})
    function reportDashboardCells(cells) {
        if (JSON.stringify(dashboardCells) === JSON.stringify(cells)) return
        dashboardCells = cells || ({})
    }

    // And for the launcher's blocks, the way the other two report theirs: a
    // drag is over before a screenshot can catch it.
    property var launcherCells: ({})
    function reportLauncherCells(cells) {
        if (JSON.stringify(launcherCells) === JSON.stringify(cells)) return
        launcherCells = cells || ({})
    }

    // Rectangle of the first visible clock on a screen, if any. In notch mode
    // the collapsed notch is the clock.
    function clockRect(screenName) {
        if (notchShown) return notchRect(screenName)
        if (!widgetsShown) return null
        for (const id of placementIds(screenName, false)) {
            const target = item(id)
            const isClock = target && (target.type === "clock"
                || (target.members && members(id).some(entry => entry.type === "clock")))
            if (isClock && placementRects[screenName + "/" + id]) return placementRects[screenName + "/" + id]
        }
        return null
    }

    Connections {
        target: Quickshell
        function onScreensChanged() { root.ensureScreens() }
    }

    // layout.json is the user's alone (0600), as settings.json is (see
    // SettingsService.keepPrivate): it names their apps, their profiles and
    // what their desktops hold. Once at the first read and once after the
    // first write of a start; the atomic write keeps the mode after that.
    property bool privateRead: false
    property bool privateWritten: false
    function keepPrivate(written) {
        if (written ? privateWritten : privateRead) return
        if (written) privateWritten = true
        else privateRead = true
        Quickshell.execDetached(["chmod", "600", "--", layoutPath])
    }

    FileView {
        id: layoutFile
        path: root.layoutPath
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: { root.unreadableReason = ""; root.load(); root.adoptOnce(); root.keepPrivate(false) }
        // Missing at startup means a fresh layout; later it is a replacement in
        // progress. Any other failure is a file that is there (unreadableReason).
        onLoadFailed: error => {
            if (root.loaded) return
            if (error !== FileViewError.FileNotFound)
                root.unreadableReason = "layout.json cannot be read (" + FileViewError.toString(error) + ")"
            root.load()
        }
        onFileChanged: reload()
        onSaved: root.keepPrivate(true)
        onSaveFailed: error => {
            if (root.saveFailedWarned) return
            root.saveFailedWarned = true
            console.warn("buchhwin-shell: layout.json could not be written (" + FileViewError.toString(error)
                         + "): changes are lost when the shell restarts")
        }
    }

    // The version the backup below is of. 0 while nothing has been migrated,
    // so the FileView has a path but writes nothing.
    property int backupVersion: 0

    FileView {
        id: backupFile
        path: Paths.configDir + "/layout.v" + Math.max(1, root.backupVersion) + ".backup.json"
        printErrors: false
        // As private as the file it is a copy of.
        onSaved: Quickshell.execDetached(["chmod", "600", "--", path])
    }

    // The built-in notch presets, read like the mode templates.
    Instantiator {
        model: root.builtinNotchPresetNames
        delegate: FileView {
            required property string modelData
            path: Quickshell.shellPath("config/notch-presets/" + modelData + ".json")
            printErrors: false
            onLoaded: {
                try {
                    const preset = Logic.sanitizeNotchPreset(JSON.parse(text()), true)
                    if (!preset) return
                    preset.id = modelData
                    const order = root.builtinNotchPresetNames
                    root.builtinNotchPresets = root.builtinNotchPresets.filter(item => item.id !== modelData)
                        .concat([preset]).sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id))
                } catch (error) {
                    console.warn("buchhwin-shell: notch preset unreadable:", modelData, error)
                }
            }
        }
    }

    // The dock's presets, read the same way.
    Instantiator {
        model: root.builtinDockPresetNames
        delegate: FileView {
            required property string modelData
            path: Quickshell.shellPath("config/dock-presets/" + modelData + ".json")
            printErrors: false
            onLoaded: {
                try {
                    const preset = Logic.sanitizeDockPreset(JSON.parse(text()))
                    if (!preset) return
                    preset.id = modelData
                    const order = root.builtinDockPresetNames
                    root.builtinDockPresets = root.builtinDockPresets.filter(item => item.id !== modelData)
                        .concat([preset]).sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id))
                } catch (error) {
                    console.warn("buchhwin-shell: dock preset unreadable:", modelData, error)
                }
            }
        }
    }

    // The shipped profiles, read once like the notch presets above. Added to
    // the layout as soon as both this and the layout file are in, whichever
    // comes last. A missing one (a profile not exported yet) is read too, as
    // nothing: the state of the profile in use is settled only once every
    // one has answered, so it is never settled before its shipped setup is
    // known.
    Instantiator {
        model: root.builtinProfileNames
        delegate: FileView {
            required property string modelData
            path: Quickshell.shellPath("config/builtin-profiles/" + modelData + "/profile.json")
            printErrors: false
            onLoaded: {
                try {
                    const data = Logic.sanitizeBuiltinProfile(JSON.parse(text()), modelData)
                    if (data) {
                        const next = Object.assign({}, root.builtinProfiles)
                        next[modelData] = data
                        root.builtinProfiles = next
                        root.ensureBuiltinProfiles()
                    }
                } catch (error) {
                    console.warn("buchhwin-shell: built-in profile unreadable:", modelData, error)
                }
                root.markBuiltinRead(modelData)
            }
            onLoadFailed: root.markBuiltinRead(modelData)
        }
    }

    // The factory state: one file per mode. A new profile is built from these,
    // not from the Default profile.
    Instantiator {
        model: root.modeNames
        delegate: FileView {
            required property string modelData
            path: Quickshell.shellPath("config/profiles/" + modelData + ".json")
            printErrors: false
            onLoaded: {
                try {
                    const next = Object.assign({}, root.templates)
                    next[modelData] = JSON.parse(text())
                    root.templates = next
                    root.ensureScreens()
                    root.adoptOnce()
                    root.resumeDndOnce()
                } catch (error) {
                    console.warn("buchhwin-shell: mode template unreadable:", modelData, error)
                }
            }
        }
    }
}
