import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/profile/ProfileLogic.js" as P

// A profile keeps everything the user sets, not only its layouts: the panel
// colour, the accent, the notch's options and its two lists, the lock screen
// - every setting except the machine's and the person's (the weather place,
// the keyboard layout, the screens), and except what the five modes own.
// First the pure half: which settings are a profile's, and the state in the
// file. Then LayoutService against the runner's sandbox: leaving a profile
// stores its state, entering one with a state puts it back, one without keeps
// what is set and takes it, a setting the state does not name is not reset,
// and the first switch of the day leaves a backup in the sandbox's state
// directory.
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0
    property string studio: ""
    property var homeNotch: null
    property var homeLock: null

    FileView {
        id: backupLayout
        path: Paths.stateDir + "/backup-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + "/layout.json"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        // ---- which settings are a profile's -------------------------------------
        T.ok(P.isProfileSetting("appearance.panelColor"), "the panel colour is a profile's")
        T.ok(P.isProfileSetting("notch.bodyHeight") && P.isProfileSetting("notch.hoverMode"), "and the notch's options")
        T.ok(P.isProfileSetting("notch.displayOsd"), "a group name is matched whole (notch.displayOsd is not display.*)")
        T.ok(!P.isProfileSetting("appearance.blurStrength"), "a mode-scoped leaf is the mode's")
        T.eq(["weather.lat", "weather.lon", "weather.locationName", "weather.autoLocate", "input.kbLayout",
              "input.kbVariant", "display.x11Scale", "display.xwaylandSharp", "onboarding.completed",
              "calendar.hiddenCalendars", "calendar.newEventCalendar", "colorPicker.history",
              "wallpaper.recentFolders", "configVersion", "notch.headerAdopted", "desktop.quickSizesAdopted",
              "desktop.settingsMoveX", "desktop.settingsMoveY"].filter(P.isProfileSetting), [],
             "the machine's and the person's settings are global")
        T.ok(P.isProfileSetting("weather.unit") && P.isProfileSetting("input.repeatRate")
             && P.isProfileSetting("wallpaper.path"), "their neighbours are a profile's")
        T.eq(P.profileSettings({ appearance: { panelColor: "#202020", gapsIn: 3 }, weather: { lat: 12.5, unit: "celsius" },
                                 recording: { folder: "~/Videos" } }, "/home/u"),
             { appearance: { panelColor: "#202020" }, weather: { unit: "celsius" }, recording: { folder: "/home/u/Videos" } },
             "a profile's settings as a tree, home paths expanded")

        // ---- the state in the file ------------------------------------------------
        const raw = { settings: { appearance: { panelColor: "#202020", blurStrength: 0.3, list: [1] },
                                  weather: { lat: 12.5, unit: "fahrenheit" }, input: { kbLayout: "us" }, odd: null },
                      notch: { collapsed: [], expanded: [] }, lock: { lock: [] } }
        const config = L.sanitize({ profiles: { default: { label: "Default", modes: {}, state: raw } } })
        const state = L.stateOf(config, "default")
        T.eq(state.settings, { appearance: { panelColor: "#202020" }, weather: { unit: "fahrenheit" } },
             "the sanitizer keeps a profile's settings and drops the mode's, the machine's, lists and nulls")
        T.eq(state.notch, L.sanitizeNotch(raw.notch), "the notch through its own sanitizer")
        T.eq(state.lock, L.sanitizeLock(raw.lock), "and the lock screen")
        T.eq(L.sanitize(JSON.parse(JSON.stringify(config))), config, "a write and a read keep the state")
        T.eq(L.sanitize({ profiles: { a: { modes: {}, state: "x" } } }).profiles.a.state, undefined,
             "a state that is not an object is none")
        T.eq(L.sanitize({ profiles: { a: { modes: {} } } }).profiles.a.state, undefined, "and a profile without one writes none")
        const partial = L.sanitize({ profiles: { a: { modes: {}, state: { settings: {} } } } }).profiles.a.state
        T.eq([partial.notch, partial.lock], [null, null], "a part it lacks is null")
        const withNotch = L.sanitize({ notch: raw.notch, profiles: { a: { modes: {} } } })
        T.eq(L.restoreStateLayout(withNotch, partial).notch, withNotch.notch, "and restoring leaves that part as it is")
        T.eq(L.restoreStateLayout(withNotch, { notch: L.defaultNotch(), lock: null }).notch, L.defaultNotch(),
             "a part it names replaces the one in use")

        // ---- the profile operations -----------------------------------------------
        const copy = L.duplicateProfile(config, "default", "Copy")
        T.eq(L.stateOf(copy.config, copy.name), state, "a duplicate copies the source's state")
        const now = { settings: { appearance: { panelColor: "#303030" } }, notch: null, lock: null }
        const given = L.duplicateProfile(config, "default", "Now", now)
        T.eq(L.stateOf(given.config, given.name).settings.appearance.panelColor, "#303030",
             "or the one it is given: the profile in use, as it is set now")
        const added = L.addProfile(config, "New")
        T.eq(L.stateOf(added.config, added.name), null, "a new profile has none")
        T.eq(L.stateOf(L.resetProfile(config, "default"), "default"), state, "reset of a profile of the user's keeps its state")
        T.eq(L.stateOf(L.renameProfile(config, "default", "Home"), "default"), state, "and so does a rename")
        T.eq(L.stateOf(L.withState(config, "default", null), "default"), null, "withState(null) forgets it")
        T.eq(L.stateOf(L.withState(config, "default", now), "default").settings, now.settings, "and with one replaces it")

        ready.start()
    }

    // ---- LayoutService in the sandbox --------------------------------------------
    Timer {
        id: ready
        interval: 20
        repeat: true
        onTriggered: {
            root.waits += 1
            const there = LayoutService.loaded && SettingsService.loaded && LayoutService.stateSettled
                && !LayoutService.builtinApplying.length
            if (!there && root.waits < 250) return
            stop()
            T.ok(there, "the layout, the settings and the profile in use are settled (" + Paths.configDir + ")")
            const home = LayoutService.activeProfile
            T.eq(home, "default", "the sandbox starts in Default")
            T.ok(L.stateOf(LayoutService.config, home) !== null, "which holds a state from the first start on")
            T.ok(L.hasAdopted(LayoutService.config, "profileState"), "and the file says so")
            // A first start with a shipped Default (config/builtin-profiles/
            // default): adopted with the shipped modes, and its setup applied.
            const shipped = LayoutService.builtinProfiles["default"]
            if (shipped !== undefined) {
                T.eq(LayoutService.builtinOf(home), "default", "a first start adopts Default as the shipped one")
                T.eq(Object.keys(L.modesOf(LayoutService.config, home)).sort(), Object.keys(shipped.modes).sort(),
                     "with the shipped modes")
                T.eq(SettingsService.value("appearance.accent"), shipped.settings.appearance.accent,
                     "and applies its shipped setup")
                T.eq(L.stateOf(LayoutService.config, home).settings.appearance.accent, shipped.settings.appearance.accent,
                     "which is its state")
            } else {
                T.eq(LayoutService.builtinOf(home), "", "without its file Default is the user's profile, as before")
            }

            // Default as the user set it: a colour, the notch's body, its two
            // lists and the lock screen, a mode's blur - and the machine's
            // own place and keyboard.
            SettingsService.setAll({ "appearance.panelColor": "#202020", "appearance.accent": "#aa0000",
                                     "notch.bodyHeight": 32, "terminal.fontSize": 13,
                                     "weather.lat": 12.5, "input.kbLayout": "us" })
            SettingsService.set("appearance.blurStrength", 0.2)
            LayoutService.notchResetLayout()
            LayoutService.notchRemove(LayoutService.notchLayout.expanded[0].id)
            LayoutService.lockRemove(LayoutService.lockLayout.lock[0].id)
            root.homeNotch = LayoutService.notchLayout
            root.homeLock = LayoutService.lockLayout

            root.studio = LayoutService.addProfile("Studio")
            T.eq(L.stateOf(LayoutService.config, root.studio), null, "a new profile has no state")
            T.eq(LayoutService.setActiveProfile(root.studio), true, "into it")
            const left = L.stateOf(LayoutService.config, home)
            T.eq(left.settings.appearance.panelColor, "#202020", "leaving Default stores its panel colour")
            T.eq(left.settings.notch.bodyHeight, 32, "the notch's body")
            T.eq(left.notch, root.homeNotch, "the notch's lists")
            T.eq(left.lock, root.homeLock, "and the lock screen")
            T.eq(left.settings.weather.lat, undefined, "but not the weather place")
            T.eq(left.settings.input.kbLayout, undefined, "nor the keyboard layout")
            T.eq(left.settings.appearance.blurStrength, undefined, "nor what the mode owns")
            T.eq(SettingsService.value("appearance.panelColor"), "#202020",
                 "a profile without a state keeps what is set")
            T.eq(L.stateOf(LayoutService.config, root.studio).settings.appearance.panelColor, "#202020",
                 "and takes it as its own")
            T.eq(LayoutService.undoStack.length, 0, "undo starts again in the profile entered")
            changed.start()
        }
    }

    // Studio changed, then back: Default's state is put back, the machine's
    // settings stay, the mode's come from the mode.
    Timer {
        id: changed
        interval: 50
        onTriggered: {
            SettingsService.setAll({ "appearance.panelColor": "#303030", "appearance.accent": "#00aa00",
                                     "notch.bodyHeight": 48, "terminal.fontSize": 15,
                                     "weather.lat": 23.5, "input.kbLayout": "fr" })
            LayoutService.notchResetLayout()
            LayoutService.lockResetLayout()
            T.eq(LayoutService.setActiveProfile("default"), true, "back to Default")
            T.eq(SettingsService.value("appearance.panelColor"), "#202020", "its panel colour is back")
            T.eq(SettingsService.value("appearance.accent"), "#aa0000", "its accent")
            T.eq(SettingsService.value("notch.bodyHeight"), 32, "the notch's body")
            T.eq(SettingsService.value("terminal.fontSize"), 13, "the terminal's font size")
            T.eq(LayoutService.notchLayout, root.homeNotch, "the notch's lists")
            T.eq(LayoutService.lockLayout, root.homeLock, "and the lock screen")
            T.eq(SettingsService.value("weather.lat"), 23.5, "the weather place stays what it is")
            T.eq(SettingsService.value("input.kbLayout"), "fr", "and so does the keyboard layout")
            T.eq(SettingsService.value("appearance.blurStrength"), 0.2, "the blur comes from Default's mode")
            const away = L.stateOf(LayoutService.config, root.studio)
            T.eq([away.settings.appearance.panelColor, away.settings.notch.bodyHeight], ["#303030", 48],
                 "Studio keeps its own")
            T.eq(away.notch, L.defaultNotch(), "with its notch")
            missing.start()
        }
    }

    // A setting the state does not name - added after it was stored - keeps
    // the value it has; duplicating and removing the profile in use.
    Timer {
        id: missing
        interval: 50
        onTriggered: {
            const trimmed = JSON.parse(JSON.stringify(L.stateOf(LayoutService.config, root.studio)))
            delete trimmed.settings.terminal.fontSize
            LayoutService.config = L.withState(LayoutService.config, root.studio, trimmed)
            SettingsService.set("terminal.fontSize", 17)
            T.eq(LayoutService.setActiveProfile(root.studio), true, "into Studio again")
            T.eq(SettingsService.value("appearance.panelColor"), "#303030", "its panel colour is back")
            T.eq(SettingsService.value("terminal.fontSize"), 17, "a setting its state does not name is not reset")
            const twin = LayoutService.duplicateProfile(root.studio, "Studio copy")
            T.eq(L.stateOf(LayoutService.config, twin).settings.terminal.fontSize, 17,
                 "a duplicate of the profile in use takes the settings as they are now")
            T.eq(LayoutService.removeProfile(root.studio), true, "removing the profile in use")
            T.eq(LayoutService.activeProfile, "default", "switches to the first one left")
            T.eq(SettingsService.value("appearance.panelColor"), "#202020", "and puts its state back")
            T.ok(LayoutService.profileNames.indexOf(root.studio) < 0, "the removed one is gone")
            root.tries = 0
            backup.start()
        }
    }

    // The first switch of the day kept both files as they were before it.
    Timer {
        id: backup
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            backupLayout.reload()
            const text = backupLayout.text()
            if (!text.length && root.tries < 60) return
            stop()
            T.ok(text.indexOf("\"profiles\"") >= 0, "layout.json was backed up in the sandbox's state directory")
            T.ok(text.indexOf("\"activeProfile\": \"default\"") >= 0, "as it was before the first switch")
            T.ok(text.indexOf("\"Studio\"") < 0, "and only once that day: the later switches did not write it again")
            T.finish("ProfileStateTest")
        }
    }
}
