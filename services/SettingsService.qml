pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "power/PowerSourceLogic.js" as PowerSourceLogic
import "wallpaper/WallpaperLogic.js" as WallpaperLogic
import "appearance/AnimationLogic.js" as AnimationLogic

// User preferences in ~/.config/buchhwin-shell/settings.json. Missing keys fall
// back to defaults; only known primitive values are written back.
Singleton {
    id: root

    readonly property var defaults: ({
        "configVersion": 1,
        "appearance": {
            "theme": "dark",
            // KDE/GTK apps follow the theme (AppThemeService, real session only).
            "appsFollowTheme": false,
            // KDE apps use the shell accent (AppThemeService, real session only).
            "appsAccent": false,
            "appsRestoreOnLogout": true,
            "fontFamily": "Inter Variable",
            "monoFontFamily": "JetBrains Mono",
            "accent": "#4f8ff7", // style: the default the user can change, not a look
            "animationMode": "full",
            "fontScale": 1,
            "cursorTheme": "breeze_cursors",
            "cursorSize": 24,
            "accentFromWallpaper": false,
            "panelOpacity": 0.74,
            "panelColor": "auto",
            "blurStrength": 0.5,
            // How fast every animation runs, the shell's and the
            // compositor's. 1 is the designed speed; the mode above still
            // decides whether things move at all and how far.
            "animationSpeed": 1.0,
            "windowRadius": 16,
            "shellRadius": 20,
            // Rounds the screen's own corners, like a laptop bezel. The radius
            // is the window rounding, so the display and the windows match.
            "screenCorners": true,
            "borderEnabled": true,
            "borderSize": 1,
            "gapsIn": 6,
            "gapsOut": 12,
            "locale": "en_GB",
            // "locale" follows the language above; "24" and "12" override it.
            // The shell could only ever show 24 hours before this, whatever
            // the locale said - the date followed it, the time did not.
            "clockFormat": "locale"
        },
        // Own opacity per window group (PanelStyleService); -1 uses appearance.panelOpacity.
        "panelOpacity": {
            "settings": -1,
            "controlCenter": -1,
            "dashboard": -1,
            "launcher": -1,
            "notificationCenter": -1,
            "notificationPopups": -1,
            "sessionMenu": -1,
            "clipboard": -1,
            "overview": -1,
            "switcher": -1,
            "popups": -1,
            "pillBar": -1,
            "widgets": -1,
            "osd": -1
        },
        "desktop": {
            "clockIndicators": true,
            "osd": true,
            "autoProfile": false,
            // The control center's tiles became a grid; this remembers that an
            // existing panel was given the sizes its tiles start at, so it
            // happens once and never undoes a size the user then chose.
            "quickSizesAdopted": false,
            // The control center's own size, dragged from the corner of the
            // panel while its tiles are being arranged. 0 means "not set yet".
            "quickWidth": 0,
            "quickHeight": 0,
            // The dashboard keeps its own, the same way: 0 means "never
            // dragged", and the panel then follows the width its view asks for.
            "dashboardWidth": 0,
            "dashboardHeight": 0
        },
        // Desktop mode "notch" (shell/notch): exclusive zone, fullscreen and hover.
        "notch": {
            "reserve": true,
            "fullscreen": "hide",
            "expandOnHover": true,
            "eventCount": 2,
            // The notch is not nailed to a size: both shapes are dragged in
            // the layout editor. The strip only horizontally - its height is
            // the notch's own - and the overview freely. A width of 0 means
            // "not set yet" and the clamp fills the default in.
            // "notch" hangs from the top edge with concave ears; "pill" lets
            // go of it and is rounded all the way round. Everything it carries
            // and everything it does stays the same.
            "shape": "notch",
            "collapsedWidth": 0,
            "expandedWidth": 0,
            // A floor, not a ceiling: the overview still grows when what it
            // carries needs more room than this.
            "expandedHeight": 0,
            // The big time and the long date became an item; this remembers
            // that an existing notch was given one, so it happens once.
            "headerAdopted": false
        },
        "workspaces": {
            "mode": "open",
            "style": "numbers",
            "count": 5,
            // Each monitor its own 1-N. On by default because with a single
            // screen it is the behaviour that was always there - offset 0,
            // ids 1-10, the same keys - so it only differs once there is
            // something to differ about.
            "perMonitor": true
        },
        "wallpaper": {
            "path": "",
            "folder": "~/Pictures/Desktop",
            "slideshow": false,
            "intervalMinutes": 15,
            "order": "sequential",
            // Which images the slideshow rotates through: every one in the
            // folder, the favourites, or a list the user picks. It replaced a
            // boolean that made favourites do two jobs at once.
            "slideshowSource": "all",
            "slideshowFolder": ""
        },
        "login": {
            // Which wallpaper the greeter shows. Empty means "whatever the
            // desktop has", which is what sddm-theme.sh already does when it
            // is given no --wallpaper. A path pins it to one picture instead.
            "wallpaper": "",
            "blur": true,
            "accent": "shell",
            "font": "shell",
            "dateFormat": "dddd, d MMMM"
        },
        "notifications": {
            "popupTimeoutMs": 6000,
            "suppressFullscreen": true,
            "suppressGames": true,
            "dndTomorrowHour": 6
        },
        "emoji": {
            "tone": 0
        },
        // The short tour on the first start; closing it at any point sets this.
        "onboarding": {
            "completed": false
        },
        "launcher": {
            "fileSearch": true,
            "searchEngine": "duckduckgo",
            "searchUrl": ""
        },
        "autostart": {
            "apps": "",
            "system": true
        },
        "lock": {
            "showAvatar": true,
            "showMedia": false,
            "showStatus": false,
            "showPowerButtons": false,
            // Fingerprint unlock: auto (not while the lid is closed) | on | off.
            "fingerprint": "auto"
        },
        "terminal": {
            "fontFamily": "JetBrains Mono",
            "fontSize": 11,
            "opacity": 0.86,
            "padding": 12,
            "cursorShape": "beam",
            "cursorBlink": true,
            "cursorBlinkStyle": "soft",
            "cursorTrail": "short",
            "promptColor": "shell",
            "errorColor": "#f07178", // style: a terminal palette default
            "symbol": "❯",
            "errorSymbol": "❯",
            "gitSymbol": "󰊢",
            "username": true,
            "hostname": true,
            "directory": true,
            "git": true,
            "gitStatus": true,
            "python": false,
            "nodejs": false,
            "docker": false,
            "commandDuration": true,
            "jobs": true,
            "time": false,
            "twoLine": true,
            "newline": true,
            "directoryDepth": 3,
            "durationMin": 1500,
            "timeFormat": "%H:%M",
            "fastfetchOnStart": true,
            "imageSize": 30,
            "previewGit": true
        },
        // The colours picked off the screen, newest first. A comma-string,
        // because `sanitizedNode` turns a stored array into {"0": ...} on the
        // next write of any setting - the same reason `autostart.apps` is one.
        "colorPicker": {
            "history": ""
        },
        "clipboard": {
            "history": true,
            "maxItems": 200
        },
        "recording": {
            "audio": "off",
            "fps": 30,
            "folder": "~/Videos/Recordings"
        },
        "drives": {
            "notify": true,
            "autoOpen": false
        },
        "weather": {
            "enabled": true,
            "locationName": "",
            "lat": 0,
            "lon": 0,
            "unit": "celsius",
            "refreshMinutes": 30
        },
        "input": {
            "kbLayout": "de",
            "kbVariant": "",
            "repeatRate": 25,
            "repeatDelay": 600,
            "sensitivity": 0,
            "accelProfile": "adaptive",
            "mouseNaturalScroll": false,
            "touchpadNaturalScroll": true,
            "touchpadScrollFactor": 1.0,
            "tapToClick": true,
            "disableWhileTyping": true
        },
        // Touchpad gestures (GestureService, services/input/GestureLogic.js).
        "gestures": {
            "enabled": true,
            "threeHorizontal": "workspace",
            "threeUp": "overview",
            "threeDown": "closePanel",
            "fourHorizontal": "none",
            "fourUp": "none",
            "fourDown": "none",
            "pinchIn": "launcher",
            "pinchOut": "none",
            "naturalSwipe": true,
            "createNew": false
        },
        "nightLight": {
            "mode": "off",
            "lastMode": "schedule",
            "temperature": 4000,
            "start": "20:00",
            "end": "07:00"
        },
        "power": {
            "lockBeforeSleep": true,
            "lowBatteryWarning": true,
            "lowBatteryLevel": 20,
            // Per power source (services/power/PowerSourceLogic.js); files
            // from before the split are migrated when they load.
            "battery": {
                "screenOffMinutes": 5,
                "lockMinutes": 0,
                "suspendMinutes": 15,
                "dimBeforeScreenOff": true,
                "lidAction": "suspend",
                "profile": "powerSaver"
            },
            "ac": {
                "screenOffMinutes": 10,
                "lockMinutes": 0,
                "suspendMinutes": 0,
                "dimBeforeScreenOff": true,
                "lidAction": "suspend",
                "profile": "balanced"
            }
        },
        "calendar": {
            "enabled": true,
            "eventHint": true,
            "hintMinutes": 15,
            "hiddenCalendars": "",
            // Collection id last used for a new event; dashboard view month | week | day.
            "newEventCalendar": "",
            "eventColor": "accent",
            "dashboardView": "month"
        },
        "updates": {
            "checkHours": 24,
            "notify": true
        }
    })

    property var data: defaults
    property bool loaded: false

    readonly property string theme: value("appearance.theme")
    readonly property string accent: value("appearance.accent")
    readonly property string fontFamily: value("appearance.fontFamily")
    readonly property string monoFontFamily: value("appearance.monoFontFamily")
    readonly property string animationMode: value("appearance.animationMode")
    readonly property string cursorTheme: value("appearance.cursorTheme")
    readonly property int cursorSize: value("appearance.cursorSize")
    readonly property real panelOpacity: Math.max(0.4, Math.min(1, value("appearance.panelOpacity")))
    readonly property real blurStrength: Math.max(0, Math.min(1, value("appearance.blurStrength")))
    // Bounded where it stays useful: a quarter speed is a slow, deliberate
    // glide and three times is as close to instant as motion gets before it
    // stops reading as motion at all.
    readonly property real animationSpeed: Math.max(0.25, Math.min(3, value("appearance.animationSpeed")))
    readonly property int windowRadius: Math.max(0, Math.min(32, value("appearance.windowRadius")))
    readonly property bool borderEnabled: value("appearance.borderEnabled")
    readonly property int borderSize: Math.max(1, Math.min(8, value("appearance.borderSize")))
    readonly property int gapsIn: Math.max(0, Math.min(30, value("appearance.gapsIn")))
    readonly property int gapsOut: Math.max(0, Math.min(60, value("appearance.gapsOut")))
    readonly property string localeName: value("appearance.locale")
    readonly property var locale: Qt.locale(localeName === "system" ? Qt.locale().name : localeName)
    // Whether a time is shown as "6:52 PM" or "18:52". "locale" asks the
    // language itself: a 12-hour format carries "A"/"AP" for the meridiem, and
    // no 24-hour one does. Everything that draws a time reads this and passes
    // it to `TimeFormat`.
    readonly property bool twelveHourClock: {
        const mode = value("appearance.clockFormat")
        if (mode === "12") return true
        if (mode === "24") return false
        return /a/i.test(locale.timeFormat(Locale.ShortFormat))
    }

    readonly property var allowed: ({
        "appearance.theme": ["dark", "light", "auto"],
        "appearance.clockFormat": ["locale", "24", "12"],
        "appearance.animationMode": ["full", "reduced", "off"],
        "wallpaper.order": ["sequential", "random"],
        "wallpaper.slideshowSource": ["all", "favourites", "chosen", "folder"],
        "workspaces.mode": ["open", "gapless", "fixed"],
        "workspaces.style": ["numbers", "dots", "activeDot"],
        "notch.fullscreen": ["hide", "show"],
        "workspaces.count": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        "weather.unit": ["celsius", "fahrenheit"],
        "calendar.dashboardView": ["month", "week", "day"],
        "lock.fingerprint": ["auto", "on", "off"],
        "power.battery.lidAction": ["suspend", "lock", "screenOff", "nothing"],
        "power.ac.lidAction": ["suspend", "lock", "screenOff", "nothing"],
        "power.battery.profile": ["keep", "powerSaver", "balanced", "performance"],
        "power.ac.profile": ["keep", "powerSaver", "balanced", "performance"],
        "power.lowBatteryLevel": [10, 15, 20, 25],
        "calendar.eventColor": ["accent", "calendar"],
        "updates.checkHours": [0, 6, 12, 24],
        "recording.audio": ["off", "desktop", "desktop+mic"],
        "recording.fps": [30, 60],
        "input.accelProfile": ["adaptive", "flat"],
        "gestures.threeHorizontal": ["workspace", "none"],
        "gestures.fourHorizontal": ["workspace", "none"],
        "gestures.threeUp": ["none", "overview", "launcher", "dashboard", "controlCenter", "notifications", "clipboard", "closePanel", "fullscreen", "float", "close"],
        "gestures.threeDown": ["none", "overview", "launcher", "dashboard", "controlCenter", "notifications", "clipboard", "closePanel", "fullscreen", "float", "close"],
        "gestures.fourUp": ["none", "overview", "launcher", "dashboard", "controlCenter", "notifications", "clipboard", "closePanel", "fullscreen", "float", "close"],
        "gestures.fourDown": ["none", "overview", "launcher", "dashboard", "controlCenter", "notifications", "clipboard", "closePanel", "fullscreen", "float", "close"],
        "gestures.pinchIn": ["none", "overview", "launcher", "dashboard", "controlCenter", "notifications", "clipboard", "closePanel", "fullscreen", "float", "close"],
        "gestures.pinchOut": ["none", "overview", "launcher", "dashboard", "controlCenter", "notifications", "clipboard", "closePanel", "fullscreen", "float", "close"],
        "appearance.fontScale": [0.9, 1, 1.1, 1.25],
        "login.dateFormat": ["dddd, d MMMM", "dddd, d MMM", "d MMMM yyyy", "dd.MM.yyyy"],
        "terminal.cursorShape": ["beam", "block", "underline"],
        "terminal.cursorBlinkStyle": ["hard", "soft"],
        "terminal.cursorTrail": ["off", "short", "long"],
        "launcher.searchEngine": ["duckduckgo", "google", "startpage", "wikipedia", "custom"],
        "nightLight.mode": ["off", "manual", "schedule", "sun"],
        "nightLight.lastMode": ["manual", "schedule", "sun"]
    })

    function expandHome(path) {
        return path.startsWith("~/") ? Quickshell.env("HOME") + path.slice(1) : path
    }

    function lookup(source, path) {
        let node = source
        for (const part of path.split(".")) {
            if (node === null || node === undefined || typeof node !== "object") return undefined
            node = node[part]
        }
        return node
    }

    function value(path) {
        const stored = lookup(data, path)
        const fallback = lookup(defaults, path)
        if (stored === undefined || stored === null || typeof stored !== typeof fallback) return fallback
        const choices = allowed[path]
        if (choices && choices.indexOf(stored) < 0) return fallback
        return stored
    }

    function set(path, newValue) {
        const fallback = lookup(defaults, path)
        if (fallback === undefined || typeof newValue !== typeof fallback) {
            console.warn("buchhwin-shell: rejected setting", path)
            return false
        }
        const choices = allowed[path]
        if (choices && choices.indexOf(newValue) < 0) return false
        const next = sanitized()
        const parts = path.split(".")
        let node = next
        for (let i = 0; i < parts.length - 1; ++i) node = node[parts[i]]
        node[parts[parts.length - 1]] = newValue
        data = next
        settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
        return true
    }

    // Several keys in one write. Two `set` calls in the same turn of the event
    // loop each replace the file, and the first write is dropped in flight -
    // Quickshell says so in the log, and the shell's own smoke test fails on
    // it. Migrations that run together use this.
    function setAll(values) {
        const next = sanitized()
        let changed = false
        for (const path of Object.keys(values || {})) {
            const newValue = values[path]
            const fallback = lookup(defaults, path)
            if (fallback === undefined || typeof newValue !== typeof fallback) {
                console.warn("buchhwin-shell: rejected setting", path)
                continue
            }
            const choices = allowed[path]
            if (choices && choices.indexOf(newValue) < 0) continue
            const parts = path.split(".")
            let node = next
            for (let i = 0; i < parts.length - 1; ++i) node = node[parts[i]]
            node[parts[parts.length - 1]] = newValue
            changed = true
        }
        if (!changed) return false
        data = next
        settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
        return true
    }

    // Rebuild the document from defaults so unknown or malformed keys are dropped.
    function sanitized() {
        const result = {}
        for (const section of Object.keys(defaults)) {
            result[section] = typeof defaults[section] === "object"
                ? sanitizedNode(defaults[section], section) : defaults[section]
        }
        return result
    }

    // Nested groups (such as power.battery) are rebuilt the same way.
    function sanitizedNode(node, prefix) {
        const result = {}
        for (const key of Object.keys(node)) {
            const path = prefix + "." + key
            result[key] = node[key] !== null && typeof node[key] === "object" ? sanitizedNode(node[key], path) : value(path)
        }
        return result
    }

    // A reload can catch the file while it is being replaced (empty, missing or
    // half written). Once loaded, such reads keep the current settings instead
    // of falling back to defaults, which the next change would write to disk.
    function load() {
        const text = settingsFile.text()
        if (loaded && !text.trim().length) return
        try {
            data = text.trim().length
                ? AnimationLogic.migrate(WallpaperLogic.migrate(PowerSourceLogic.migrate(JSON.parse(text)))) : defaults
        } catch (error) {
            if (loaded) {
                console.warn("buchhwin-shell: settings file unreadable, keeping current settings:", error)
                return
            }
            console.warn("buchhwin-shell: settings unreadable, using defaults:", error)
            data = defaults
        }
        loaded = true
    }

    FileView {
        id: settingsFile
        path: Paths.configDir + "/settings.json"
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: root.load()
        onLoadFailed: root.loaded = true
        onFileChanged: reload()
    }
}
