import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// How LayoutService changes the layout, pure: one mode at a time. An edit
// copies the mode it changes and the global surfaces, shares everything else
// with the config it started from, and checks only what it copied - and the
// result must be the very one a whole copy and a whole check give. Every part
// that did not change is the object it was, so a QML binding on the notch, the
// dock or another mode's bar is not told about it. Then the settings a profile
// switch writes: the migrations a stored state goes through, home paths and
// the defaults, and a value this version refuses.
ShellRoot {
    id: root
    FileView { id: buchhwinFile; path: Qt.resolvedUrl("../../config/builtin-profiles/buchhwin/profile.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: defaultFile; path: Qt.resolvedUrl("../../config/builtin-profiles/default/profile.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: workFile; path: Qt.resolvedUrl("../../config/profiles/work.json").toString().replace("file://", ""); blockLoading: true }

    function json(value) { return JSON.stringify(value) }

    // Frozen all the way down: a check that changed its input in place would
    // fail silently on it and come out different from a check of a copy.
    function freeze(value) {
        if (value && typeof value === "object") {
            Object.freeze(value)
            for (const key of Object.keys(value)) root.freeze(value[key])
        }
        return value
    }

    // What every edit did before: a whole copy, the callback, a whole check.
    function wholeEdit(config, profile, mode, callback) {
        const next = JSON.parse(JSON.stringify(config))
        if (!next.profiles[profile]) next.profiles[profile] = { label: L.DEFAULT_PROFILE_LABEL, modes: {} }
        const modes = next.profiles[profile].modes
        if (!modes[mode]) modes[mode] = { widgets: [], groups: [], screens: [] }
        callback(modes[mode], next)
        return L.sanitize(next)
    }

    Component.onCompleted: {
        const buchhwin = JSON.parse(buchhwinFile.text())
        const shippedDefault = JSON.parse(defaultFile.text())
        const config = root.freeze(L.sanitize({
            activeProfile: "buchhwin", activeMode: "minimal",
            notch: buchhwin.notch, lock: buchhwin.lock,
            profiles: {
                "default": { label: "Default", builtin: "default", modes: shippedDefault.modes,
                             state: { settings: shippedDefault.settings, notch: shippedDefault.notch, lock: shippedDefault.lock } },
                buchhwin: { label: "buchhwin", builtin: "buchhwin", modes: buchhwin.modes,
                            state: { settings: buchhwin.settings, notch: buchhwin.notch, lock: buchhwin.lock } }
            }
        }))
        T.ok(Object.keys(config.profiles.buchhwin.modes).length === 5, "the fixture is a real layout: buchhwin's five modes")

        // ---- a check with the config it came from ---------------------------
        T.eq(json(L.sanitize(config, config)), json(L.sanitize(config)), "checked again with itself it is what a whole check gives")
        const same = L.sanitize(config, config)
        T.ok(same.notch === config.notch && same.dock === config.dock && same.lock === config.lock
             && same.profiles === config.profiles, "and every part is the object it was")
        const thawed = JSON.parse(JSON.stringify(config))
        T.eq(json(L.sanitize(thawed, config)), json(config), "a copy checked against the config is equal")
        const kept = L.sanitize(thawed, config)
        T.ok(kept.notch === config.notch && kept.profiles.buchhwin.modes.work === config.profiles.buchhwin.modes.work
             && kept.profiles["default"].state === config.profiles["default"].state,
             "and the parts that came out the same are the config's objects, not the copy's")
        T.eq(json(L.sanitize(root.freeze(JSON.parse(JSON.stringify(config))))), json(config),
             "a check does not change its input in place")

        // ---- one edit -------------------------------------------------------
        const edits = [
            ["a bar option", (mode, next) => { mode.bar = Object.assign({}, mode.bar, { edge: "bottom" }) }],
            ["a pill moved", (mode, next) => { mode.bar = L.movePill(mode.bar, mode.bar.left[0].id, 1) }],
            ["the desktop mode", (mode, next) => { mode.desktopMode = "notch" }],
            ["a mode-scoped setting", (mode, next) => { mode.appearance = Object.assign({}, mode.appearance, { gapsOut: 13 }) }],
            ["the notch", (mode, next) => { next.notch = L.defaultNotch() }],
            ["the dock", (mode, next) => { next.dock = L.dockPinAt(next.dock, "org.example.App", 0) }],
            ["the lock screen", (mode, next) => { next.lock = L.defaultLock() }],
            ["a marker", (mode, next) => { next.adopted = L.withAdopted(next, "testMarker") }],
            ["nothing at all", (mode, next) => {}]
        ]
        for (const entry of edits) {
            const made = L.edit(config, "buchhwin", "minimal", entry[1])
            T.eq(json(made), json(root.wholeEdit(config, "buchhwin", "minimal", entry[1])),
                 entry[0] + ": the result is the one a whole copy and a whole check give")
            T.ok(made.profiles["default"] === config.profiles["default"], entry[0] + ": the other profile is the object it was")
            T.ok(made.profiles.buchhwin.state === config.profiles.buchhwin.state, entry[0] + ": and so is the profile's state")
            T.ok(["work", "gaming", "laptop", "docked"].every(name => made.profiles.buchhwin.modes[name] === config.profiles.buchhwin.modes[name]),
                 entry[0] + ": and every other mode")
        }
        const barEdit = L.edit(config, "buchhwin", "minimal", mode => { mode.bar = Object.assign({}, mode.bar, { edge: "bottom" }) })
        const before = config.profiles.buchhwin.modes.minimal
        const after = barEdit.profiles.buchhwin.modes.minimal
        T.ok(barEdit.notch === config.notch && barEdit.dock === config.dock && barEdit.lock === config.lock
             && barEdit.notchPresets === config.notchPresets && barEdit.adopted === config.adopted,
             "a bar edit leaves the notch, the dock, the lock screen, the presets and the markers the objects they were")
        T.ok(after.bar !== before.bar && after.bar.edge === "bottom", "the bar is new")
        T.ok(after.quick === before.quick && after.dashboard === before.dashboard && after.launcher === before.launcher
             && after.appearance === before.appearance && after.widgets === before.widgets,
             "and the mode's other parts are the objects they were")
        const notchEdit = L.edit(config, "buchhwin", "minimal", (mode, next) => { next.notch = L.defaultNotch() })
        T.ok(notchEdit.notch !== config.notch && notchEdit.profiles === config.profiles && notchEdit.dock === config.dock,
             "a notch edit is a new notch and nothing else")
        const nothing = L.edit(config, "buchhwin", "minimal", () => {})
        T.ok(nothing.profiles === config.profiles && nothing.notch === config.notch, "an edit that changes nothing changes no part")
        // A mode or a profile that is not in the file yet.
        const plain = L.sanitize({ activeProfile: "default", profiles: { "default": { label: "Default", modes: {} } } })
        const intoNew = mode => { mode.desktopMode = "pills" }
        T.eq(json(L.edit(plain, "default", "work", intoNew)), json(root.wholeEdit(plain, "default", "work", intoNew)),
             "a mode not in the file is made by its first edit")
        T.eq(json(L.edit(plain, "other", "minimal", intoNew)), json(root.wholeEdit(plain, "other", "minimal", intoNew)),
             "and so is a profile")

        // ---- one mode replaced, a switch, a state put back ----------------
        const work = JSON.parse(JSON.stringify(config.profiles.buchhwin.modes.work))
        work.desktopMode = "widgets"
        const replaced = L.withMode(config, "buchhwin", "work", work)
        const whole = JSON.parse(JSON.stringify(config))
        whole.profiles.buchhwin.modes.work = work
        T.eq(json(replaced), json(L.sanitize(whole)), "a mode replaced: what a whole check gives")
        T.ok(replaced.profiles.buchhwin.modes.minimal === config.profiles.buchhwin.modes.minimal
             && replaced.notch === config.notch, "with the rest the objects they were")
        const switched = L.sanitize(Object.assign({}, config, { activeMode: "work" }), config)
        T.eq(switched.activeMode, "work", "a switch")
        T.ok(switched.profiles === config.profiles && switched.notch === config.notch && switched.dock === config.dock
             && switched.lock === config.lock, "changes no notch, dock, lock screen or mode")
        const state = config.profiles["default"].state
        const entered = Object.assign({}, config, { activeProfile: "default" })
        T.eq(json(L.restoreStateLayout(entered, state, config)), json(L.restoreStateLayout(JSON.parse(JSON.stringify(entered)), state)),
             "a state put back: what a whole copy and a whole check give")
        T.ok(L.restoreStateLayout(entered, state, config).profiles === config.profiles, "with every profile the object it was")

        // ---- a mode entered the first time ----------------------------------
        const template = JSON.parse(workFile.text())
        const fresh = L.freshMode(template)
        T.eq([fresh.desktopMode, json(fresh.bar), fresh.widgets, fresh.screens], ["pills", json(template.bar), [], []],
             "a mode made before it is entered has its template's desktop mode and bar")
        T.eq(L.sanitizeMode(L.freshMode({ widgets: [] })).desktopMode, "widgets", "a template without one: widgets")
        T.ok(L.freshMode(template).bar !== template.bar, "a copy of the template's bar")

        // ---- the settings a switch writes -----------------------------------
        const migrated = L.migrateSettings({ notch: { expandOnHover: false }, wallpaper: { favouritesOnly: true },
                                             appearance: { animationMode: "fast" } })
        T.eq([migrated.notch.hoverMode, migrated.notch.expandOnHover, migrated.wallpaper.slideshowSource,
              migrated.appearance.animationMode],
             ["click", undefined, "favourites", "full"], "a state from before a migration is migrated like settings.json")
        const defaults = { recording: { folder: "~/Videos/Recordings" }, wallpaper: { path: "", folder: "" },
                           notch: { hoverMode: "hover", openDelay: 120 }, power: { lowBatteryLevel: 10 } }
        const leaves = L.profileLeaves(L.migrateSettings({ recording: { folder: "/home/u/Videos/Recordings" },
                                                           wallpaper: { path: "~/Pictures/a.png" },
                                                           notch: { expandOnHover: false } }), defaults, "/home/u")
        T.eq(leaves["recording.folder"], "~/Videos/Recordings",
             "a stored home path that is the default once expanded is the default")
        T.eq(leaves["wallpaper.path"], "/home/u/Pictures/a.png", "any other home path is expanded as before")
        T.eq([leaves["wallpaper.folder"], leaves["notch.openDelay"]], ["", 120], "what the state does not name is the default")
        T.eq(leaves["notch.hoverMode"], "click", "and the migrated value is the state's")
        T.eq(Object.keys(leaves).filter(path => path.indexOf("power.") === 0), [], "a migration's machine settings stay out")
        T.eq(L.profileLeaves({}, defaults, "/home/u")["recording.folder"], "~/Videos/Recordings",
             "the default folder is not expanded on its way in")

        const known = { "notch.hoverMode": "hover", "notch.openDelay": 120, "recording.folder": "~/Videos/Recordings" }
        const allowed = { "notch.hoverMode": ["hover", "click", "off"] }
        const now = { "notch.hoverMode": "click", "notch.openDelay": 300, "recording.folder": "~/Videos/Recordings" }
        T.eq(L.knownSettings({ "notch.hoverMode": "bogus", "notch.openDelay": "slow", "recording.folder": "~/Videos/Recordings",
                               "unknown.key": 1 },
                             path => known[path], allowed, path => now[path]),
             { "notch.hoverMode": "hover", "notch.openDelay": 120 },
             "a refused value is the default, not the setting of the profile left; an equal one and an unknown key are left out")
        T.eq(L.knownSettings({ "notch.hoverMode": "off" }, path => known[path], allowed, path => now[path]),
             { "notch.hoverMode": "off" }, "an accepted one is written as it is")

        T.finish("LayoutEditTest")
    }
}
