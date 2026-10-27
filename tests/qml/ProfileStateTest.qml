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
// the keyboard layout and the pointer, the screens, power and the fingerprint
// reader, the clipboard history, what the login starts ...), and except what
// the five modes own.
// First the pure half: which settings are a profile's - every setting sorted
// into one of the three, so a new one cannot go unclassified -, and the state
// in the file. Then LayoutService against the runner's sandbox: leaving a profile
// stores its state, entering one with a state puts it back, one without keeps
// what is set and takes it, a setting the state does not name goes back to its
// default, and the first switch of the day leaves a backup in the sandbox's state
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
        T.ok(P.isProfileSetting("dock.enabled") && P.isProfileSetting("dock.visibility") && P.isProfileSetting("panelOpacity.dock"),
             "the dock is a profile's")
        T.ok(P.isGlobalSetting("dock.screens") && !P.isProfileSetting("dock.screens"), "but its screens are the machine's")
        T.eq(["weather.lat", "weather.lon", "weather.locationName", "weather.autoLocate", "input.kbLayout",
              "input.kbVariant", "display.x11Scale", "display.xwaylandSharp", "onboarding.completed",
              "calendar.hiddenCalendars", "calendar.newEventCalendar", "colorPicker.history",
              "wallpaper.recentFolders", "configVersion",
              "desktop.settingsMoveX", "desktop.settingsMoveY", "power.lockBeforeSleep", "power.lowBatteryLevel",
              "power.battery.lidAction", "power.ac.suspendMinutes", "lock.fingerprint"].filter(P.isProfileSetting), [],
             "the machine's and the person's settings are global, power and the fingerprint reader too")
        T.ok(P.isProfileSetting("weather.unit") && P.isProfileSetting("input.repeatRate")
             && P.isProfileSetting("wallpaper.path") && P.isProfileSetting("lock.showAvatar"),
             "their neighbours are a profile's")
        T.eq(["clipboard.history", "clipboard.maxItems", "input.tapToClick", "input.touchpadNaturalScroll",
              "input.mouseNaturalScroll", "input.sensitivity", "input.accelProfile", "input.touchpadScrollFactor",
              "input.disableWhileTyping", "autostart.apps", "autostart.system", "updates.checkHours",
              "updates.shellAuto", "drives.autoOpen", "terminal.alacrittyDaemon", "notch.screens",
              "desktop.worldClocks", "commandWidgets.one.command", "commandWidgets.three.interval"].filter(P.isProfileSetting), [],
             "the clipboard history, the pointer, what the login starts, updates, drives, how Alacritty runs, "
             + "the notch's screens, the world clock's places and the command widgets are the machine's")
        T.ok(P.isProfileSetting("input.repeatRate") && P.isProfileSetting("input.repeatDelay")
             && P.isProfileSetting("input.browserScroll") && P.isProfileSetting("terminal.fontSize"),
             "the keys' repeat, the shell's own scrolling and the rest of the terminal stay a profile's")

        // Every entry of the two lists names a setting there is: a typo
        // ("dock.screen") would leave the real one a profile's, and nothing
        // else would notice.
        T.eq(P.GLOBAL_SETTINGS.filter(entry => SettingsService.defaultOf(entry) === undefined), [],
             "every GLOBAL_SETTINGS entry is a setting or a group of SettingsService.defaults")
        T.eq(P.MODE_SCOPED.filter(leaf => {
            const fallback = SettingsService.defaultOf(P.modeScopedPath(leaf))
            return fallback === undefined || typeof fallback === "object"
        }), [], "every MODE_SCOPED leaf is a setting of SettingsService.defaults")

        // Every setting is a profile's unless it is listed as the machine's or
        // a mode's (pitfall 115): a new key lands here first, and fails until
        // someone decides. A profile's? Add it below. The machine's or the
        // person's? ProfileLogic.GLOBAL_SETTINGS and profile-export.py's DROP.
        // A mode's? ProfileLogic.MODE_SCOPED.
        const profileOwned = {
            appearance: ["accent", "accentFromWallpaper", "appsAccent", "appsFollowTheme", "appsRestoreOnLogout",
                         "autoTheme", "clockFormat", "cursorSize", "cursorTheme", "dateOrder", "fontFamily", "fontScale",
                         "locale", "monoFontFamily", "panelColor", "panelScrim", "screenCorners", "shortDateNumbers",
                         "statusColors", "theme"],
            audio: ["micKeyAll"],
            bluetooth: ["batteryWarning"],
            calendar: ["enabled", "eventColor", "eventHint", "hintMinutes"],
            desktop: ["autoModeBattery", "autoModeDesk", "autoModeRoad", "autoProfile", "clockIndicators", "dashboardHeight", "dashboardWidth", "launcherHeight",
                      "launcherWidth", "mediaVisualizer", "osd", "quickHeight", "quickWidth"],
            dock: ["activeClick", "badges", "enabled", "iconSize", "magnification", "margin", "position", "previews",
                   "runningOn", "shape", "showRunning", "span", "startOpens", "visibility", "wheelVolume"],
            emoji: ["tone"],
            gestures: ["createNew", "enabled", "fourDown", "fourHorizontal", "fourUp", "naturalSwipe", "pinchIn",
                       "pinchOut", "threeDown", "threeHorizontal", "threeUp"],
            input: ["browserScroll", "passthroughCitrix", "repeatDelay", "repeatRate"],
            launcher: ["categories", "codeFolders", "conversions", "exchangeRates", "fileSearch", "modeOrder", "pinned",
                       "recentFiles", "searchEngine", "searchUrl", "showPinned", "windows"],
            lock: ["showAvatar", "showPowerButtons", "showStatus"],
            login: ["accent", "blur", "dateFormat", "font", "wallpaper"],
            network: ["portalNotify"],
            nightLight: ["end", "lastMode", "mode", "start", "temperature"],
            notch: ["accentGlyphs", "bodyHeight", "bodyPadding", "bodyRadius", "clickAction", "closeDelay",
                    "collapsedWidth", "displayMedia", "displayNotifications", "displayOsd", "dockDuplicates",
                    "eventCount", "expandedHeight", "expandedWidth", "fullscreen", "hoverMode", "middleAction",
                    "openDelay", "osdStyle", "panelOrigin", "reserve", "rightAction", "shape", "swipe"],
            notifications: ["dndTomorrowHour", "fullscreenElsewhere", "fullscreenExceptions", "missedSummary",
                            "popupTimeoutMs", "sounds", "suppressFullscreen", "suppressGames", "suppressSharing"],
            panelOpacity: ["clipboard", "controlCenter", "dashboard", "dock", "launcher", "notificationCenter",
                           "notificationPopups", "osd", "overview", "pillBar", "popups", "sessionMenu", "settings",
                           "switcher", "widgets"],
            recording: ["audio", "folder", "fps"],
            terminal: ["commandDuration", "cursorBlink", "cursorBlinkStyle", "cursorShape", "cursorTrail", "directory",
                       "directoryDepth", "docker", "durationMin", "errorColor", "errorSymbol", "fastfetchOnStart",
                       "fontFamily", "fontSize", "git", "gitStatus", "gitSymbol", "hostname", "imageSize", "jobs",
                       "newline", "nodejs", "opacity", "padding", "personalShell", "previewGit", "promptColor",
                       "python", "symbol", "time", "timeFormat", "twoLine", "username"],
            timer: ["sound"],
            toasts: ["capsLock", "charger", "output", "vpn"],
            wallpaper: ["darkPath", "folder", "intervalMinutes", "lightPath", "order", "path", "slideshow", "slideshowFolder",
                        "slideshowSource", "themePair"],
            weather: ["enabled", "refreshMinutes", "unit"],
            windows: ["minimizeRequests"],
            workspaces: ["count", "keepEmpty", "mode", "perMonitor", "style"]
        }
        const listed = []
        for (const group of Object.keys(profileOwned))
            for (const leaf of profileOwned[group]) listed.push(group + "." + leaf)
        const owned = Object.keys(P.settingLeaves(SettingsService.defaults, ""))
        T.eq(owned.filter(path => listed.indexOf(path) < 0).sort(), [],
             "no setting is a profile's without a decision: a new one goes into this list, GLOBAL_SETTINGS or MODE_SCOPED")
        T.eq(listed.filter(path => owned.indexOf(path) < 0).sort(), [],
             "and every one listed here is still a profile's setting")
        T.eq(P.profileSettings({ appearance: { panelColor: "#202020", gapsIn: 3 }, weather: { lat: 12.5, unit: "celsius" },
                                 recording: { folder: "~/Videos" } }, "/home/u"),
             { appearance: { panelColor: "#202020" }, weather: { unit: "celsius" }, recording: { folder: "/home/u/Videos" } },
             "a profile's settings as a tree, home paths expanded")

        // ---- the state in the file ------------------------------------------------
        const raw = { settings: { appearance: { panelColor: "#202020", blurStrength: 0.3, list: [1] },
                                  weather: { lat: 12.5, unit: "fahrenheit" }, input: { kbLayout: "us" }, odd: null,
                                  power: { lowBatteryLevel: 15, ac: { lidAction: "nothing" } },
                                  lock: { fingerprint: "off", showAvatar: false } },
                      notch: { collapsed: [], expanded: [] }, lock: { lock: [] } }
        const config = L.sanitize({ profiles: { default: { label: "Default", modes: {}, state: raw } } })
        const state = L.stateOf(config, "default")
        T.eq(state.settings, { appearance: { panelColor: "#202020" }, weather: { unit: "fahrenheit" },
                               lock: { showAvatar: false } },
             "the sanitizer keeps a profile's settings and drops the mode's, the machine's (a state stored "
             + "with power and the fingerprint reader in it too), lists and nulls")
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
        const docked = L.sanitize({ dock: { center: [{ id: "dock-apps", items: [{ type: "apps" }] }], pins: ["x"] }, profiles: { a: { modes: {} } } })
        T.eq(L.restoreStateLayout(docked, partial).dock, L.defaultDock(), "the dock is the profile's: a state without one gets the default")
        T.eq(L.applyBuiltinLayout(docked, { notch: null }).dock, L.defaultDock(), "and so does a shipped profile without one")
        T.eq(P.completeLeaves({ "dock.enabled": true }, { "dock.enabled": false, "dock.margin": 8 }),
             { "dock.enabled": true, "dock.margin": 8 }, "a profile's settings: what it names, the default for the rest")

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
            T.eq([LayoutService.freshDecided, LayoutService.freshLayout], [true, false],
                 "the sandbox's start was a first one (both files missing), and it is over once settled")
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
                                     "weather.lat": 12.5, "input.kbLayout": "us",
                                     "power.ac.lidAction": "lock", "lock.fingerprint": "off" })
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
            T.eq(left.settings.power, undefined, "nor power")
            T.eq(left.settings.lock.fingerprint, undefined, "nor the fingerprint reader")
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
                                     "weather.lat": 23.5, "input.kbLayout": "fr",
                                     "power.ac.lidAction": "nothing", "lock.fingerprint": "on",
                                     "clipboard.history": false, "input.tapToClick": false,
                                     "autostart.system": false })
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
            T.eq([SettingsService.value("power.ac.lidAction"), SettingsService.value("lock.fingerprint")], ["nothing", "on"],
                 "and power and the fingerprint reader")
            T.eq([SettingsService.value("clipboard.history"), SettingsService.value("input.tapToClick"),
                  SettingsService.value("autostart.system")], [false, false, false],
                 "a clipboard history turned off stays off, and so do the touchpad and the login's own choices")
            T.eq(SettingsService.value("appearance.blurStrength"), 0.2, "the blur comes from Default's mode")
            const away = L.stateOf(LayoutService.config, root.studio)
            T.eq([away.settings.appearance.panelColor, away.settings.notch.bodyHeight], ["#303030", 48],
                 "Studio keeps its own")
            T.eq(away.notch, L.defaultNotch(), "with its notch")
            missing.start()
        }
    }

    // A setting the state does not name - added after it was stored, as the
    // dock was after every state stored before it - is the default there,
    // not what the profile left had: the dock switched on in one profile does
    // not come along into the other (17.10.). Duplicating and removing the
    // profile in use.
    Timer {
        id: missing
        interval: 50
        onTriggered: {
            const trimmed = JSON.parse(JSON.stringify(L.stateOf(LayoutService.config, root.studio)))
            delete trimmed.settings.terminal.fontSize
            delete trimmed.settings.dock
            delete trimmed.dock
            // As an older shell stored it: with power and the fingerprint
            // reader in it, past the sanitizer.
            const older = JSON.parse(JSON.stringify(L.withState(LayoutService.config, root.studio, trimmed)))
            older.profiles[root.studio].state.settings.power = { ac: { lidAction: "suspend" } }
            older.profiles[root.studio].state.settings.lock = { fingerprint: "auto" }
            LayoutService.config = older
            SettingsService.setAll({ "terminal.fontSize": 17, "dock.enabled": true, "dock.visibility": "always" })
            LayoutService.dockPin("org.example.App")
            T.eq(LayoutService.setActiveProfile(root.studio), true, "into Studio again")
            T.eq(SettingsService.value("appearance.panelColor"), "#303030", "its panel colour is back")
            const fontDefault = SettingsService.defaultOf("terminal.fontSize")
            T.eq(SettingsService.value("terminal.fontSize"), fontDefault, "a setting its state does not name is the default")
            T.eq([SettingsService.value("dock.enabled"), SettingsService.value("dock.visibility")],
                 [false, SettingsService.defaultOf("dock.visibility")], "a state from before the dock: the dock off, not Default's")
            T.eq(LayoutService.dockLayout, L.defaultDock(), "and the default dock, not Default's pins")
            T.eq([SettingsService.value("power.ac.lidAction"), SettingsService.value("lock.fingerprint")], ["nothing", "on"],
                 "a state stored with power and the fingerprint reader in it does not put them back")
            const twin = LayoutService.duplicateProfile(root.studio, "Studio copy")
            T.eq(L.stateOf(LayoutService.config, twin).settings.terminal.fontSize, fontDefault,
                 "a duplicate of the profile in use takes the settings as they are now")
            // An undo step keeps only what undo puts back: the states, the
            // saved notch presets and the markers come from the config at hand.
            const step = JSON.parse(LayoutService.undoStack[LayoutService.undoStack.length - 1])
            T.eq(Object.keys(step.config.profiles).filter(name => step.config.profiles[name].state !== undefined), [],
                 "an undo step carries no profile's state")
            T.ok(!("notchPresets" in step.config) && !("adopted" in step.config) && !("states" in step),
                 "nor the notch presets, the markers or a removed profile's state")
            // The one state undo cannot take from the config: a profile removed
            // while the steps stay, which its own step hands back.
            const twinState = L.stateOf(LayoutService.config, twin)
            T.eq(LayoutService.removeProfile(twin), true, "removing a profile not in use")
            const removal = JSON.parse(LayoutService.undoStack[LayoutService.undoStack.length - 1])
            T.eq(Object.keys(removal.states || {}), [twin], "its step carries that profile's state and no other")
            LayoutService.undo()
            T.ok(LayoutService.profileNames.indexOf(twin) >= 0, "undo brings it back")
            T.eq(L.stateOf(LayoutService.config, twin), twinState, "with the state it had")
            T.ok(L.stateOf(LayoutService.config, "default") !== null && L.hasAdopted(LayoutService.config, "profileState"),
                 "and the other states and the markers are the config's")
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
