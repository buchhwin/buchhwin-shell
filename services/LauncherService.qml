pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.theme
import "launcher/Calculator.js" as Calc
import "launcher/Usage.js" as Usage
import "launcher/IconLogic.js" as IconLogic
import "launcher/WebSearch.js" as Web
import "settings/SettingsNavLogic.js" as Nav

// Launcher providers. Prefixes: none = apps (+ calculator, commands and, for
// something that looks like an address, "Open"), ">" commands, "/" files
// (plocate), "@" settings, "=" calculator, "?" web search, ":" emoji.
Singleton {
    id: root

    // The file mode disappears with its setting rather than staying and
    // finding nothing: an option that changes nothing is worse than no option.
    readonly property bool fileSearch: SettingsService.value("launcher.fileSearch")
    readonly property var modes: [
        { id: "apps", prefix: "", label: "Apps", icon: "󰀻" },
        { id: "commands", prefix: ">", label: "Commands", icon: "󰘳" },
        { id: "settings", prefix: "@", label: "Settings", icon: Icons.settings },
        { id: "calculator", prefix: "=", label: "Calculator", icon: "󰃬" },
        { id: "web", prefix: "?", label: "Web", icon: "󰖟" },
        { id: "emoji", prefix: ":", label: "Emoji", icon: "󰞅" }
    ].concat(fileSearch ? [{ id: "files", prefix: "/", label: "Files", icon: Icons.folder }] : [])

    readonly property var categories: [
        { name: "All", icon: "󰀻", keys: [] },
        { name: "Internet", icon: "󰖟", keys: ["Network", "WebBrowser", "Email", "InstantMessaging"] },
        { name: "Office", icon: "󰈙", keys: ["Office", "Calendar", "ContactManagement"] },
        { name: "Graphics", icon: "󰋩", keys: ["Graphics", "2DGraphics", "3DGraphics", "Photography"] },
        { name: "Multimedia", icon: "󰝚", keys: ["AudioVideo", "Audio", "Video", "Player"] },
        { name: "Development", icon: "󰅩", keys: ["Development", "IDE"] },
        { name: "System", icon: Icons.settings, keys: ["System", "Settings", "Security", "Monitor"] },
        { name: "Utilities", icon: "󰦪", keys: ["Utility", "TextEditor", "TerminalEmulator", "FileManager"] },
        { name: "Games", icon: "󰊴", keys: ["Game"] }
    ]
    // Categories that contain at least one visible app, with their app count.
    readonly property var availableCategories: {
        const visible = DesktopEntries.applications.values.filter(app => app && !app.noDisplay)
        return categories.map(item => Object.assign({}, item, {
            count: item.keys.length ? visible.filter(app => inCategory(app, item)).length : visible.length
        })).filter(item => !item.keys.length || item.count > 0)
    }

    function inCategory(app, category) {
        return !category || !category.keys.length || category.keys.some(key => (app.categories || []).indexOf(key) >= 0)
    }

    // App launch overrides keep session integration (KWallet, Zsh profile).
    readonly property var appOverrides: ({
        "brave-browser": "launch-brave.sh",
        "com.brave.Browser": "launch-brave.sh",
        "kitty": "launch-kitty.sh"
    })

    readonly property var commands: [
        { title: "Control Center", keywords: "control center audio wifi bluetooth kontrollzentrum wlan", icon: Icons.settings, run: () => PanelService.open("controlCenter") },
        { title: "Notifications", keywords: "notifications history benachrichtigungen verlauf", icon: "󰂚", run: () => PanelService.open("notifications") },
        { title: "Dashboard", keywords: "calendar clock weather time kalender uhr wetter", icon: "󰃭", run: () => PanelService.open("dashboard") },
        { title: "Refresh weather", keywords: "weather refresh open-meteo wetter aktualisieren", icon: "󰖐", run: () => { WeatherService.refresh(); PanelService.open("dashboard") } },
        { title: "Open calendar in Merkuro", keywords: "calendar events google akonadi kalender termine", icon: "󰸗", run: () => CalendarService.openManager() },
        { title: "Desktop mode: Widgets", keywords: "mode widgets desktop modus", icon: Icons.edit, run: () => LayoutService.setMode("widgets") },
        { title: "Desktop mode: Bar", keywords: "mode bar pills top panel modus leiste oben", icon: "󰘔", run: () => LayoutService.setMode("pills") },
        { title: "Desktop mode: Notch", keywords: "mode notch island dynamic time modus kerbe insel uhr", icon: "󱂩", run: () => LayoutService.setMode("notch") },
        { title: "Edit layout", keywords: "widgets pills bar notch editor arrange layout bearbeiten anordnen leiste", icon: Icons.edit, run: () => { PanelService.close(); LayoutService.editMode = true } },
        { title: "Settings", keywords: "settings appearance einstellungen darstellung", icon: Icons.settings, run: () => PanelService.open("settings") },
        { title: "Do Not Disturb: 1 hour", keywords: "dnd focus quiet nicht stören ruhe stunde", icon: Icons.busy, run: () => NotificationService.setDnd("1h") },
        { title: "Do Not Disturb: until tomorrow", keywords: "dnd quiet night nicht stören ruhe nacht morgen", icon: "󰖔", run: () => NotificationService.setDnd("tomorrow") },
        { title: "Do Not Disturb: on", keywords: "dnd quiet nicht stören ruhe", icon: "󰂛", run: () => NotificationService.setDnd("manual") },
        { title: "Do Not Disturb: off", keywords: "dnd nicht stören", icon: "󰂚", run: () => NotificationService.setDnd("off") },
        { title: "Toggle Dark Mode", keywords: "theme dark light dunkelmodus hell dunkel", icon: "󰔎", run: () => SettingsService.set("appearance.theme", SettingsService.theme === "dark" ? "light" : "dark") },
        { title: "Next wallpaper", keywords: "wallpaper next hintergrundbild nächstes", icon: "󰸉", run: () => WallpaperService.next(1) },
        { title: "Profile: Minimal", keywords: "profile layout profil", icon: Icons.edit, run: () => LayoutService.setActiveProfile("minimal") },
        { title: "Profile: Work", keywords: "profile layout profil arbeit", icon: Icons.edit, run: () => LayoutService.setActiveProfile("work") },
        { title: "Profile: Gaming", keywords: "profile layout games profil spiele", icon: "󰊴", run: () => LayoutService.setActiveProfile("gaming") },
        { title: "Profile: Laptop", keywords: "profile layout profil", icon: "󰌢", run: () => LayoutService.setActiveProfile("laptop") },
        { title: "Profile: Docked", keywords: "profile layout monitor display profil", icon: "󰍹", run: () => LayoutService.setActiveProfile("docked") },
        { title: "Animations: Full", keywords: "animation full fast animationen voll schnell", icon: "󰓅", run: () => SettingsService.set("appearance.animationMode", "full") },
        { title: "Animations: Reduced", keywords: "animation reduced motion animationen reduziert", icon: "󰾆", run: () => SettingsService.set("appearance.animationMode", "reduced") },
        { title: "Toggle Night Light", keywords: "night light blue light warm nachtlicht nachtmodus blaulicht", icon: "󰖔", run: () => NightLightService.toggle() },
        { title: "Focus: on", keywords: "focus concentration quiet widgets fokus konzentration ruhe", icon: "󰽥", run: () => AdaptiveService.setFocus(true) },
        { title: "Focus: off", keywords: "focus concentration fokus konzentration", icon: "󰽥", run: () => AdaptiveService.setFocus(false) },
        { title: "Overview", keywords: "overview windows workspaces expose übersicht fenster", icon: Icons.edit, run: () => PanelService.open("overview") },
        { title: "Clipboard", keywords: "clipboard history copy zwischenablage verlauf kopieren", icon: Icons.copy, run: () => PanelService.open("clipboard") },
        { title: "Screenshot: Region", keywords: "screenshot capture region selection bildschirmfoto foto bereich auswahl", icon: "󰩭", run: () => { PanelService.close(); screenshotDelay.mode = "region"; screenshotDelay.restart() } },
        { title: "Screenshot: Screen", keywords: "screenshot capture screen monitor bildschirmfoto foto bildschirm", icon: "󰹑", run: () => { PanelService.close(); screenshotDelay.mode = "screen"; screenshotDelay.restart() } },
        { title: "Record region", keywords: "screen recording record region video capture bildschirmaufnahme aufnahme bereich", icon: "󰑊", run: () => { PanelService.close(); RecordingService.startSoon("region") } },
        { title: "Record screen", keywords: "screen recording record screen monitor video capture bildschirmaufnahme aufnahme bildschirm", icon: "󰑋", run: () => { PanelService.close(); RecordingService.startSoon("screen") } },
        { title: "Stop recording", keywords: "screen recording stop video bildschirmaufnahme aufnahme beenden", icon: "󰓛", run: () => RecordingService.stop() },
        { title: "Lock", keywords: "lock sperren", icon: "󰌾", run: () => SessionService.run("lock") },
        { title: "Fingerprint unlock: Automatic", keywords: "fingerprint unlock lock screen lid dock automatic fingerabdruck entsperren sperrbildschirm deckel automatisch", icon: "󰈷", run: () => FingerprintService.setMode("auto") },
        { title: "Fingerprint unlock: On", keywords: "fingerprint unlock lock screen on fingerabdruck entsperren sperrbildschirm an ein", icon: "󰈷", run: () => FingerprintService.setMode("on") },
        { title: "Fingerprint unlock: Off", keywords: "fingerprint unlock lock screen password off fingerabdruck entsperren sperrbildschirm passwort aus", icon: "󰈷", run: () => FingerprintService.setMode("off") },
        { title: "Stay awake: on", keywords: "caffeine idle awake koffein wach bleiben", icon: "󰅶", run: () => IdleService.stayAwake = true },
        { title: "Stay awake: off", keywords: "caffeine idle awake koffein wach bleiben", icon: "󰾪", run: () => IdleService.stayAwake = false },
        { title: "Sleep", keywords: "suspend sleep bereitschaft", icon: "󰤄", run: () => SessionService.run("suspend") },
        { title: "Log out …", keywords: "logout log out abmelden", icon: "󰍃", run: () => PanelService.open("powerMenu", { confirm: "logout" }) },
        { title: "Restart …", keywords: "reboot restart neustarten neu starten", icon: "󰜉", run: () => PanelService.open("powerMenu", { confirm: "reboot" }) },
        { title: "Shut down …", keywords: "shutdown shut down poweroff ausschalten herunterfahren", icon: "󰐥", run: () => PanelService.open("powerMenu", { confirm: "poweroff" }) }
    ]

    // Derived from the settings navigation, not kept by hand: the copy that
    // used to live here missed the two newest pages, so `@widgets` and
    // `@accounts` found nothing and it still offered a page that had moved.
    readonly property var settingsPages: Nav.PAGES.map(page => ({
        title: page.title, keywords: page.keywords, page: page.id, icon: page.icon
    })).concat([
        // Deep links to a section inside a page, which the page list cannot name.
        { title: "Cursor", keywords: "cursor pointer macos breeze mauszeiger zeiger", page: "appearance", icon: "󰇀" },
        { title: "Panel color & transparency", keywords: "panel background color colour transparency opacity windows control center pills hintergrund farbe transparenz deckkraft", page: "appearance", icon: "󰏘" },
        { title: "Window borders & gaps", keywords: "border gaps window fensterrahmen rahmen abstand fenster", page: "appearance", icon: "󰕮" },
        { title: "Screen recording", keywords: "screen recording video record capture wf-recorder audio frame rate folder bildschirmaufnahme aufnahme", page: "desktop", icon: "󰑊" }
    ])

    // Let the launcher close before the screen is captured.
    Timer {
        id: screenshotDelay
        property string mode: "region"
        interval: 350
        onTriggered: Quickshell.execDetached([Paths.script("screenshot.sh"), mode])
    }

    property var fileResults: []
    property bool fileSearchRunning: false
    property string fileQuery: ""

    function score(text, query) {
        const value = (text || "").toLowerCase()
        if (!query.length) return 1
        if (value === query) return 100
        if (value.startsWith(query)) return 80
        if (value.split(/[\s\-_.]+/).some(word => word.startsWith(query))) return 60
        if (value.includes(query)) return 40
        return 0
    }

    // Launch history (frecency) ranks often and recently used apps higher.
    property var usage: ({})

    // recordUse: false for launches the user did not pick (autostart).
    function launchApp(app, recordUse) {
        const script = appOverrides[app.id]
        if (script) Quickshell.execDetached([Paths.script(script)])
        else app.execute()
        if (recordUse !== false && app.id) {
            usage = Usage.record(usage, app.id, Date.now())
            usageFile.setText(Usage.serialize(usage))
        }
    }

    FileView {
        id: usageFile
        path: Paths.stateDir + "/launcher.json"
        atomicWrites: true
        printErrors: false
        onLoaded: root.usage = Usage.parse(text())
    }

    // App icon image source; missing theme icons fall back to the generic icon
    // without loading a broken image (launcher/IconLogic.js).
    function iconSource(names) {
        return IconLogic.source(names, name => Quickshell.iconPath(name, true))
    }

    function apps(query, category) {
        const q = query.trim().toLowerCase()
        const now = Date.now()
        const filter = categories.find(item => item.name === category)
        return DesktopEntries.applications.values
            .filter(app => app && !app.noDisplay)
            .filter(app => inCategory(app, filter))
            .map(app => ({
                app: app,
                score: Math.max(score(app.name, q) * 1.2, score(app.genericName, q), score((app.keywords || []).join(" "), q) * 0.8)
            }))
            .filter(entry => entry.score > 0)
            .map(entry => Object.assign(entry, { score: entry.score + Usage.boost(root.usage, entry.app.id, now) }))
            .sort((a, b) => b.score - a.score || (a.app.name || "").localeCompare(b.app.name || ""))
            .slice(0, 60)
            .map(entry => ({
                kind: "app", title: entry.app.name || entry.app.id, subtitle: entry.app.genericName || entry.app.comment || "",
                iconSource: root.iconSource(entry.app.icon),
                run: () => root.launchApp(entry.app)
            }))
    }

    function commandResults(query, limit) {
        const q = query.trim().toLowerCase()
        return commands
            .map(command => ({ command: command, score: Math.max(score(command.title, q), score(command.keywords, q) * 0.7) }))
            .filter(entry => entry.score > 0)
            .sort((a, b) => b.score - a.score)
            .slice(0, limit)
            .map(entry => ({ kind: "command", title: entry.command.title, subtitle: "Command", icon: entry.command.icon, run: entry.command.run }))
    }

    function settingsResults(query) {
        const q = query.trim().toLowerCase()
        return settingsPages
            .map(item => ({ item: item, score: Math.max(score(item.title, q), score(item.keywords, q) * 0.7) }))
            .filter(entry => entry.score > 0)
            .sort((a, b) => b.score - a.score)
            .map(entry => ({ kind: "settings", title: entry.item.title, subtitle: "Settings", icon: entry.item.icon,
                             run: () => PanelService.open("settings", { page: entry.item.page }) }))
    }

    // ---- the web ------------------------------------------------------------
    // The address goes to the session's default browser through
    // launch-default.sh, so the launcher opens what the rest of the shell does.
    readonly property string searchEngine: SettingsService.value("launcher.searchEngine")
    readonly property string searchTemplate: SettingsService.value("launcher.searchUrl")
    readonly property string searchLabel: Web.engineLabel(searchEngine, searchTemplate)

    function openUrl(url) {
        if (!url.length) return
        Quickshell.execDetached([Paths.script("launch-default.sh"), "browser", url])
    }

    function webResult(query) {
        const url = Web.searchUrl(query, searchEngine, searchTemplate)
        if (!url.length) return null
        return { kind: "web", title: "Search for “" + query.trim() + "”", subtitle: searchLabel, icon: "󰖟",
                 run: () => root.openUrl(url) }
    }

    function addressResult(query) {
        const url = Web.addressUrl(query)
        if (!url.length) return null
        return { kind: "web", title: "Open " + Web.hostOf(url), subtitle: url, icon: "󰖟",
                 run: () => root.openUrl(url) }
    }

    // Emoji by name, the same list the picker uses. Enter copies, as it does
    // for the calculator: the shell never types into another window.
    function emojiResults(query) {
        return EmojiService.search(query, "").slice(0, 60).map(entry => ({
            kind: "emoji", title: EmojiService.text(entry) + "  " + entry.n,
            subtitle: "Enter copies", icon: "󰞅",
            run: () => EmojiService.pick(entry)
        }))
    }

    function calculatorResult(expression) {
        const result = Calc.evaluate(expression)
        if (!result.ok) return null
        const text = Calc.format(result.value)
        return { kind: "calculator", title: text, subtitle: expression.trim() + " = " + text + " · Enter copies", icon: "󰃬",
                 run: () => { Quickshell.clipboardText = text } }
    }

    function modeFor(text) {
        const first = text.charAt(0)
        return modes.find(mode => mode.prefix.length && mode.prefix === first) || modes[0]
    }

    function results(text, category) {
        const mode = modeFor(text)
        const query = mode.prefix.length ? text.slice(1) : text
        if (mode.id === "commands") return commandResults(query, 50)
        if (mode.id === "settings") return settingsResults(query)
        if (mode.id === "calculator") {
            const calc = calculatorResult(query)
            return calc ? [calc] : []
        }
        if (mode.id === "emoji") return emojiResults(query)
        if (mode.id === "web") {
            const list = []
            const address = addressResult(query)
            if (address) list.push(address)
            const search = webResult(query)
            if (search) list.push(search)
            return list
        }
        if (mode.id === "files") {
            requestFiles(query)
            return fileResults
        }
        const list = []
        if (Calc.looksLikeMath(query)) {
            const calc = calculatorResult(query)
            if (calc) list.push(calc)
        }
        // A typed address is offered before anything else: nothing else can be
        // meant by "example.org/page".
        const address = addressResult(query)
        if (address) list.push(address)
        const appList = apps(query, category)
        const commandList = query.trim().length >= 2 ? commandResults(query, 3) : []
        return list.concat(appList.slice(0, 1), commandList, appList.slice(1))
    }

    // ---- files -------------------------------------------------------------
    function requestFiles(query) {
        const trimmed = query.trim()
        if (trimmed === fileQuery) return
        fileQuery = trimmed
        if (trimmed.length < 2) { fileResults = []; fileProc.running = false; return }
        fileDebounce.restart()
    }

    Timer {
        id: fileDebounce
        interval: 250
        onTriggered: {
            fileProc.running = false
            fileProc.command = ["plocate", "-i", "-l", "200", "--", root.fileQuery]
            root.fileSearchRunning = true
            fileProc.running = true
        }
    }

    Process {
        id: fileProc
        stderr: ErrorLog { label: "LauncherService.fileProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                const home = Paths.home + "/"
                root.fileResults = text.split("\n")
                    .filter(path => path.startsWith(home) && !path.slice(home.length).split("/").some(part => part.startsWith(".")))
                    .slice(0, 50)
                    .map(path => ({
                        kind: "file", title: path.split("/").pop(), subtitle: "~/" + path.slice(home.length),
                        icon: /\.(png|jpe?g|webp|svg|gif)$/i.test(path) ? "󰋩" : /\.pdf$/i.test(path) ? "󰈦" : "󰈔",
                        run: () => Quickshell.execDetached(["xdg-open", path]),
                        alternate: () => Quickshell.execDetached(["xdg-open", path.slice(0, path.lastIndexOf("/"))])
                    }))
                root.fileSearchRunning = false
            }
        }
        onExited: root.fileSearchRunning = false
    }
}
