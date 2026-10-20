pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.theme
import "launcher/Calculator.js" as Calc
import "launcher/Usage.js" as Usage
import "launcher/IconLogic.js" as IconLogic
import "launcher/WebSearch.js" as Web
import "launcher/ModeOrder.js" as ModeOrder
import "launcher/Pinned.js" as Pinned
import "launcher/LaunchLogic.js" as Launch
import "launcher/WindowClassLogic.js" as WindowClass
import "launcher/FileSearch.js" as FileSearch
import "launcher/ResultsLogic.js" as Results
import "launcher/ConvertLogic.js" as Convert
import "launcher/WindowResults.js" as Windows
import "launcher/RecentFiles.js" as Recent
import "launcher/CodeFolders.js" as Code
import "launcher/RunCommand.js" as Run
import "settings/SettingsNavLogic.js" as Nav

// Launcher providers. Prefixes: none = apps (+ calculator, conversions,
// commands, open windows, VS Code's folders, recent files and, for something
// that looks like an address, "Open"), ">" commands, "/" files (plocate),
// "@" settings, "=" calculator, "?" web search, ":" emoji, "$" a command to
// run.
Singleton {
    id: root

    // The file mode disappears with its setting rather than staying and
    // finding nothing: an option that changes nothing is worse than no option.
    readonly property bool fileSearch: SettingsService.value("launcher.fileSearch")
    // The order they are declared in, before the user's own is applied.
    readonly property var allModes: [
        { id: "apps", prefix: "", label: "Apps", icon: Icons.apps },
        { id: "commands", prefix: ">", label: "Commands", icon: "󰘳" },
        { id: "settings", prefix: "@", label: "Settings", icon: Icons.settings },
        { id: "calculator", prefix: "=", label: "Calculator", icon: "󰃬" },
        { id: "web", prefix: "?", label: "Web", icon: "󰖟" },
        { id: "emoji", prefix: ":", label: "Emoji", icon: "󰞅" }
    ].concat(fileSearch ? [{ id: "files", prefix: "/", label: "Files", icon: Icons.folder }] : [])
    // What the switch shows, in the order Settings > Launcher put them. The
    // rules a stored order has to survive are in ModeOrder, with their test.
    readonly property var modes: ModeOrder.apply(SettingsService.value("launcher.modeOrder"), allModes)
    // "$ command" is a prefix, not one of the switch's modes: a mode there is
    // a segment more in everyone's switch and a row in Settings > Launcher's
    // order, for something typed rather than browsed. The field still says
    // what it does (its glyph and "Run …") while the prefix is there.
    readonly property var runMode: ({ id: "run", prefix: Run.PREFIX, label: "Run", icon: "󰆍" })
    // Where the categories are is a layout question now, not a setting: the
    // block sits in the sidebar, or in the column as a row of chips, or
    // nowhere. `Launcher.qml` reads the zone; nothing outside it needs to.


    // ---- pinned apps -------------------------------------------------------
    // The one fixed thing in front of a search field that earns its place: what
    // you want before you type. See services/launcher/Pinned.js.
    readonly property string pinnedStored: SettingsService.value("launcher.pinned")
    readonly property bool showPinned: SettingsService.value("launcher.showPinned")
    readonly property var pinnedApps: Pinned.apps(pinnedStored, entries)
    readonly property bool pinnedFull: Pinned.full(pinnedStored)
    readonly property int pinLimit: Pinned.LIMIT
    function isPinned(id) { return Pinned.has(pinnedStored, id) }
    // True when pinning `id` would be refused for the limit (Pinned.refused).
    function pinRefused(id) { return Pinned.refused(pinnedStored, id) }
    function togglePin(id) { return SettingsService.set("launcher.pinned", Pinned.toggle(pinnedStored, id)) }
    function movePinned(id, delta) { return SettingsService.set("launcher.pinned", Pinned.move(pinnedStored, id, delta)) }

    readonly property var categories: [
        { name: "All", icon: Icons.apps, keys: [] },
        { name: "Internet", icon: "󰖟", keys: ["Network", "WebBrowser", "Email", "InstantMessaging"] },
        { name: "Office", icon: "󰈙", keys: ["Office", "Calendar", "ContactManagement"] },
        { name: "Graphics", icon: "󰋩", keys: ["Graphics", "2DGraphics", "3DGraphics", "Photography"] },
        { name: "Multimedia", icon: "󰝚", keys: ["AudioVideo", "Audio", "Video", "Player"] },
        { name: "Development", icon: "󰅩", keys: ["Development", "IDE"] },
        { name: "System", icon: Icons.settings, keys: ["System", "Settings", "Security", "Monitor"] },
        { name: "Utilities", icon: "󰦪", keys: ["Utility", "TextEditor", "TerminalEmulator", "FileManager"] },
        { name: "Games", icon: "󰊴", keys: ["Game"] }
    ]
    // ---- the desktop entries ---------------------------------------------
    // DesktopEntries fills its list one entry at a time once the shell is up
    // - 69 `valuesChanged` within 4 ms at a start here, one per entry - and
    // does it again for every app installed or removed. Every binding over
    // `values` ran once per entry, with the launcher closed: the categories
    // and their counts 70 times at every login. These
    // bindings read a copy taken once a scan has settled instead, and
    // `entriesRevision` counts the copies for anyone who looks entries up by
    // id (ShortcutService), which no binding would follow by itself.
    property var entries: []
    property int entriesRevision: 0
    function takeEntries() {
        const values = DesktopEntries.applications.values
        const list = []
        for (let index = 0; index < values.length; ++index) if (values[index]) list.push(values[index])
        entries = list
        entriesRevision += 1
        queueIcons()
    }
    Component.onCompleted: takeEntries()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { entriesSettle.restart() }
    }
    Timer { id: entriesSettle; interval: 50; onTriggered: root.takeEntries() }

    // What counts as an app: every entry that does not ask to be left out of
    // menus. The launcher's results and categories and the start menu's lists
    // all start here. Read it under a panel's `shown`.
    function visibleApps() {
        // `app.id` too: an entry removed by a scan is gone before the copy
        // is retaken, and what is left of it has no id.
        return entries.filter(app => app && app.id && !app.noDisplay)
    }

    // Categories that contain at least one visible app, with their app count.
    readonly property var availableCategories: {
        const visible = visibleApps()
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
        "google-chrome": "launch-chrome.sh",
        "com.google.Chrome": "launch-chrome.sh",
        "chromium-browser": "launch-chromium-browser.sh",
        "chromium": "launch-chromium-browser.sh",
        "Alacritty": "launch-alacritty.sh",
        "kitty": "launch-kitty.sh"
    })

    // Sentence case, and what follows a colon is a value, so it starts small
    // too: "Timer: stop", "Screenshot: region". Half of them had said
    // "Screenshot: Region" and "Toggle Dark Mode" beside "Focus: on". Names
    // keep their capitals: Do Not Disturb and Night Light, as every panel
    // writes them, and a notch preset's own label.
    readonly property var commands: [
        { title: "Control center", keywords: "control center audio wifi bluetooth kontrollzentrum wlan", icon: Icons.settings, run: () => PanelService.open("controlCenter") },
        { title: "Notifications", keywords: "notifications history benachrichtigungen verlauf", icon: "󰂚", run: () => PanelService.open("notifications") },
        { title: "Dashboard", keywords: "calendar clock weather time kalender uhr wetter", icon: "󰃭", run: () => PanelService.open("dashboard") },
        { title: "Refresh weather", keywords: "weather refresh open-meteo wetter aktualisieren", icon: "󰖐", run: () => { WeatherService.refresh(); PanelService.open("dashboard") } },
        { title: "Open calendar in Merkuro", keywords: "calendar events google akonadi kalender termine", icon: "󰸗", run: () => CalendarService.openManager() },
        { title: "Desktop mode: widgets", keywords: "mode widgets desktop modus", icon: Icons.arrange, run: () => LayoutService.setDesktopMode("widgets") },
        { title: "Desktop mode: bar", keywords: "mode bar pills top panel modus leiste oben", icon: "󰘔", run: () => LayoutService.setDesktopMode("pills") },
        { title: "Desktop mode: notch", keywords: "mode notch island dynamic time modus kerbe insel uhr", icon: "󱂩", run: () => LayoutService.setDesktopMode("notch") },
        { title: "Notch: Island", keywords: "notch preset island pills workspaces status kerbe insel vorlage arbeitsflächen", icon: "󱂩", preset: "island", run: () => LayoutService.applyNotchPreset("island") },
        { title: "Notch: Classic", keywords: "notch preset classic time clock only kerbe klassisch vorlage uhr zeit", icon: "󱂩", preset: "classic", run: () => LayoutService.applyNotchPreset("classic") },
        { title: "Edit layout", keywords: "widgets pills bar notch editor arrange layout bearbeiten anordnen leiste", icon: Icons.arrange, run: () => { PanelService.close(); LayoutService.editMode = true } },
        { title: "Settings", keywords: "settings appearance einstellungen darstellung", icon: Icons.settings, run: () => PanelService.open("settings") },
        { title: "Timer: 5 minutes", keywords: "timer countdown 5 minutes wecker uhr minuten", icon: "󰔛", run: () => TimerService.start(300) },
        { title: "Timer: 10 minutes", keywords: "timer countdown 10 minutes wecker uhr minuten", icon: "󰔛", run: () => TimerService.start(600) },
        { title: "Timer: 25 minutes", keywords: "timer countdown 25 minutes pomodoro focus wecker minuten", icon: "󰔛", run: () => TimerService.start(1500) },
        { title: "Timer: stop", keywords: "timer countdown stop cancel wecker abbrechen", icon: "󰔞", run: () => TimerService.stopTimer() },
        { title: "Do Not Disturb: 1 hour", keywords: "dnd focus quiet nicht stören ruhe stunde", icon: Icons.busy, run: () => NotificationService.setDnd("1h") },
        { title: "Do Not Disturb: until tomorrow", keywords: "dnd quiet night nicht stören ruhe nacht morgen", icon: Icons.untilMorning, run: () => NotificationService.setDnd("tomorrow") },
        { title: "Do Not Disturb: on", keywords: "dnd quiet nicht stören ruhe", icon: "󰂛", run: () => NotificationService.setDnd("manual") },
        { title: "Do Not Disturb: off", keywords: "dnd nicht stören", icon: "󰂚", run: () => NotificationService.setDnd("off") },
        { title: "Toggle dark mode", keywords: "theme dark light dunkelmodus hell dunkel", icon: "󰔎", run: () => SettingsService.set("appearance.theme", SettingsService.theme === "dark" ? "light" : "dark") },
        { title: "Next wallpaper", keywords: "wallpaper next hintergrundbild nächstes", icon: "󰸉", run: () => WallpaperService.next(1) },
        // The five modes, not profiles: these called setActiveProfile with a
        // mode's name and did nothing (15.10.).
        { title: "Mode: minimal", keywords: "mode modus profile layout profil", icon: Icons.arrange, run: () => LayoutService.setActiveMode("minimal") },
        { title: "Mode: work", keywords: "mode modus profile layout profil arbeit", icon: Icons.arrange, run: () => LayoutService.setActiveMode("work") },
        { title: "Mode: gaming", keywords: "mode modus profile layout games profil spiele", icon: "󰊴", run: () => LayoutService.setActiveMode("gaming") },
        { title: "Mode: laptop", keywords: "mode modus profile layout profil", icon: "󰌢", run: () => LayoutService.setActiveMode("laptop") },
        { title: "Mode: desk", keywords: "mode modus profile layout monitor display profil docked dock schreibtisch", icon: "󰍹", run: () => LayoutService.setActiveMode("docked") },
        // The display switcher (Super+Shift+P) and its choices, for a projector
        // or a meeting room's screen. Applied after the launcher has closed: a
        // choice can take its screen away. One that cannot be made does nothing.
        { title: "Display switcher", keywords: "display monitor projector beamer duplicate mirror extend presentation bildschirm spiegeln erweitern präsentation", icon: "\u{f0379}", run: () => PanelService.open("displaySwitcher") },
        { title: "Displays: duplicate", keywords: "display monitor projector beamer duplicate mirror same presentation bildschirm spiegeln duplizieren präsentation", icon: "\u{f0191}", run: () => { PanelService.close(); Qt.callLater(() => DisplayService.setProjection("duplicate")) } },
        { title: "Displays: extend", keywords: "display monitor projector beamer extend side by side bildschirm erweitern", icon: "\u{f037a}", run: () => { PanelService.close(); Qt.callLater(() => DisplayService.setProjection("extend")) } },
        { title: "Displays: laptop only", keywords: "display monitor laptop only internal screen bildschirm nur laptop", icon: "\u{f0322}", run: () => { PanelService.close(); Qt.callLater(() => DisplayService.setProjection("internal")) } },
        { title: "Displays: external only", keywords: "display monitor projector beamer external only second screen bildschirm nur extern", icon: "\u{f0379}", run: () => { PanelService.close(); Qt.callLater(() => DisplayService.setProjection("external")) } },
        { title: "Animations: full", keywords: "animation full fast animationen voll schnell", icon: "󰓅", run: () => SettingsService.set("appearance.animationMode", "full") },
        { title: "Animations: reduced", keywords: "animation reduced motion animationen reduziert", icon: "󰾆", run: () => SettingsService.set("appearance.animationMode", "reduced") },
        { title: "Toggle Night Light", keywords: "night light blue light warm nachtlicht nachtmodus blaulicht", icon: Icons.nightLight, run: () => NightLightService.toggle() },
        { title: "Focus: on", keywords: "focus concentration quiet widgets fokus konzentration ruhe", icon: Icons.focus, run: () => AdaptiveService.setFocus(true) },
        { title: "Focus: off", keywords: "focus concentration fokus konzentration", icon: Icons.focus, run: () => AdaptiveService.setFocus(false) },
        // Focus with an end: off again after 25 minutes, with a ring.
        { title: "Focus: 25 minutes", keywords: "focus session pomodoro 25 minutes timer concentration quiet fokus sitzung konzentration ruhe minuten", icon: Icons.focus, run: () => AdaptiveService.focusFor(1500) },
        { title: "Overview", keywords: "overview windows workspaces expose übersicht fenster", icon: Icons.arrange, run: () => PanelService.open("overview") },
        // Settings > Apps: with nothing set, each opens that page instead.
        { title: "Start my work apps", keywords: "work apps start morning together arbeit apps starten morgens", icon: Icons.play, run: () => SessionAppsService.startWork() },
        { title: "Reopen the last session's apps", keywords: "reopen restore session last apps login wiederherstellen wieder öffnen sitzung letzte", icon: Icons.window, run: () => SessionAppsService.reopen() },
        { title: "Clipboard", keywords: "clipboard history copy zwischenablage verlauf kopieren", icon: Icons.copy, run: () => PanelService.open("clipboard") },
        // A model on this computer, through Ollama (shell/assistant).
        { title: "Assistant", keywords: "assistant ai chat ask question ollama local model llm assistent ki frage fragen", icon: Icons.assistant, run: () => PanelService.open("assistant") },
        // A click on a window takes that window, a drag a region
        // (scripts/screenshot.sh hands slurp the windows on screen).
        { title: "Screenshot: region", keywords: "screenshot capture region selection window click bildschirmfoto foto bereich auswahl fenster klick", icon: "󰩭", run: () => root.screenshot(["region"]) },
        { title: "Screenshot: screen", keywords: "screenshot capture screen monitor bildschirmfoto foto bildschirm", icon: "󰹑", run: () => root.screenshot(["screen"]) },
        // For a menu or a tooltip, which a selection overlay would close:
        // three seconds to open it, then the screen.
        { title: "Screenshot: screen in 3 seconds", keywords: "screenshot capture screen delay timer later menu tooltip bildschirmfoto verzögert später sekunden", icon: "󰃩", run: () => root.screenshot(["--delay", "3", "screen"]) },
        // Text out of a picture of it: a Citrix session, a scanned page, a
        // dialog that will not let its text be selected (tesseract).
        { title: "Copy text from the screen", keywords: "ocr text recognition copy screen region tesseract texterkennung text kopieren bildschirm bereich", icon: "󱄽", run: () => root.screenshot(["text"]) },
        { title: "Record region", keywords: "screen recording record region video capture bildschirmaufnahme aufnahme bereich", icon: "󰑊", run: () => { PanelService.close(); RecordingService.startSoon("region") } },
        { title: "Record screen", keywords: "screen recording record screen monitor video capture bildschirmaufnahme aufnahme bildschirm", icon: "󰑋", run: () => { PanelService.close(); RecordingService.startSoon("screen") } },
        { title: "Stop recording", keywords: "screen recording stop video bildschirmaufnahme aufnahme beenden", icon: Icons.stop, run: () => RecordingService.stop() },
        // The screen zoom and the color filters (ScreenEffectsService), keep
        // on top, the drop-down terminal, the keyboard passthrough and the
        // Citrix session over the desk's screens (HyprlandService).
        { title: "Zoom in", keywords: "zoom magnifier magnify bigger larger lupe vergrößern größer", icon: "󰍋", run: () => ScreenEffectsService.zoomBy(1) },
        { title: "Zoom out", keywords: "zoom magnifier smaller lupe verkleinern kleiner", icon: "󰍊", run: () => ScreenEffectsService.zoomBy(-1) },
        { title: "Zoom: off", keywords: "zoom magnifier reset 100 lupe zurücksetzen aus", icon: "󰍊", run: () => ScreenEffectsService.resetZoom() },
        { title: "Color filter: on", keywords: "color filter colour grayscale colorblind farbfilter graustufen farbenblind an", icon: "󰌁", run: () => ScreenEffectsService.setFilterOn(true) },
        { title: "Color filter: off", keywords: "color filter colour grayscale colorblind farbfilter graustufen farbenblind aus", icon: "󰌁", run: () => ScreenEffectsService.setFilterOn(false) },
        { title: "Color filter: grayscale", keywords: "color filter colour grayscale greyscale black white focus farbfilter graustufen schwarz weiß", icon: "󰌁", run: () => ScreenEffectsService.setFilter("grayscale") },
        { title: "Color filter: red-green", keywords: "color filter colorblind deuteranopia protanopia red green farbfilter farbenblind rot grün", icon: "󰌁", run: () => ScreenEffectsService.setFilter("deuteranopia") },
        { title: "Color filter: blue-yellow", keywords: "color filter colorblind tritanopia blue yellow farbfilter farbenblind blau gelb", icon: "󰌁", run: () => ScreenEffectsService.setFilter("tritanopia") },
        { title: "Color filter: inverted", keywords: "color filter invert inverted negative farbfilter invertiert umkehren", icon: "󰌁", run: () => ScreenEffectsService.setFilter("invert") },
        { title: "Keep window on top", keywords: "keep on top always above pin float window immer im vordergrund anheften fenster", icon: Icons.keepOnTop, run: () => { PanelService.close(); HyprlandService.keepOnTop("") } },
        { title: "Drop-down terminal", keywords: "terminal dropdown drop down quake yakuake guake scratchpad alacritty konsole", icon: "󰆍", run: () => { PanelService.close(); HyprlandService.toggleDropdown() } },
        { title: "Keys to the window", keywords: "keyboard passthrough citrix remote desktop vm virtual machine windows key tastatur durchreichen fernzugriff", icon: "󰌌", run: () => { PanelService.close(); HyprlandService.setPassthrough(true) } },
        { title: "Citrix over the screens", keywords: "citrix span spread multi monitor screens desktop viewer both bildschirme beide verteilen", icon: "󰍺", run: () => { PanelService.close(); HyprlandService.spanCitrix() } },
        { title: "Citrix back into the layout", keywords: "citrix unspan tile back layout zurück", icon: "󰍺", run: () => HyprlandService.unspanCitrix() },
        { title: "Lock", keywords: "lock sperren", icon: Icons.lock, run: () => SessionService.run("lock") },
        { title: "Fingerprint unlock: automatic", keywords: "fingerprint unlock lock screen lid dock automatic fingerabdruck entsperren sperrbildschirm deckel automatisch", icon: "󰈷", run: () => FingerprintService.setMode("auto") },
        { title: "Fingerprint unlock: on", keywords: "fingerprint unlock lock screen on fingerabdruck entsperren sperrbildschirm an ein", icon: "󰈷", run: () => FingerprintService.setMode("on") },
        { title: "Fingerprint unlock: off", keywords: "fingerprint unlock lock screen password off fingerabdruck entsperren sperrbildschirm passwort aus", icon: "󰈷", run: () => FingerprintService.setMode("off") },
        { title: "Stay awake: on", keywords: "caffeine idle awake koffein wach bleiben", icon: "󰅶", run: () => IdleService.stayAwake = true },
        { title: "Stay awake for 1 hour", keywords: "caffeine idle awake hour koffein wach bleiben stunde", icon: "󰅶", run: () => IdleService.holdAwake("1h") },
        { title: "Stay awake: off", keywords: "caffeine idle awake koffein wach bleiben", icon: "󰾪", run: () => IdleService.stayAwake = false },
        { title: "Sleep", keywords: "suspend sleep bereitschaft", icon: Icons.suspend, run: () => SessionService.run("suspend") },
        { title: "Log out …", keywords: "logout log out abmelden", icon: Icons.logout, run: () => PanelService.open("powerMenu", { confirm: "logout" }) },
        { title: "Restart …", keywords: "reboot restart neustarten neu starten", icon: Icons.reboot, run: () => PanelService.open("powerMenu", { confirm: "reboot" }) },
        { title: "Shut down …", keywords: "shutdown shut down poweroff ausschalten herunterfahren", icon: Icons.poweroff, run: () => PanelService.open("powerMenu", { confirm: "poweroff" }) }
    // A notch preset is a command only once its file has read (LayoutService
    // loads the built-in ones asynchronously); before that, or with the file
    // missing, it would be a command that does nothing.
    ].filter(command => !command.preset || LayoutService.notchPreset(command.preset) !== null)

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
    function screenshot(args) {
        PanelService.close()
        screenshotDelay.args = args
        screenshotDelay.restart()
    }
    Timer {
        id: screenshotDelay
        property var args: ["region"]
        interval: 350
        onTriggered: Quickshell.execDetached([Paths.script("screenshot.sh")].concat(args))
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
        // In a unit of its own, named after the entry (scripts/launch-app.sh):
        // the portals know the application by that name, Plasma starts it the
        // same way, and the Secret portal keys on it - and with the session's
        // environment, not the shell's own settings (launcher/LaunchLogic.js).
        // A Terminal=true entry opens in the session's terminal
        // (scripts/launch-terminal.sh). Only an entry without a parsed
        // command keeps Quickshell's launch.
        const context = Launch.launchContext(app, appOverrides, name => Paths.script(name))
        if (context) Quickshell.execDetached(context)
        else app.execute()
        if (recordUse !== false && app.id) {
            usage = Usage.record(usage, app.id, Date.now())
            usageFile.setText(Usage.serialize(usage))
        }
    }

    // One of an entry's desktop actions (New Window, a web app's "New
    // message" …), started the way the entry is (LaunchLogic.actionContext).
    function launchAction(app, action) {
        const context = Launch.actionContext(app, action, appOverrides, name => Paths.script(name))
        if (context) Quickshell.execDetached(context)
        else if (action && typeof action.execute === "function") action.execute()
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

    // ---- icon names, looked up ahead ----------------------------------------
    // The first lookup of an icon name walks the icon theme's folders on disk,
    // 8 ms for most names here and up to 19 (~70 apps: 0.33 s); after that Qt
    // answers from its own cache (0.4 ms for sixty). Little else asks for most
    // app icons before the launcher does, so the first open after a start
    // resolved its sixty rows in one go and came up ~0.3 s late. The rows ask
    // for their own icons now (only the rows a list draws), and a while after
    // the entries have settled the names nobody asked yet are looked up one
    // per tick, never while a panel is open, so each lookup lands where
    // nobody waits for a frame. The start menu, the dock, the switcher and
    // Settings read the same cache.
    property var iconsAsked: ({})
    property var iconQueue: []
    function queueIcons() {
        const names = IconLogic.pending(visibleApps().map(app => app.icon), iconsAsked)
        if (!names.length) return
        iconQueue = names
        if (!iconWarm.running && !iconWarmDelay.running) iconWarmDelay.start()
    }
    // After the login's own work: the panels, the wallpaper, the first frames.
    Timer { id: iconWarmDelay; interval: 20000; onTriggered: iconWarm.start() }
    Timer {
        id: iconWarm
        interval: 250
        repeat: true
        onTriggered: {
            if (PanelService.active.length) return
            if (!root.iconQueue.length) { stop(); return }
            const name = root.iconQueue[0]
            root.iconQueue = root.iconQueue.slice(1)
            // A plain object no binding reads: the queue's own bookkeeping.
            root.iconsAsked[name] = true
            root.iconSource(name)
        }
    }

    function apps(query, category) {
        const q = query.trim().toLowerCase()
        const now = Date.now()
        const filter = categories.find(item => item.name === category)
        return visibleApps()
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
                // Looked up when a row reads it, not here: the launcher draws
                // a handful of the sixty, and a theme lookup is milliseconds
                // the first time (see `queueIcons`).
                get iconSource() { return root.iconSource(entry.app.icon) },
                // The id so a row can be pinned; everything else about a result
                // is what it shows, and this is the one thing about what it is.
                appId: entry.app.id,
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
            .map(entry => ({ kind: "command", key: "command:" + entry.command.title, title: entry.command.title,
                             subtitle: "Command", icon: entry.command.icon, run: entry.command.run }))
    }

    function settingsResults(query) {
        const q = query.trim().toLowerCase()
        return settingsPages
            .map(item => ({ item: item, score: Math.max(score(item.title, q), score(item.keywords, q) * 0.7) }))
            .filter(entry => entry.score > 0)
            .sort((a, b) => b.score - a.score)
            .map(entry => ({ kind: "settings", key: "settings:" + entry.item.page + ":" + entry.item.title,
                             title: entry.item.title, subtitle: "Settings", icon: entry.item.icon,
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
        return { kind: "web", key: "web:search", title: "Search for “" + query.trim() + "”", subtitle: searchLabel, icon: "󰖟",
                 run: () => root.openUrl(url) }
    }

    function addressResult(query) {
        const url = Web.addressUrl(query)
        if (!url.length) return null
        return { kind: "web", key: "web:open", title: "Open " + Web.hostOf(url), subtitle: url, icon: "󰖟",
                 run: () => root.openUrl(url) }
    }

    // Emoji by name, the same list the picker uses. Enter copies, as it does
    // for the calculator: the shell never types into another window.
    function emojiResults(query) {
        return EmojiService.search(query, "").slice(0, 60).map(entry => ({
            kind: "emoji", key: "emoji:" + entry.e, title: EmojiService.text(entry) + "  " + entry.n,
            subtitle: "Enter copies", icon: "󰞅",
            run: () => EmojiService.pick(entry)
        }))
    }

    function calculatorResult(expression) {
        const result = Calc.evaluate(expression)
        if (!result.ok) return null
        const text = Calc.format(result.value)
        return { kind: "calculator", key: "calculator", title: text, subtitle: expression.trim() + " = " + text + " · Enter copies", icon: "󰃬",
                 run: () => { Quickshell.clipboardText = text } }
    }

    function modeFor(text) {
        const first = text.charAt(0)
        // "$100 to eur" is a conversion with the dollar in front, not a
        // command: the prefix runs whatever else follows it.
        if (first === Run.PREFIX && !Convert.parse(text)) return runMode
        return modes.find(mode => mode.prefix.length && mode.prefix === first) || modes[0]
    }

    function results(text, category) {
        const mode = modeFor(text)
        const query = mode.prefix.length ? text.slice(1) : text
        if (mode.id === "run") {
            const run = runResult(text)
            return run ? [run] : []
        }
        if (mode.id === "commands") return commandResults(query, 50)
        if (mode.id === "settings") return settingsResults(query)
        if (mode.id === "calculator") {
            // "= 10 km to mi" is a conversion; anything else the calculator's.
            if (Convert.parse(query)) {
                const converted = conversionResult(query)
                return converted ? [converted] : []
            }
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
        const lead = []
        if (Calc.looksLikeMath(query)) {
            const calc = calculatorResult(query)
            if (calc) lead.push(calc)
        }
        const converted = conversionResult(query)
        if (converted) lead.push(converted)
        // A typed address: first when it is one beyond doubt
        // ("example.org/page", "https://…"), after the best app when it is a
        // bare host, which "readme.md" is too (ResultsLogic.appsMode).
        const address = addressResult(query)
        const appList = apps(query, category)
        const typed = query.trim().length >= 2
        const commandList = typed ? commandResults(query, 3) : []
        // The other sources only once something is typed: with an empty
        // field the list is every app, and a window or a file among them
        // would be noise. Each brings its few best rows.
        const extras = typed && category === "All"
            ? windowResults(query).concat(codeResults(query), recentResults(query)) : []
        return Results.appsMode(lead, address, Web.addressLeads(query), appList, commandList, extras)
    }

    // ---- "$ command" -------------------------------------------------------
    // One row for the line typed after "$": Enter runs it, Ctrl+Enter runs it
    // in the session's terminal, which stays open for the output
    // (launcher/RunCommand.js has how, and why a browser goes the long way).
    function runResult(text) {
        const command = Run.parse(text)
        if (!command.length) return null
        return { kind: "run", key: "run", title: "Run " + command, subtitle: "Enter runs it · Ctrl+Enter in a terminal",
                 icon: runMode.icon,
                 run: () => root.runCommand(command, false),
                 alternate: () => root.runCommand(command, true) }
    }

    // Ctrl+Enter keeps the terminal for the output (RunCommand.context).
    function runCommand(command, inTerminal) {
        const terminal = inTerminal || Run.needsTerminal(command, entries)
        const context = Run.context(command, name => Paths.script(name), terminal, inTerminal)
        if (!context) return
        context.workingDirectory = Paths.home
        Quickshell.execDetached(context)
    }

    // ---- open windows ------------------------------------------------------
    // From Quickshell's list of the compositor's windows, which the shell
    // keeps anyway: no process, nothing asked. Read only from `results`, so
    // only while the launcher shows something typed.
    readonly property bool windowSearch: SettingsService.value("launcher.windows") !== false

    function appEntry(appId) {
        return entryForClass(appId)
    }

    // The desktop entry a window's class stands for: a known alias first
    // (WindowClassLogic - Citrix Workspace's window says "selfservice"), then
    // Quickshell's heuristic lookup and the id itself. The dock, the overview,
    // Alt+Tab, the window title widget and the session's apps ask here, so a
    // window has the same app, and the same icon, everywhere.
    function entryForClass(cls) {
        const name = String(cls || "")
        if (!name.length) return null
        const alias = WindowClass.aliasFor(name)
        const aliased = alias.length ? DesktopEntries.byId(alias) : null
        return aliased || DesktopEntries.heuristicLookup(name) || DesktopEntries.byId(name)
            || DesktopEntries.byId(name.toLowerCase()) || null
    }

    function windowResults(query) {
        if (!windowSearch) return []
        const names = {}
        const appName = appId => {
            if (names[appId] === undefined) {
                const entry = appEntry(appId)
                names[appId] = entry && entry.name ? entry.name : appId
            }
            return names[appId]
        }
        // The blocks' order only with a window to name: a search with none
        // open makes no compositor service (a unit test's would start
        // HyprCompat's probes against no compositor).
        const toplevels = Hyprland.toplevels.values
        return Windows.matches(Windows.entries(toplevels, toplevels.length ? HyprlandService.blockOrder : []), query, score, appName).map(window => ({
            kind: "window", key: "window:" + window.address, title: window.title || appName(window.appId),
            subtitle: Windows.subtitle(window, appName), icon: Icons.window,
            get iconSource() {
                const entry = root.appEntry(window.appId)
                return root.iconSource([entry ? entry.icon : "", window.appId])
            },
            run: () => root.focusWindowSoon(window.address)
        }))
    }

    // After the launcher has let go of the keyboard, or Hyprland hands the
    // focus back to the window it had (SwitcherService waits the same way).
    function focusWindowSoon(address) {
        focusTimer.address = address
        focusTimer.restart()
    }
    Timer {
        id: focusTimer
        property string address: ""
        interval: 120
        onTriggered: {
            try {
                HyprCompat.dispatch(HyprCompat.commands.focusWindow(address))
            } catch (error) {
                console.warn("buchhwin-shell: LauncherService: no window to focus")
            }
        }
    }

    // ---- recent files ------------------------------------------------------
    // The list GTK and KDE applications keep of what they opened, read when a
    // query first asks for it in an open (one file, a few KB to a few
    // hundred) and let go when the launcher closes: nothing watched, nothing
    // kept while it is shut. A path set anew each time is a fresh read
    // (pitfall 91), where a reload() of a FileView that read once may hand
    // back the old text.
    readonly property bool recentSearch: SettingsService.value("launcher.recentFiles") !== false
    readonly property string recentFile: (Quickshell.env("XDG_DATA_HOME") || Paths.home + "/.local/share") + "/recently-used.xbel"
    property string recentPath: ""
    property var recentList: []

    function recentResults(query) {
        if (!recentSearch) return []
        // Scheduled, never written here: `results` is a binding (pitfall 34).
        Qt.callLater(root.loadRecent)
        return Recent.matches(recentList, query, score).map(file => ({
            kind: "file", key: "recent:" + file.path, title: file.name,
            subtitle: (file.kind === "folder" ? "Recent folder · " : "Recent file · ") + file.folder,
            icon: file.kind === "folder" ? Icons.folder : file.kind === "image" ? "󰋩" : file.kind === "pdf" ? "󰈦" : "󰈔",
            run: () => Quickshell.execDetached(["xdg-open", file.path]),
            alternate: () => Quickshell.execDetached(["xdg-open", file.path.slice(0, file.path.lastIndexOf("/")) || "/"])
        }))
    }

    function loadRecent() {
        if (recentPath.length || !recentSearch) return
        recentPath = recentFile
        holdBriefly()
    }

    FileView {
        id: recentView
        path: root.recentPath
        printErrors: false
        onLoaded: root.recentList = Recent.parse(text(), Paths.home)
        onLoadFailed: root.recentList = []
    }

    // ---- VS Code's folders ---------------------------------------------------
    // "Open in VS Code" for the folders it opened last and those under ~/git,
    // read by scripts/launcher-code-folders.py once per open (~20 ms), only
    // when VS Code (or Codium) is installed and a query asks.
    readonly property bool codeSearch: SettingsService.value("launcher.codeFolders") !== false
    property var codeFound: null
    property bool codeAsked: false

    function codeResults(query) {
        if (!codeSearch) return []
        const editor = Code.editorEntry(visibleApps())
        if (!editor) return []
        Qt.callLater(root.loadCode)
        if (!codeFound) return []
        const list = Code.folders(codeFound, editor.editor, Paths.home)
        return Code.matches(list, query, score).map(folder => ({
            kind: "folder", key: "code:" + folder.path, title: folder.name,
            subtitle: "Open in " + (editor.app.name || "VS Code") + " · " + folder.place,
            get iconSource() { return root.iconSource(editor.app.icon) },
            icon: Icons.folder,
            run: () => {
                const context = Code.openContext(editor.app, folder.path, name => Paths.script(name))
                if (context) Quickshell.execDetached(context)
            },
            // The folder itself, in the file manager.
            alternate: () => Quickshell.execDetached(["xdg-open", folder.workspace
                ? folder.path.slice(0, folder.path.lastIndexOf("/")) : folder.path])
        }))
    }

    function loadCode() {
        if (codeAsked || !codeSearch) return
        codeAsked = true
        codeProc.running = true
        holdBriefly()
    }

    Process {
        id: codeProc
        command: ["python3", Paths.script("launcher-code-folders.py")]
        stderr: ErrorLog { label: "LauncherService.codeProc" }
        stdout: StdioCollector {
            // Only for the open that asked: one closed meanwhile let it go.
            onStreamFinished: if (root.codeAsked) root.codeFound = Code.parse(text)
        }
    }

    // ---- conversions ---------------------------------------------------------
    // "10 km to mi", "20 C in F", "100 eur to usd" through qalc (launcher/
    // ConvertLogic.js has the shape and what of the answer counts), once the
    // typing has settled: one short process per settled query, none for
    // anything else. qalc keeps its settings and fetched rates in a folder of
    // the shell's own: it saves its mode on every exit, and the user's own
    // qalculate settings are theirs.
    readonly property bool conversions: SettingsService.value("launcher.conversions") !== false
    readonly property bool exchangeRates: SettingsService.value("launcher.exchangeRates") === true
    readonly property string qalcDir: Paths.cacheDir + "/qalc"
    // expression → the answer, or false for none. A new object on each
    // answer, so `results` hears of it.
    property var convertAnswers: ({})
    property var convertPending: null
    // Set once a run could not start: qalc is not installed (Settings >
    // Launcher says so, and doctor.sh names the package).
    property bool qalcMissing: false
    property real ratesFetchedAt: 0
    property real ratesRetryAt: 0

    function conversionResult(query) {
        if (!conversions || qalcMissing) return null
        const parsed = Convert.parse(query)
        if (!parsed) return null
        const known = convertAnswers[parsed.expression]
        if (known === undefined) {
            Qt.callLater(root.queueConversion, parsed)
            return null
        }
        if (!known) return null
        return { kind: "calculator", key: "convert", title: known.title,
                 subtitle: Convert.subtitle(parsed, known, ratesFetchedAt > 0), icon: "󰓡",
                 run: () => { Quickshell.clipboardText = known.copy },
                 // The number alone, for a field that wants no unit.
                 alternate: () => { Quickshell.clipboardText = known.number || known.copy } }
    }

    function queueConversion(parsed) {
        if (!parsed || convertAnswers[parsed.expression] !== undefined) return
        if (convertPending && convertPending.expression === parsed.expression) return
        convertPending = parsed
        convertDebounce.restart()
    }

    // Until the typing settles: "10 km to m" is on the way to "10 km to mi".
    Timer {
        id: convertDebounce
        interval: 300
        onTriggered: root.startConversion()
    }

    // One run at a time; the next waits for its exit (onRunningChanged).
    function startConversion() {
        const job = convertPending
        if (!job || convertProc.running || qalcMissing) return
        convertPending = null
        if (convertAnswers[job.expression] !== undefined) return
        const now = Date.now()
        const fetching = Convert.needsRates(job, exchangeRates, ratesFetchedAt, now) && now >= ratesRetryAt
        convertProc.job = job
        convertProc.fetching = fetching
        convertProc.started = false
        convertProc.command = Convert.command(job, fetching)
        convertProc.running = true
        convertKill.interval = fetching ? 8000 : 3000
        convertKill.restart()
        holdBriefly()
    }

    function takeAnswer(job, output, fetching) {
        if (!job) return
        let fresh = false
        if (fetching) {
            // A fetch that failed (offline) says so in its output; it is
            // tried again in ten minutes rather than with every keystroke.
            if (Convert.ratesFailed(output)) ratesRetryAt = Date.now() + Convert.RATES_RETRY_MS
            else { ratesFetchedAt = Date.now(); fresh = true }
        }
        // New rates make every answer before them old.
        const next = fresh ? {} : Object.assign({}, convertAnswers)
        next[job.expression] = Convert.answer(output, job) || false
        convertAnswers = next
    }

    Process {
        id: convertProc
        // What this run was asked, kept until the next one starts: the
        // output is taken by the job it belongs to, whichever of the stream's
        // end and the exit comes first.
        property var job: null
        property bool fetching: false
        property bool started: false
        environment: ({ XDG_CONFIG_HOME: root.qalcDir + "/config", XDG_DATA_HOME: root.qalcDir + "/data" })
        stderr: ErrorLog { label: "LauncherService.convertProc" }
        stdout: StdioCollector {
            onStreamFinished: root.takeAnswer(convertProc.job, text, convertProc.fetching)
        }
        onStarted: started = true
        onRunningChanged: {
            if (running) return
            convertKill.stop()
            // Never started: no qalc (Quickshell says "Process failed to
            // start" once, and the launcher asks no more this session).
            if (!started) root.qalcMissing = true
            if (root.convertPending) Qt.callLater(root.startConversion)
        }
    }
    Timer {
        id: convertKill
        interval: 3000
        onTriggered: if (convertProc.running) convertProc.running = false
    }

    // Whether qalc is there, for Settings > Launcher: asked when the page
    // shows (a few ms), as the file index is.
    function checkQalc() {
        if (!qalcCheck.running) qalcCheck.running = true
    }
    Process {
        id: qalcCheck
        command: ["sh", "-c", "command -v qalc >/dev/null"]
        onExited: code => root.qalcMissing = code !== 0
    }

    // ---- the launcher opens and closes ---------------------------------------
    // What a query read for this open goes again when it closes: the recent
    // files, VS Code's folders and the answers of qalc (the rates in them age).
    function launcherClosed() {
        recentPath = ""
        recentList = []
        codeAsked = false
        codeFound = null
        if (codeProc.running) codeProc.running = false
        // A run still under way answers no one: its answer is not kept.
        convertProc.job = null
        convertPending = null
        convertDebounce.stop()
        convertAnswers = ({})
        releaseTimer.stop()
    }

    // The same goes when something else asked: the start menu's search
    // reads these sources too, and IPC `launcher results` with nothing open.
    // The launcher lets go itself when it closes; for the others it is half
    // a minute after the last read, or once the start menu has closed. The
    // timer only runs while something read is held.
    function holdBriefly() {
        if (PanelService.active !== "launcher") releaseTimer.restart()
    }
    Timer {
        id: releaseTimer
        interval: 30000
        onTriggered: {
            if (PanelService.active === "startMenu") restart()
            else if (PanelService.active !== "launcher") root.launcherClosed()
        }
    }

    // The rows a query gives, as the launcher would show them, for IPC
    // (`launcher results TEXT`): kinds, keys, titles and subtitles only.
    // What a source reads in the background (qalc, the recent files, VS
    // Code's folders) comes in a moment later - ask again.
    function describe(text) {
        const list = results(String(text || ""), "All").map(entry => ({
            kind: entry.kind || "", key: entry.key || "", title: entry.title || "", subtitle: entry.subtitle || "" }))
        return JSON.stringify(list)
    }

    // ---- files -------------------------------------------------------------
    // Called from the launcher's `results` binding, so it only schedules: a
    // write to `fileQuery` (or `fileResults`) inside that evaluation is a
    // binding loop on every keystroke (pitfall 34). Qt.callLater keeps the
    // last query of a turn; the binding returns the current results.
    function requestFiles(query) {
        Qt.callLater(root.setFileQuery, query.trim())
    }

    function setFileQuery(trimmed) {
        if (trimmed === fileQuery) return
        fileQuery = trimmed
        if (trimmed.length < 2) {
            fileDebounce.stop()
            fileResults = []
            fileSearchRunning = false
            if (fileProc.running) { fileProc.stale = true; fileProc.running = false }
            return
        }
        fileDebounce.restart()
    }

    Timer {
        id: fileDebounce
        interval: 250
        onTriggered: root.startFileSearch()
    }
    // A run still going is stopped, and the next one starts once it has
    // exited: `running = false; running = true` in one turn may not restart
    // at all. Each run carries the query it was started with, so the output
    // of a stopped one never lands under the next query.
    function startFileSearch() {
        if (fileProc.running) {
            fileProc.stale = true
            fileProc.running = false
            return
        }
        if (fileQuery.length < 2) { fileSearchRunning = false; return }
        fileProc.stale = false
        fileProc.query = fileQuery
        // Under the home folder, from the index (FileSearch.command).
        fileProc.command = FileSearch.command(Paths.home, fileQuery)
        // Asked again while the index has nothing from home (a few ms), so
        // the hint goes once the user has fixed it - no restart needed.
        if (homeIndexed <= 0) checkFileIndex()
        fileSearchRunning = true
        fileProc.running = true
    }

    // How many paths under the home folder the file index holds; -1 until
    // asked (with a file search, or by Settings > Launcher). None
    // means every search ends in "No files found": on this machine /home is
    // the btrfs subvolume @home, which updatedb takes for a bind mount and
    // skips (PRUNE_BIND_MOUNTS = "yes" in /etc/updatedb.conf). The
    // fix needs root, so it is the user's: `fileIndexHint` says which.
    property int homeIndexed: -1
    readonly property string fileIndexHint: homeIndexed !== 0 ? ""
        : "The file index holds nothing from your home folder. If /home is a btrfs subvolume, updatedb skips it as a bind mount: "
          + "set PRUNE_BIND_MOUNTS = \"no\" in /etc/updatedb.conf, then run sudo systemctl start plocate-updatedb.service."
    function checkFileIndex() {
        if (!indexProc.running) indexProc.running = true
    }
    Process {
        id: indexProc
        command: FileSearch.indexCommand(Paths.home)
        stderr: ErrorLog { label: "LauncherService.indexProc" }
        stdout: StdioCollector { onStreamFinished: root.homeIndexed = FileSearch.count(text) }
    }

    Process {
        id: fileProc
        property string query: ""
        // Stopped for a newer query, which starts once this run is gone.
        property bool stale: false
        stderr: ErrorLog { label: "LauncherService.fileProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                if (fileProc.stale || fileProc.query !== root.fileQuery) return
                const home = Paths.home + "/"
                root.fileResults = FileSearch.paths(text, Paths.home)
                    .map(path => ({
                        kind: "file", key: "file:" + path, title: path.split("/").pop(), subtitle: "~/" + path.slice(home.length),
                        icon: /\.(png|jpe?g|webp|svg|gif)$/i.test(path) ? "󰋩" : /\.pdf$/i.test(path) ? "󰈦" : "󰈔",
                        run: () => Quickshell.execDetached(["xdg-open", path]),
                        alternate: () => Quickshell.execDetached(["xdg-open", path.slice(0, path.lastIndexOf("/"))])
                    }))
                root.fileSearchRunning = false
            }
        }
        onExited: {
            if (fileProc.stale) Qt.callLater(root.startFileSearch)
            else if (fileProc.query === root.fileQuery) root.fileSearchRunning = false
        }
    }
}
