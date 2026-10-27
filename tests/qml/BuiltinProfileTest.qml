import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.theme
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/profile/ProfileLogic.js" as P
import "../../services/arrange/ArrangeLogic.js" as Arrange

// The profiles the repository ships (config/builtin-profiles/<id>). First the
// pure half: always added and only once, never over a profile of the user's
// that carries the same name, not removable, reset to the shipped modes, and
// the settings it writes being everything but what the modes own. Then
// LayoutService against the runner's sandbox: the real "buchhwin" profile is
// added once the layout has loaded, and entering it the first time backs up,
// installs fastfetch's files and applies the settings, the notch and the lock
// screen, which become its state - all of it inside the sandbox's XDG
// directories. After that it keeps the user's changes; Restore and Reset bring
// the shipped setup back. A run that fails leaves it a profile like the
// user's own, and a cursor theme this machine lacks is not set.
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0
    property bool appliedSignal: false

    FileView {
        id: shippedFile
        path: Qt.resolvedUrl("../../config/builtin-profiles/buchhwin/profile.json").toString().replace("file://", "")
        blockLoading: true
    }
    FileView {
        id: shippedDefaultFile
        path: Qt.resolvedUrl("../../config/builtin-profiles/default/profile.json").toString().replace("file://", "")
        blockLoading: true
    }

    // The panel's own lines around its cards: the header (as measured, its
    // title row), the padding above and below, the gap under the header and
    // the space the scroll list keeps (DashboardPanel's ScrollList).
    readonly property int dashboardChrome: 41 + Metrics.panelPadding * 2 + Metrics.panelGap + Metrics.spaceLg

    // How tall a mode's dashboard grid is at the width the profile ships.
    function dashboardGridHeight(mode, storedWidth) {
        const width = (storedWidth > 0 ? storedWidth : Metrics.dashboardWidth) - Metrics.panelPadding * 2
        const columns = Arrange.columnsFor(width, Metrics.dashboardGridCell, Metrics.dashboardGridColumns)
        const cells = ((mode.dashboard || {}).dashboard || []).map(group => ({ id: group.id, w: group.items[0].w, h: group.items[0].h }))
        const rows = Arrange.gridRows(cells, columns)
        return rows > 0 ? rows * Metrics.dashboardGridUnit + (rows - 1) * Metrics.cardGridGap : 0
    }
    // The body the shipped profile's notch should have: Island's, which the
    // profile's notch is.
    FileView {
        id: islandFile
        path: Qt.resolvedUrl("../../config/notch-presets/island.json").toString().replace("file://", "")
        blockLoading: true
    }
    FileView {
        id: fastfetchFile
        path: Paths.configDir + "/fastfetch.jsonc"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: backupFile
        path: Paths.stateDir + "/backup-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + "/layout.json"
        blockLoading: true
        printErrors: false
    }

    Connections {
        target: LayoutService
        function onBuiltinApplied(id) { root.appliedSignal = id === "buchhwin" }
    }

    function mode(widgets) {
        return { widgets: widgets, groups: [], screens: ["DP-1"], desktopMode: "notch" }
    }
    // A mode template (config/profiles/<mode>.json), with a FileView of its
    // own (pitfall 91).
    function template(name) {
        const view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
        view.path = Qt.resolvedUrl("../../config/profiles/" + name + ".json").toString().replace("file://", "")
        const data = JSON.parse(view.text())
        view.destroy()
        return data
    }

    Component.onCompleted: {
        // ---- the shipped file ------------------------------------------------
        const raw = JSON.parse(shippedFile.text())
        const shipped = L.sanitizeBuiltinProfile(raw, "buchhwin")
        T.ok(shipped !== null, "the shipped profile reads")
        T.eq(shipped.id, "buchhwin", "under its id")
        T.eq(P.slug(shipped.id), shipped.id, "and the id is a profile name as ProfileLogic makes them")
        T.eq(Object.keys(shipped.modes).sort(), ["docked", "gaming", "laptop", "minimal", "work"],
             "with all five modes")
        T.eq(shipped.defaultApps, { terminal: "Alacritty.desktop", files: "org.kde.dolphin.desktop" },
             "and the two default apps")
        T.eq([raw.settings.power, raw.settings.lock.fingerprint], [undefined, undefined],
             "nothing of the machine's: no power settings, no fingerprint reader")
        T.eq([raw.settings.appearance.accentFromWallpaper, raw.settings.appearance.accent], [false, "#50e2cb"],
             "the measured accent, not one from a wallpaper another machine does not have")
        const islandBody = JSON.parse(islandFile.text()).options
        T.eq(["bodyHeight", "bodyRadius", "bodyPadding"].map(key => raw.settings.notch[key]),
             [islandBody.bodyHeight, islandBody.bodyRadius, islandBody.bodyPadding],
             "its notch has the Island preset's body, so applying Island changes nothing about it")
        T.eq(raw.settings.wallpaper.path, "", "no wallpaper path of the machine it was exported on")
        // Minimal mode's dashboard: two columns of equal height, so the Today
        // card under the weather is not cut off.
        const heightOf = type => raw.modes.minimal.dashboard.dashboard
            .map(group => group.items[0]).find(item => item.type === type).h
        T.eq([heightOf("weather"), heightOf("clock") + heightOf("calendar")], [4, heightOf("weather") + heightOf("events")],
             "minimal mode's dashboard columns are balanced: weather 4, clock + calendar = weather + events")

        // ---- both shipped profiles --------------------------------------------
        const rawDefault = JSON.parse(shippedDefaultFile.text())
        for (const profile of [raw, rawDefault]) {
            const desktop = profile.settings.desktop
            // A stored height is a ceiling the cards scroll under. Shipped
            // below what its cards need, the dashboard opened scrolling, with
            // the Today card cut through its first row; 0 lets the card
            // measure what it carries.
            const tallest = Math.max(...Object.keys(profile.modes).map(name =>
                root.dashboardGridHeight(profile.modes[name], desktop.dashboardWidth)))
            T.ok(desktop.dashboardHeight === 0 || desktop.dashboardHeight >= tallest + root.dashboardChrome,
                 profile.id + "'s dashboard fits its cards (stored " + desktop.dashboardHeight + ", cards "
                 + tallest + " + " + root.dashboardChrome + ")")
            T.eq(profile.settings.appearance.accentFromWallpaper, false,
                 profile.id + ": the accent as measured, not one from a wallpaper another machine does not have")
        }
        T.eq(rawDefault.settings.desktop.launcherWidth, 0,
             "Default's launcher opens at its designed width, where its mode names and categories fit")
        // Default's dark panels at 0.88 in every mode: at the default 0.74 the
        // muted text on its cards came to 3.3:1 over its own wallpaper, where
        // text wants 4.5:1. The opacity is a mode's (ProfileLogic.MODE_SCOPED)
        // and a profile's settings skip it, so each mode carries it; the four
        // Default does not shape itself ship as entering them would make them
        // - their template's desktop mode and bar, the rest left to it.
        const modeNames = ["minimal", "work", "gaming", "laptop", "docked"]
        T.eq(Object.keys(rawDefault.modes), modeNames, "Default ships all five modes")
        T.eq(modeNames.map(name => rawDefault.modes[name].appearance), modeNames.map(() => ({ panelOpacity: 0.88 })),
             "each with its panels at 0.88 and nothing else of the appearance: gaming's and laptop's effects still apply")
        T.eq(rawDefault.settings.appearance.panelOpacity, undefined, "and none in its settings, which would be skipped")
        const sanitizedDefault = L.sanitizeBuiltinProfile(rawDefault, "default")
        T.eq(modeNames.map(name => sanitizedDefault.modes[name].appearance.panelOpacity), modeNames.map(() => 0.88),
             "kept as the file is read")
        for (const name of modeNames.slice(1)) {
            const own = Object.assign({}, rawDefault.modes[name])
            delete own.appearance
            T.eq(L.sanitizeProfile({ modes: { [name]: own } }).modes[name],
                 L.sanitizeProfile({ modes: { [name]: L.freshMode(root.template(name)) } }).modes[name],
                 "Default's " + name + " is its template's, as a first entry makes it")
        }
        // One order for the status readouts wherever a bar carries them: the
        // battery at the outer end, where its percent is.
        for (const name of ["work", "laptop", "docked"]) {
            const status = shipped.modes[name].bar.right.map(pill => pill.items.map(item => item.type))
                .find(types => types.indexOf("battery") >= 0)
            T.eq(status, ["network", "volume", "battery"], name + "'s bar: network, volume, battery")
        }
        T.eq(shipped.modes.laptop.bar.right[shipped.modes.laptop.bar.right.length - 1].items.map(item => item.type),
             ["notificationIndicator", "quickPanel"], "laptop's bar shows unread notifications beside the control center")
        // Each mode a surface of its own (the four were once the same
        // placeholder, the widgets and the default bar), minimal as it was.
        T.eq(["minimal", "work", "gaming", "laptop", "docked"].map(name => shipped.modes[name].desktopMode),
             ["notch", "pills", "notch", "pills", "pills"], "minimal and gaming the notch, work, laptop and docked a bar")
        T.eq([shipped.modes.work.bar.style, shipped.modes.laptop.bar.style, shipped.modes.laptop.bar.position, shipped.modes.laptop.bar.scale],
             ["pills", "bar", "attached", 0.9], "work floats its pills, laptop has a slim attached bar")
        T.eq(shipped.modes.work.bar.left[0].items[0].type === "workspace" && shipped.modes.work.bar.left[0].items[0].options.style, "dots",
             "its bars draw the workspaces as dots, like its island")
        T.eq([raw.modes.gaming.appearance.animationMode, raw.modes.gaming.appearance.blurStrength,
              raw.modes.laptop.appearance.gapsIn, raw.modes.laptop.appearance.gapsOut], ["reduced", 0, 4, 8],
             "gaming: reduced motion and no blur; laptop: tighter gaps")
        T.eq([raw.modes.work.screens, raw.modes.docked.widgets], [[], []], "their widgets come from the templates on the first entry")
        T.eq(L.sanitizeBuiltinProfile({ label: "x" }, "x"), null, "a file without modes is nothing to add")
        T.eq(L.sanitizeBuiltinProfile(raw, "Not A Slug"), null, "nor is one under an id that is not a profile name")
        T.eq(L.sanitizeBuiltinProfile({ modes: {}, defaultApps: { terminal: "../evil.desktop", files: "x" } }, "y").defaultApps,
             {}, "a default app is a desktop id or nothing")

        // ---- always there, and only once ---------------------------------------
        const small = { id: "buchhwin", label: "buchhwin", modes: { work: root.mode([]) } }
        const fresh = L.sanitize({})
        const once = L.addBuiltinProfiles(fresh, [small])
        T.eq(once.added, ["buchhwin"], "a missing built-in profile is added under its id")
        T.eq(L.profileNames(once.config), ["default", "buchhwin"], "beside the profile that was there")
        T.eq(L.builtinOf(once.config, "buchhwin"), "buchhwin", "marked as the built-in one")
        T.eq(once.config.activeProfile, "default", "adding it does not switch to it")
        T.eq(L.modeConfig(once.config, "buchhwin", "work").desktopMode, "notch", "with the modes it shipped with")
        const twice = L.addBuiltinProfiles(once.config, [small])
        T.eq(twice.added, [], "added once, not twice")
        T.eq(L.profileNames(twice.config), ["default", "buchhwin"], "so the file is left as it was")
        T.eq(L.sanitize(JSON.parse(JSON.stringify(once.config))).profiles.buchhwin.builtin, "buchhwin",
             "the mark survives a write and a read")
        T.eq(L.sanitize({ profiles: { a: { modes: {}, builtin: "Not a slug" } } }).profiles.a.builtin, undefined,
             "a mark that is not a profile id is dropped")
        T.eq(L.sanitize({ profiles: { a: { modes: {} } } }).profiles.a.builtin, undefined,
             "and a profile of the user's carries none")

        // A profile the user called "buchhwin" before there was a built-in one.
        const mine = L.sanitize({ activeProfile: "buchhwin", profiles: {
            buchhwin: { label: "Mine", modes: { work: root.mode([{ id: "clock-a", type: "clock", screen: "DP-1" }]) } } } })
        const beside = L.addBuiltinProfiles(mine, [small])
        T.eq(beside.added, ["buchhwin-2"], "a user's profile with the same name keeps it; the built-in one takes the next")
        T.eq(L.profileLabel(beside.config, "buchhwin"), "Mine", "the user's profile is not overwritten")
        T.eq(L.modeConfig(beside.config, "buchhwin", "work").widgets.length, 1, "nor are its modes")
        T.eq(L.builtinOf(beside.config, "buchhwin"), "", "and it does not become the built-in one")
        T.eq(L.builtinProfileName(beside.config, "buchhwin"), "buchhwin-2", "the built-in one is found by its mark")
        T.eq(L.addBuiltinProfiles(beside.config, [small]).added, [], "and is not added a third time")

        // ---- the Default profile is adopted, not added beside ---------------------
        const shippedDefault = { id: "default", label: "Default",
                                 modes: { work: root.mode([{ id: "clock-s", type: "clock", screen: "DP-1" }]) } }
        const existing = L.sanitize({ profiles: { default: { label: "Mine", modes: { gaming: root.mode([]) },
            state: { settings: { appearance: { accent: "#111111" } } } } } })
        const adopted = L.addBuiltinProfiles(existing, [shippedDefault, small])
        T.eq(adopted.added, ["default", "buchhwin"], "an unmarked Default is adopted, buchhwin added beside it")
        T.eq(L.profileNames(adopted.config), ["default", "buchhwin"], "no default-2")
        T.eq(L.builtinOf(adopted.config, "default"), "default", "Default is marked as the shipped one")
        T.eq(L.profileLabel(adopted.config, "default"), "Mine", "and keeps its label")
        T.eq(Object.keys(L.modesOf(adopted.config, "default")), ["gaming"], "its modes")
        T.eq(L.stateOf(adopted.config, "default").settings.appearance.accent, "#111111", "and its state")
        T.eq(L.addBuiltinProfiles(adopted.config, [shippedDefault]).added, [], "adopted once")
        T.eq(L.profileNames(L.removeProfile(adopted.config, "default")), ["default", "buchhwin"],
             "and from then on not removable")
        const firstStart = L.addBuiltinProfiles(L.sanitize({}), [shippedDefault], true)
        T.eq(firstStart.added, ["default"], "on a first start it is adopted too")
        T.eq(L.modeConfig(firstStart.config, "default", "work").widgets.map(widget => widget.id), ["clock-s"],
             "and takes the shipped modes: there is nothing of the user's to keep")
        T.eq(L.profileLabel(firstStart.config, "default"), "Default", "under the label it had")
        const noDefault = L.addBuiltinProfiles(L.sanitize({ activeProfile: "work", profiles: { work: { label: "Work", modes: {} } } }),
                                               [shippedDefault])
        T.eq(L.profileNames(noDefault.config), ["work", "default"], "without a Default the shipped one is added")
        T.eq(L.modeConfig(noDefault.config, "default", "work").widgets.length, 1, "with its modes")
        T.eq(L.builtinOf(once.config, "default"), "", "without a shipped Default, Default stays the user's profile")

        // ---- once per start: what the profile in use gets -------------------------
        const later = L.sanitize(Object.assign(JSON.parse(JSON.stringify(adopted.config)), { adopted: ["profileState"] }))
        T.eq(L.settleAction(adopted.config, "default", true, false), "", "a profile with a state keeps it")
        T.eq(L.settleAction(adopted.config, "buchhwin", true, false), "current",
             "the first start of this version over an existing file: a built-in profile in use keeps what is set")
        T.eq(L.settleAction(adopted.config, "buchhwin", true, true), "shipped", "a first start applies its shipped setup")
        T.eq(L.settleAction(later, "buchhwin", true, false), "shipped", "and so does any later start without a state")
        T.eq(L.settleAction(later, "buchhwin", false, false), "current", "unless its file is missing")
        T.eq(L.settleAction(L.withState(later, "default", null), "default", false, true), "current",
             "a profile of the user's takes what is set")

        // ---- not removable; renamed by label only ------------------------------
        T.eq(L.profileNames(L.removeProfile(once.config, "buchhwin")), ["default", "buchhwin"],
             "a built-in profile is not removable")
        T.eq(L.profileNames(L.removeProfile(once.config, "default")), ["buchhwin"],
             "the profile beside it still is")
        const renamed = L.renameProfile(once.config, "buchhwin", "My desk")
        T.eq([L.profileLabel(renamed, "buchhwin"), L.builtinOf(renamed, "buchhwin")], ["My desk", "buchhwin"],
             "renaming changes its label, not its id or its mark")
        const copy = L.duplicateProfile(once.config, "buchhwin", "Copy")
        T.eq(L.builtinOf(copy.config, copy.name), "", "a duplicate is the user's own profile")

        // ---- reset to the shipped state -----------------------------------------
        const edited = L.sanitize(JSON.parse(JSON.stringify(once.config)))
        edited.profiles.buchhwin.modes.work = root.mode([{ id: "x", type: "clock", screen: "DP-1" }])
        edited.profiles.buchhwin.modes.gaming = root.mode([])
        const back = L.resetProfile(edited, "buchhwin", "", small.modes)
        T.eq(Object.keys(L.modesOf(back, "buchhwin")), ["work"], "reset brings back the shipped modes, all of them")
        T.eq(L.modeConfig(back, "buchhwin", "work").widgets, [], "as they shipped")
        const one = L.resetProfile(edited, "buchhwin", "work", small.modes)
        T.eq(Object.keys(L.modesOf(one, "buchhwin")).sort(), ["gaming", "work"], "one mode on its own")
        T.eq(L.modeConfig(one, "buchhwin", "work").widgets, [], "that one from the shipped file")
        T.eq(Object.keys(L.modesOf(L.resetProfile(edited, "buchhwin", "gaming", small.modes), "buchhwin")), ["work"],
             "and a mode the file does not ship goes back to the factory template")
        T.eq(L.builtinOf(back, "buchhwin"), "buchhwin", "it stays the built-in one")
        T.eq(Object.keys(L.modesOf(L.resetProfile(edited, "default", "", small.modes), "default")), [],
             "a profile of the user's ignores shipped modes and goes to the factory state")

        // ---- the settings it writes ---------------------------------------------
        const leaves = P.settingLeaves({
            configVersion: 1,
            appearance: { accent: "#50e2cb", blurStrength: 0.9, gapsIn: 3, theme: "dark" },
            notch: { openDelay: 120 },
            desktop: { dashboardWidth: 900 },
            wallpaper: { path: "~/Pictures/w.webp", folder: "" },
            power: { ac: { lidAction: "nothing" } },
            odd: { list: [1, 2], nothing: null }
        }, "/home/u")
        T.eq(leaves, { "appearance.accent": "#50e2cb", "appearance.theme": "dark", "notch.openDelay": 120,
                       "desktop.dashboardWidth": 900, "wallpaper.path": "/home/u/Pictures/w.webp",
                       "wallpaper.folder": "" },
             "leaf paths, without the mode-scoped ones, the markers, the machine's power, lists or nulls; home paths expanded")
        T.ok(Object.keys(P.settingLeaves(shipped.settings, "/home/u")).every(path => !P.isModeScoped(path)),
             "the shipped settings carry nothing a mode owns")
        T.eq([P.expandHome("~", "/h"), P.expandHome("~user/x", "/h"), P.expandHome("/abs", "/h")], ["/h", "~user/x", "/abs"],
             "only ~ and ~/ are this home")

        // ---- the global half ----------------------------------------------------
        const withPreset = L.sanitize(Object.assign(JSON.parse(JSON.stringify(once.config)), {
            notchPresets: [{ id: "custom-mine", label: "Mine", layout: L.defaultNotch(), options: {} },
                           { id: "custom-shared", label: "Old", layout: L.defaultNotch(), options: {} }] }))
        const applied = L.applyBuiltinLayout(withPreset, {
            notch: shipped.notch, lock: shipped.lock,
            notchPresets: [{ id: "custom-shared", label: "New", layout: shipped.notch, options: {} }] })
        T.eq(applied.notch, shipped.notch, "the notch is replaced")
        T.eq(applied.lock, shipped.lock, "and the lock screen")
        T.eq(applied.notchPresets.map(preset => preset.id + ":" + preset.label), ["custom-shared:New", "custom-mine:Mine"],
             "a shipped preset replaces one of the same id, the user's own stay")
        T.eq(L.profileNames(applied), L.profileNames(withPreset), "and the profiles are untouched")

        ready.start()
    }

    // ---- LayoutService in the sandbox -------------------------------------------
    // Waits for the layout, the shipped profiles and the state of the profile
    // in use to be settled - and for a shipped Default to have been applied,
    // when there is one (a first start in the sandbox applies it).
    Timer {
        id: ready
        interval: 20
        repeat: true
        onTriggered: {
            root.waits += 1
            const there = LayoutService.loaded && LayoutService.builtinProfiles.buchhwin !== undefined
                && LayoutService.profileNames.indexOf("buchhwin") >= 0
                && LayoutService.stateSettled && !LayoutService.builtinApplying.length
            if (!there && root.waits < 200) return
            stop()
            T.ok(there, "the built-in profile is in the layout once it has loaded (" + Paths.configDir + ")")
            T.eq(LayoutService.profileNames.filter(name => LayoutService.builtinOf(name) === "buchhwin"), ["buchhwin"],
                 "exactly once")
            T.ok(LayoutService.pendingText.indexOf("\"builtin\": \"buchhwin\"") >= 0, "and it is written to the file")
            T.eq(LayoutService.removeProfile("buchhwin"), false, "the service refuses to remove it")
            // The sandbox's first start: Default in use, with its shipped modes.
            T.eq([LayoutService.activeProfile, LayoutService.activeMode, SettingsService.value("appearance.panelOpacity")],
                 ["default", "minimal", 0.88], "a first start shows Default's panels at 0.88")
            T.eq(L.modeConfig(LayoutService.config, "default", "work").appearance.panelOpacity, 0.88,
                 "and its other modes keep them there")
            T.eq(LayoutService.modeSettings("work")["appearance.panelOpacity"], undefined, "so entering one changes nothing about them")
            // Every shipped setting this shell knows is one SettingsService
            // takes: the right type and an allowed value. Otherwise applying
            // the profile logs a "rejected setting" per key and skips it.
            const leaves = P.settingLeaves(LayoutService.builtinProfiles.buchhwin.settings, Paths.home)
            const refused = Object.keys(leaves).filter(path => {
                const fallback = SettingsService.defaultOf(path)
                if (fallback === undefined || typeof fallback === "object") return false
                const choices = SettingsService.allowed[path]
                return typeof leaves[path] !== typeof fallback || (choices && choices.indexOf(leaves[path]) < 0)
            })
            T.eq(refused, [], "every shipped setting this shell knows is one it accepts")
            T.eq(LayoutService.applyBuiltin(LayoutService.addProfile("Mine")), false,
                 "a profile that is not built in has nothing to restore")
            T.eq(L.stateOf(LayoutService.config, "buchhwin"), null, "never entered, it keeps no state yet")
            T.eq(LayoutService.setActiveProfile("buchhwin"), true, "switching to it is a switch")
            T.eq(LayoutService.builtinApplying, "buchhwin", "the first time, that applies the whole setup")
            T.eq(LayoutService.applyBuiltin("buchhwin"), false, "and a second request while it runs is refused")
            root.tries = 0
            applied.start()
        }
    }

    Timer {
        id: applied
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            if (LayoutService.builtinApplying.length && root.tries < 200) return
            stop()
            T.eq(LayoutService.builtinError, "", "applying it went through")
            T.ok(root.appliedSignal, "and said so")
            const shipped = LayoutService.builtinProfiles.buchhwin
            T.eq(SettingsService.value("appearance.accent"), shipped.settings.appearance.accent, "the settings are the shipped ones")
            T.eq(SettingsService.value("notch.openDelay"), shipped.settings.notch.openDelay, "the notch's options too")
            T.eq(LayoutService.notchLayout, shipped.notch, "the notch layout")
            T.eq(LayoutService.lockLayout, shipped.lock, "and the lock screen")
            const state = L.stateOf(LayoutService.config, "buchhwin")
            T.ok(state !== null, "what was applied is its state from now on")
            T.eq(state ? state.settings.appearance.accent : "", shipped.settings.appearance.accent, "the shipped accent in it")
            T.eq(state ? state.notch : null, shipped.notch, "and the shipped notch")
            backupFile.reload()
            T.ok(backupFile.text().indexOf("\"profiles\"") >= 0, "layout.json was backed up first, in the sandbox's state directory")
            fastfetchFile.reload()
            const fastfetch = fastfetchFile.text()
            T.ok(fastfetch.indexOf("\"modules\"") >= 0, "fastfetch.jsonc is in the sandbox's config directory")
            // The export points the logo at ~/.config/buchhwin-shell; a config
            // directory elsewhere gets its own path (home-relative when it is
            // under the home directory).
            const logo = Paths.configDir + "/saturn.txt"
            const expected = logo.indexOf(Paths.home + "/") === 0 ? "~" + logo.slice(Paths.home.length) : logo
            T.ok(fastfetch.indexOf("\"" + expected + "\"") >= 0, "pointing at the logo beside it (" + expected + ")")
            T.eq(LayoutService.undoStack.length, 0, "applying it takes no undo step, and undo starts again")
            // A later edit undone takes the edit back, not a state stored or
            // a marker set after its step.
            const notch = LayoutService.notchLayout
            const before = L.stateOf(LayoutService.config, "default")
            LayoutService.notchResetLayout()
            const marked = JSON.parse(JSON.stringify(L.withState(LayoutService.config, "default",
                { settings: { appearance: { panelColor: "#0a0a0a" } }, notch: null, lock: null })))
            marked.adopted.push("testMarker")
            LayoutService.config = L.sanitize(marked)
            LayoutService.undo()
            T.eq(LayoutService.notchLayout, notch, "undo takes the edit back")
            T.eq(L.stateOf(LayoutService.config, "default").settings.appearance.panelColor, "#0a0a0a",
                 "but not a state stored after its step")
            T.ok(L.hasAdopted(LayoutService.config, "testMarker"), "nor a marker set after it")
            T.eq(L.stateOf(LayoutService.config, "buchhwin").notch, shipped.notch, "the applied state stays")
            const clean = JSON.parse(JSON.stringify(L.withState(LayoutService.config, "default", before)))
            clean.adopted = clean.adopted.filter(name => name !== "testMarker")
            LayoutService.config = L.sanitize(clean)
            kept.start()
        }
    }

    // The user's changes to it stay: out and in again restores them, and
    // nothing is applied a second time.
    Timer {
        id: kept
        interval: 50
        onTriggered: {
            SettingsService.set("appearance.accent", "#123456")
            T.eq(LayoutService.setActiveProfile("default"), true, "back to the user's profile")
            T.eq(LayoutService.builtinApplying, "", "which applies nothing")
            T.ok(SettingsService.value("appearance.accent") !== "#123456", "and puts its own accent back")
            T.eq(L.stateOf(LayoutService.config, "buchhwin").settings.appearance.accent, "#123456",
                 "the built-in profile left keeps the change")
            root.appliedSignal = false
            T.eq(LayoutService.setActiveProfile("buchhwin"), true, "into it again")
            T.eq(LayoutService.builtinApplying, "", "with a state, entering it applies nothing")
            T.eq(SettingsService.value("appearance.accent"), "#123456", "and the change is back")
            T.eq(LayoutService.notchLayout, LayoutService.builtinProfiles.buchhwin.notch, "with its own notch")
            // Restore, in use: the shipped setup again, at once.
            T.eq(LayoutService.applyBuiltin("buchhwin"), true, "Restore in use")
            T.eq(LayoutService.builtinApplying, "buchhwin", "applies the shipped setup")
            T.eq(LayoutService.resetProfile("buchhwin", ""), false,
                 "and Reset of the profile in use is refused while that runs, like a second Restore")
            root.tries = 0
            restored.start()
        }
    }

    Timer {
        id: restored
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            if (LayoutService.builtinApplying.length && root.tries < 200) return
            stop()
            const accent = LayoutService.builtinProfiles.buchhwin.settings.appearance.accent
            T.ok(root.appliedSignal, "Restore went through")
            T.eq(SettingsService.value("appearance.accent"), accent, "the shipped accent is back")
            T.eq(L.stateOf(LayoutService.config, "buchhwin").settings.appearance.accent, accent, "and in its state")
            // Restore of a built-in profile not in use forgets its state:
            // nothing that is set now changes, and the next entry is a first.
            T.eq(LayoutService.setActiveProfile("default"), true, "out again")
            const mine = SettingsService.value("appearance.accent")
            T.eq(LayoutService.applyBuiltin("buchhwin"), true, "Restore of the profile not in use")
            T.eq(LayoutService.builtinApplying, "", "runs nothing")
            T.eq(L.stateOf(LayoutService.config, "buchhwin"), null, "and forgets its state")
            T.eq(SettingsService.value("appearance.accent"), mine, "the profile in use keeps its settings")
            leftEarly.start()
        }
    }

    // The profile key pressed twice: into the built-in profile and straight
    // out again before the script has answered. The profile left in keeps
    // its settings, and the built-in one stores none - its setup never
    // arrived, so the next entry applies it.
    Timer {
        id: leftEarly
        interval: 50
        onTriggered: {
            SettingsService.set("appearance.accent", "#010203")
            root.tries = 0
            root.appliedSignal = false
            LayoutService.setActiveProfile("buchhwin")
            T.eq(LayoutService.builtinApplying, "buchhwin", "without a state, into it applies the setup again")
            LayoutService.setActiveProfile("default")
            settled.start()
        }
    }

    Timer {
        id: settled
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            if (LayoutService.builtinApplying.length && root.tries < 200) return
            stop()
            T.eq(LayoutService.activeProfile, "default", "and out before it answered")
            T.eq(SettingsService.value("appearance.accent"), "#010203", "the profile left in keeps its settings")
            T.ok(!root.appliedSignal, "and nothing was applied")
            T.eq(L.stateOf(LayoutService.config, "buchhwin"), null, "the built-in profile left early stores no state")
            // Reset of all five of a built-in profile not in use: the shipped
            // modes, and its state forgotten.
            LayoutService.config = L.withState(LayoutService.config, "buchhwin",
                                               L.stateOf(LayoutService.config, "default"))
            const customised = L.stateOf(LayoutService.config, "buchhwin")
            T.eq(LayoutService.resetProfile("buchhwin", ""), true, "Reset of the built-in profile not in use")
            T.eq(L.stateOf(LayoutService.config, "buchhwin"), null, "forgets its state, so it comes back shipped")
            T.eq(LayoutService.builtinApplying, "", "and applies nothing while it is not in use")
            T.eq(Object.keys(L.modesOf(LayoutService.config, "buchhwin")).sort(),
                 Object.keys(LayoutService.builtinProfiles.buchhwin.modes).sort(), "its modes are the shipped ones")
            // The steps hold no states, so the Reset hands the one it forgot
            // to its own: Undo brings it back with the modes, and the next
            // entry keeps the user's setup rather than applying the shipped one.
            const resetStep = JSON.parse(LayoutService.undoStack[LayoutService.undoStack.length - 1])
            T.eq(Object.keys(resetStep.states || {}), ["buchhwin"], "its step carries that state and no other")
            LayoutService.undo()
            T.eq(L.stateOf(LayoutService.config, "buchhwin"), customised, "undo of the Reset brings the state back")
            T.eq(LayoutService.resetProfile("buchhwin", ""), true, "and Reset again")
            T.eq(L.stateOf(LayoutService.config, "buchhwin"), null, "forgets it again")
            // The Default profile is the shipped one once its file is there,
            // and the user's own until then.
            if (LayoutService.builtinProfiles["default"] !== undefined)
                T.eq(LayoutService.builtinOf("default"), "default", "with its file shipped, Default is adopted")
            else
                T.eq(LayoutService.builtinOf("default"), "", "without its file, Default stays the user's profile")
            loadTime.start()
        }
    }

    // Once per start, the profile in use without a state: arranged here as a
    // start would find it, then settled again. A later start (the marker in
    // the file) applies the built-in profile's shipped setup.
    Timer {
        id: loadTime
        interval: 50
        onTriggered: {
            const arranged = JSON.parse(JSON.stringify(LayoutService.config))
            arranged.activeProfile = "buchhwin"
            delete arranged.profiles.buchhwin.state
            LayoutService.config = L.sanitize(arranged)
            SettingsService.set("appearance.accent", "#0a0b0c")
            root.appliedSignal = false
            LayoutService.stateSettled = false
            LayoutService.settleActiveState()
            T.eq(LayoutService.builtinApplying, "buchhwin",
                 "a start in the built-in profile without a state applies its shipped setup")
            root.tries = 0
            loadApplied.start()
        }
    }

    Timer {
        id: loadApplied
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            if (LayoutService.builtinApplying.length && root.tries < 200) return
            stop()
            const accent = LayoutService.builtinProfiles.buchhwin.settings.appearance.accent
            T.ok(root.appliedSignal, "it went through")
            T.eq(SettingsService.value("appearance.accent"), accent, "the shipped accent")
            T.eq(L.stateOf(LayoutService.config, "buchhwin").settings.appearance.accent, accent, "stored as its state")
            // The first start of this version over an existing layout file
            // (no marker; the sandbox's own start was a first one): the
            // built-in profile in use keeps what is set.
            const arranged = JSON.parse(JSON.stringify(LayoutService.config))
            delete arranged.profiles.buchhwin.state
            arranged.adopted = arranged.adopted.filter(name => name !== "profileState")
            LayoutService.config = L.sanitize(arranged)
            SettingsService.set("appearance.accent", "#0d0e0f")
            LayoutService.freshLayout = false
            LayoutService.stateSettled = false
            LayoutService.settleActiveState()
            T.eq(LayoutService.builtinApplying, "", "the first start over an existing file applies nothing")
            T.eq(L.stateOf(LayoutService.config, "buchhwin").settings.appearance.accent, "#0d0e0f",
                 "the built-in profile in use keeps what is set as its state")
            T.ok(L.hasAdopted(LayoutService.config, "profileState"), "and the marker is in the file from then on")
            failed.start()
        }
    }

    // A run that failed (profile-apply.py's answer, handed in as the process
    // would): the built-in profile in use stops waiting for its shipped
    // setup and keeps what is set, like one of the user's, until Restore; the
    // error is that profile's own. Then one that went through, on a machine
    // without the shipped cursor theme and on one with it.
    Timer {
        id: failed
        interval: 50
        onTriggered: {
            const arranged = JSON.parse(JSON.stringify(LayoutService.config))
            delete arranged.profiles.buchhwin.state
            LayoutService.config = L.sanitize(arranged)
            SettingsService.setAll({ "appearance.accent": "#0c0d0e", "appearance.cursorTheme": "breeze_cursors" })
            T.ok(LayoutService.waitingForShipped("buchhwin"), "a built-in profile in use without a state waits for its setup")
            LayoutService.finishBuiltin("buchhwin", "buchhwin", 1, '{"ok": false, "error": "backup failed, nothing changed"}')
            T.eq(LayoutService.builtinErrorOf("buchhwin"), "backup failed, nothing changed", "a failed run says why, for that profile")
            T.eq(LayoutService.builtinErrorOf("default"), "", "and not for every built-in one")
            T.ok(!LayoutService.waitingForShipped("buchhwin"), "it waits no longer")
            T.eq(L.stateOf(LayoutService.config, "buchhwin").settings.appearance.accent, "#0c0d0e",
                 "and keeps what is set as its state")
            T.eq(SettingsService.value("appearance.accent"), "#0c0d0e", "nothing that is set changes")
            LayoutService.notchResetLayout()
            const cursor = LayoutService.builtinProfiles.buchhwin.settings.appearance.cursorTheme
            LayoutService.finishBuiltin("buchhwin", "buchhwin", 0,
                '{"ok": true, "apps": {}, "cursor": {"theme": "' + cursor + '", "installed": false}}')
            T.eq(LayoutService.builtinErrorOf("buchhwin"), "", "one that went through clears its error")
            T.eq(SettingsService.value("appearance.accent"), LayoutService.builtinProfiles.buchhwin.settings.appearance.accent,
                 "and applies the shipped settings")
            T.eq(SettingsService.value("appearance.cursorTheme"), "breeze_cursors",
                 "but not a cursor theme this machine does not have")
            T.eq(LayoutService.undoStack.length, 0, "and the undo steps from before it are gone")
            LayoutService.finishBuiltin("buchhwin", "buchhwin", 0,
                '{"ok": true, "apps": {}, "cursor": {"theme": "' + cursor + '", "installed": true}}')
            T.eq(SettingsService.value("appearance.cursorTheme"), cursor, "one it has is applied")
            T.finish("BuiltinProfileTest")
        }
    }
}
