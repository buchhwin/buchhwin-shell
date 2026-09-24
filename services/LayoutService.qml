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
    property int revision: 0
    property bool loaded: false
    property bool readOnly: false
    property string readOnlyReason: ""
    property bool editMode: false
    property var undoStack: []
    property var templates: ({})
    // The five modes every profile has, and the profiles themselves - the
    // first list is fixed (each one has a factory template), the second is the
    // user's.
    readonly property var modeNames: Logic.MODE_NAMES
    readonly property var profileNames: (revision, Logic.profileNames(config))
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

    signal changed()

    // The active mode of the active profile. A mode that is not in the file
    // yet reads as an empty one rather than as nothing at all.
    function modeConfig() {
        const unused = revision
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
        beginChange()
        mutate(mode => { mode.bar = operation.apply(null, [mode.bar || Logic.defaultBar()].concat(args)) })
        save()
        return true
    }

    function barAddPill(zone, type, display) { return changeBar(Logic.addPill, zone, type, display || defaultDisplay(type)) }
    function barAddItem(pillId, type, display) { return changeBar(Logic.addItem, pillId, type, display || defaultDisplay(type)) }
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

    // ---- quick settings ---------------------------------------------------
    // The control center's tiles, on the same model as the bar. They are
    // edited inside the control center itself rather than in the layout
    // editor: the editor is a full-screen surface with exclusive keyboard
    // focus, and so is the control center - two of them at once is the trap
    // that keeps Alt+Tab out of the panel system.
    // The notch's two lists. Outside `profiles`, because the notch is the same
    // on every profile and every mode - the rest of its options are in
    // settings.json, which
    // cannot hold a list at all (see the note in LayoutLogic).
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
    function notchAdd(type, zone) { return changeNotchLayout(Logic.addNotchItem, type, zone) }
    function notchResetLayout() { return changeNotchLayout(() => Logic.defaultNotch()) }

    // The lock screen's grid. Outside `profiles` like the notch: there is one
    // lock screen whatever the desktop mode says about monitors. The lock
    // screen itself is another process and only ever reads this file; it is
    // arranged in Settings, on a preview, because editing a surface whose
    // whole job is to be modal is a trap.
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

    function quickMove(tileId, delta) { return changeQuick(Logic.moveQuickTile, tileId, delta) }
    function quickMoveTo(tileId, index) { return changeQuick(Logic.moveQuickTileTo, tileId, index) }
    function quickSetSize(tileId, w, h) { return changeQuick(Logic.setQuickTileSize, tileId, w, h) }
    function quickRemove(tileId) { return changeQuick(Logic.removeQuickTile, tileId) }
    function quickAdd(type) { return changeQuick(Logic.addQuickTile, type, isKnownType) }
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
    function dashboardAdd(type) { return changeDashboard(Logic.addDashboardCard, type, isKnownType) }
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

    function launcherHas(type) { return launcherTypes.indexOf(String(type)) >= 0 }
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
    // offered twice.
    function widgetChoices(taken) {
        return WidgetRegistry.availableTypes()
            .filter(widget => (taken || []).indexOf(widget.name) < 0)
            .map(widget => ({ type: widget.name, label: widget.label, icon: widget.icon }))
    }
    function tileChoices(own, taken) {
        return (own || []).concat(widgetChoices(taken))
    }

    function placementIds(screenName, includeHidden) {
        const unused = revision
        return Logic.placements(modeConfig(), screenName, includeHidden === true)
            .filter(id => {
                const entry = root.widget(id)
                return !entry || isKnownType(entry.type)
            })
    }

    function widget(id) {
        const unused = revision
        return modeConfig().widgets.find(item => item.id === id) || null
    }

    function group(id) {
        const unused = revision
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

    function screenWidgets(screenName) {
        const unused = revision
        return modeConfig().widgets.filter(item => item.screen === screenName)
    }

    // ---- persistence -------------------------------------------------------

    function load() {
        const text = layoutFile.text()
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
        readOnly = result.readOnly
        readOnlyReason = result.error || ""
        if (result.readOnly)
            console.warn("buchhwin-shell: layout is read-only:", result.error)
        // Every migration keeps the file it read, named after the version it
        // was. It used to be v1 only, which was right while v1 was the only
        // migration there had ever been; a migration that turns out to be
        // wrong is exactly the moment the old file is worth having, and that
        // is not something the first one has a monopoly on.
        const migrated = result.ok && result.changed && result.from >= 1
        backupVersion = migrated ? result.from : 0
        config = Logic.sanitize(result.config)
        notchStored = !!(result.config && result.config.notch)
        loaded = true
        ensureScreens()
        adoptOnce()
        revision++
        if (migrated) {
            pendingBackup = text
            backupTimer.restart()
            save()
        }
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
        if (readOnly || !loaded || !SettingsService.loaded) return
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
        changed()
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
        changed()
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
                if (!modes[name]) modes[name] = { widgets: [], groups: [], screens: [] }
                modes[name].appearance = Object.assign(appearance, modes[name].appearance || {})
            }
            next.profiles[profileName].modes = modes
        }
        next.adopted = Logic.withAdopted(next, "modeAppearance")
        config = Logic.sanitize(next)
        revision++
        changed()
        return true
    }

    Connections {
        target: SettingsService
        function onLoadedChanged() {
            if (!SettingsService.loaded) return
            root.adoptOnce()
        }
    }

    // One write per turn of the event loop, and never from inside the load
    // that is finishing. `load()` and `adoptOnce()` run from the file's own
    // `loaded` handler, and a `setText` from there wrote the file inside the
    // callback of the read being finished - the FileView drops that read and
    // Quickshell logs "got operation finished from dropped operation", which
    // the smoke test fails on (docs/testing.md > Pitfalls; SettingsService
    // writes the same way). The text is taken when the write is asked for,
    // not when it runs, so a reload that lands in between cannot put an
    // older layout back on disk.
    property string pendingText: ""
    function save() {
        if (readOnly || !loaded) return false
        pendingText = JSON.stringify(Logic.sanitize(config), null, 2) + "\n"
        writeTimer.restart()
        return true
    }
    Timer { id: writeTimer; interval: 0; onTriggered: layoutFile.setText(root.pendingText) }
    // The copy a migration keeps of the file it read, written the same way
    // and for the same reason: it is asked for from `load()`.
    property string pendingBackup: ""
    Timer { id: backupTimer; interval: 0; onTriggered: backupFile.setText(root.pendingBackup) }

    // Every edit lands in the active mode of the active profile. The callback
    // gets that mode and the whole config, because a few things it may change -
    // the notch, the adoption markers - are global.
    function mutate(callback) {
        if (readOnly) return false
        const next = JSON.parse(JSON.stringify(config))
        if (!next.profiles[activeProfile])
            next.profiles[activeProfile] = { label: Logic.DEFAULT_PROFILE_LABEL, modes: {} }
        const modes = next.profiles[activeProfile].modes
        if (!modes[activeMode]) modes[activeMode] = { widgets: [], groups: [], screens: [] }
        callback(modes[activeMode], next)
        config = Logic.sanitize(next)
        revision++
        changed()
        return true
    }

    // The notch is not in the layout file - it is the same everywhere, so
    // it lives in settings.json. Its options are still edited in the editor,
    // and Ctrl+Z there has to reach them, so an undo step carries them along.
    readonly property var notchKeys: ["notch.eventCount", "notch.expandOnHover", "notch.reserve",
                                      "notch.fullscreen", "notch.shape", "notch.collapsedWidth",
                                      "notch.expandedWidth", "notch.expandedHeight"]
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

    function beginChange() {
        if (readOnly) return
        const next = undoStack.slice()
        next.push(JSON.stringify({ config: config, notch: notchSnapshot() }))
        if (next.length > 30) next.shift()
        undoStack = next
    }

    // Notch options change settings only, so they take an undo step of their
    // own rather than going through changeBar/mutate.
    function changeNotch(key, value) {
        if (notchKeys.indexOf(key) < 0) return false
        beginChange()
        SettingsService.set(key, value)
        return true
    }

    function undo() {
        if (!undoStack.length || readOnly) return
        const next = undoStack.slice()
        const step = JSON.parse(next.pop())
        config = Logic.sanitize(step.config)
        const restored = {}
        for (const key of undoKeys)
            if (step.notch && step.notch[key] !== undefined) restored[key] = step.notch[key]
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
        // Materialized in memory; written with the next edit.
        const next = JSON.parse(JSON.stringify(config))
        if (!next.profiles[activeProfile])
            next.profiles[activeProfile] = { label: Logic.DEFAULT_PROFILE_LABEL, modes: {} }
        const modes = next.profiles[activeProfile].modes
        const fresh = !modes[activeMode]
        const nextMode = modes[activeMode] || { widgets: [], groups: [], screens: [] }
        // A mode used for the first time takes its desktop mode and its bar
        // from the template too.
        if (fresh) {
            if (template.mode) nextMode.desktopMode = template.mode
            if (template.bar) nextMode.bar = template.bar
        }
        for (const screen of missing) {
            const made = Logic.materialize(template, screen, nextMode.widgets.map(w => w.id)
                .concat(nextMode.groups.map(g => g.id)), type => WidgetRegistry.type(type) !== null)
            nextMode.widgets = nextMode.widgets.concat(made.widgets)
            nextMode.groups = nextMode.groups.concat(made.groups)
            nextMode.screens.push(screen)
        }
        modes[activeMode] = nextMode
        config = Logic.sanitize(next)
        revision++
    }

    // ---- the mode: one of the five ----------------------------------------
    // What `setActiveProfile` did before v3. The settings a mode owns
    // (ProfileLogic.MODE_SCOPED) are applied here, from the mode's own stored
    // block or, for a mode nobody has customized, from its template's
    // `effects`.
    function setActiveMode(name) {
        if (modeNames.indexOf(name) < 0 || readOnly) return false
        beginChange()
        const next = JSON.parse(JSON.stringify(config))
        next.activeMode = name
        config = Logic.sanitize(next)
        ensureScreens()
        applyModeSettings(name)
        revision++
        save()
        return true
    }

    // True while a mode's own settings are being written into SettingsService,
    // so the handler below does not write them straight back into the mode
    // they just came from.
    property bool applyingMode: false

    function applyModeSettings(name) {
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
        applyingMode = true
        if (Object.keys(values).length) SettingsService.setAll(values)
        applyingMode = false
        // Do Not Disturb is not a setting, it is session state, so it is not on
        // the mode-scoped list and stays where it was: applied from the
        // template when the mode is entered.
        if (effects.dnd && typeof NotificationService !== "undefined" && NotificationService.setDnd)
            NotificationService.setDnd(effects.dnd)
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
            root.mutate(mode => {
                const appearance = Object.assign({}, mode.appearance || {})
                appearance[leaf] = value
                mode.appearance = appearance
            })
            root.save()
        }
    }

    // ---- the profile: the level above --------------------------------------

    function setActiveProfile(name) {
        if (profileNames.indexOf(name) < 0 || readOnly) return false
        beginChange()
        const next = JSON.parse(JSON.stringify(config))
        next.activeProfile = name
        config = Logic.sanitize(next)
        ensureScreens()
        applyModeSettings(activeMode)
        revision++
        save()
        return true
    }

    // A profile's own name, for a list that is not the active one.
    function profileLabelOf(name) {
        const unused = revision
        return Logic.profileLabel(config, name)
    }

    // Which of a profile's five modes have been set up, for the line under its
    // card. A mode that is not in the file has never been entered, so saying
    // "five modes" for a profile that has one would be a lie.
    function modeSummary(name) {
        const unused = revision
        const set = modeNames.filter(entry => Logic.modesOf(config, name)[entry] !== undefined)
        // A count rather than the names: this sits in a row that elides, and
        // three names elided after the first says less than a number.
        if (!set.length) return "Factory state, no mode set up yet"
        if (set.length === modeNames.length) return "All five modes set up"
        return set.length + " of five modes set up"
    }

    // `laptop` and `docked` are not renameable or removable anywhere, so a
    // profile only ever adds, duplicates, renames, removes or resets.
    function addProfile(label) {
        if (readOnly) return ""
        beginChange()
        const step = Logic.addProfile(config, label)
        config = step.config
        revision++
        changed()
        save()
        return step.name
    }

    function duplicateProfile(name, label) {
        if (readOnly) return ""
        beginChange()
        const step = Logic.duplicateProfile(config, name, label)
        config = step.config
        revision++
        changed()
        save()
        return step.name
    }

    function renameProfile(name, label) {
        if (readOnly) return false
        beginChange()
        config = Logic.renameProfile(config, name, label)
        revision++
        changed()
        save()
        return true
    }

    function removeProfile(name) {
        if (readOnly || profileNames.length < 2) return false
        beginChange()
        config = Logic.removeProfile(config, name)
        revision++
        changed()
        ensureScreens()
        applyModeSettings(activeMode)
        save()
        return true
    }

    // Back to the factory state - one mode of a profile, or all five. Asked for
    // explicitly, because Default itself gets changed and there was no way back
    // from that.
    function resetProfile(name, modeName) {
        if (readOnly) return false
        beginChange()
        config = Logic.resetProfile(config, name, modeName || "")
        revision++
        changed()
        ensureScreens()
        applyModeSettings(activeMode)
        save()
        return true
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
        if (!entry || !entry.available) return ""
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
        return mutate(mode => {
            const target = mode.groups.find(entry => entry.id === id)
            if (target) {
                mode.widgets = mode.widgets.filter(entry => target.members.indexOf(entry.id) < 0)
                mode.groups = mode.groups.filter(entry => entry.id !== id)
            } else {
                mode.widgets = mode.widgets.filter(entry => entry.id !== id)
                for (const entry of mode.groups) entry.members = entry.members.filter(member => member !== id)
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

    function reportRect(screenName, id, rect) {
        const next = Object.assign({}, placementRects)
        next[screenName + "/" + id] = rect
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

    FileView {
        id: layoutFile
        path: root.layoutPath
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: { root.load(); root.adoptOnce() }
        // Missing at startup means a fresh layout; later it is a replacement in progress.
        onLoadFailed: if (!root.loaded) root.load()
        onFileChanged: reload()
    }

    // The version the backup below is of. 0 while nothing has been migrated,
    // so the FileView has a path but writes nothing.
    property int backupVersion: 0

    FileView {
        id: backupFile
        path: Paths.configDir + "/layout.v" + Math.max(1, root.backupVersion) + ".backup.json"
        printErrors: false
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
                } catch (error) {
                    console.warn("buchhwin-shell: mode template unreadable:", modelData, error)
                }
            }
        }
    }
}
