import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/profile/ProfileLogic.js" as P

// The profiles the repository ships (config/builtin-profiles/<id>). First the
// pure half: always added and only once, never over a profile of the user's
// that carries the same name, not removable, reset to the shipped modes, and
// the settings it writes being everything but what the modes own. Then
// LayoutService against the runner's sandbox: the real "buchhwin" profile is
// added once the layout has loaded, and activating it backs up, installs
// fastfetch's files and applies the settings, the notch and the lock screen -
// all of it inside the sandbox's XDG directories.
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
            notch: { headerAdopted: true, openDelay: 120 },
            desktop: { quickSizesAdopted: false, dashboardWidth: 900 },
            wallpaper: { path: "~/Pictures/w.webp", folder: "" },
            power: { ac: { lidAction: "nothing" } },
            odd: { list: [1, 2], nothing: null }
        }, "/home/u")
        T.eq(leaves, { "appearance.accent": "#50e2cb", "appearance.theme": "dark", "notch.openDelay": 120,
                       "desktop.dashboardWidth": 900, "wallpaper.path": "/home/u/Pictures/w.webp",
                       "wallpaper.folder": "", "power.ac.lidAction": "nothing" },
             "leaf paths, without the mode-scoped ones, the markers, lists or nulls; home paths expanded")
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
    Timer {
        id: ready
        interval: 20
        repeat: true
        onTriggered: {
            root.waits += 1
            const there = LayoutService.loaded && LayoutService.builtinProfiles.buchhwin !== undefined
                && LayoutService.profileNames.indexOf("buchhwin") >= 0
            if (!there && root.waits < 200) return
            stop()
            T.ok(there, "the built-in profile is in the layout once it has loaded (" + Paths.configDir + ")")
            T.eq(LayoutService.profileNames.filter(name => LayoutService.builtinOf(name) === "buchhwin"), ["buchhwin"],
                 "exactly once")
            T.ok(LayoutService.pendingText.indexOf("\"builtin\": \"buchhwin\"") >= 0, "and it is written to the file")
            T.eq(LayoutService.removeProfile("buchhwin"), false, "the service refuses to remove it")
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
            T.eq(LayoutService.applyBuiltin("default"), false, "a profile that is not built in has nothing to restore")
            T.eq(LayoutService.setActiveProfile("buchhwin"), true, "switching to it is a switch")
            T.eq(LayoutService.builtinApplying, "buchhwin", "that applies the whole setup")
            T.eq(LayoutService.applyBuiltin("buchhwin"), false, "and a second request while it runs is refused")
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
            T.eq(LayoutService.undoStack.length > 0, true, "the notch and the lock screen are an undo step")
            leftEarly.start()
        }
    }

    // The profile key pressed twice: into the built-in profile and straight
    // out again before the script has answered. The profile left in keeps
    // its settings.
    Timer {
        id: leftEarly
        interval: 50
        onTriggered: {
            T.eq(LayoutService.setActiveProfile("default"), true, "back to the user's profile")
            T.eq(LayoutService.builtinApplying, "", "which applies nothing")
            SettingsService.set("appearance.accent", "#010203")
            root.tries = 0
            root.appliedSignal = false
            LayoutService.setActiveProfile("buchhwin")
            T.eq(LayoutService.builtinApplying, "buchhwin", "into the built-in profile again")
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
            T.finish("BuiltinProfileTest")
        }
    }
}
