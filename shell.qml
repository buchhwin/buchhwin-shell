import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQml
import qs.shell.emoji
import qs.shell.welcome
import qs.shell.launcher
import qs.shell.controlcenter
import qs.shell.notifications
import qs.shell.powermenu
import qs.shell.desktop
import qs.shell.editor
import qs.shell.dashboard
import qs.shell.settings
import qs.shell.bar
import qs.shell.notch
import qs.shell.dock
import qs.shell.startmenu
import qs.shell.network
import qs.shell.bluetooth
import qs.shell.drives
import qs.shell.osd
import qs.shell.clipboard
import qs.shell.wallpaper
import qs.shell.colorpicker
import qs.shell.displays
import qs.shell.overview
import qs.shell.switcher
import qs.shell.shortcuts
import qs.shell.popups
import qs.shell.assistant
import qs.shell.sharepicker
import qs.shell.components
import qs.services
import qs.theme
import "services/profile/ProfileLogic.js" as Profile
import "services/notch/NotchLogic.js" as NotchLogic
import "services/appearance/AnimationLogic.js" as AnimationLogic
import "services/shortcuts/ShellShortcuts.js" as ShellShortcuts
import "services/display/DisplayLogic.js" as DisplayLogic
import "services/dock/DockLogic.js" as DockLogic
import "services/ipc/IpcLogic.js" as IpcLogic
import "services/settings/SettingsNavLogic.js" as SettingsNav

ShellRoot {
    id: root
    // No hot reload. Quickshell reloads the whole graph when a file under
    // the shell directory changes, and a deploy changes many files one after
    // another: the reload ran on a half-written tree and died in
    // QWindow::setScreen five times on 2026-09-22, seconds after each
    // fast-forward of the stable worktree. The deploy restarts the shell
    // itself once the tree is complete, so the watcher has nothing to add
    // and one crash per deploy to take away. docs/system.md > Dependencies.
    settings.watchFiles: false

    // The notification server must exist from startup, not on first use.
    readonly property bool notificationsReady: NotificationService.server !== null
    readonly property bool appearanceReady: AppearanceService.cursorThemes !== null
    // Idle handling and saved monitor settings must run from startup.
    readonly property bool idleReady: IdleService.realSession !== undefined
    // Low battery warnings watch UPower from startup.
    readonly property bool powerReady: PowerService.lowBatteryLevel > 0
    readonly property bool displaysReady: DisplayService.confirmSeconds > 0
    // A color filter chosen before is put back at the start; without one the
    // zoom and filter service is not made until a key or a panel asks for it.
    readonly property bool screenEffectsReady: SettingsService.value("display.colorFilterOn") !== true || ScreenEffectsService.ready
    readonly property bool inputReady: InputService.current !== null
    readonly property bool clipboardReady: ClipboardService.dbPath.length > 0
    readonly property bool adaptiveReady: AdaptiveService.suggestedMode !== undefined
    readonly property bool nightLightReady: NightLightService.mode.length > 0
    readonly property bool autostartReady: AutostartService.marker.length > 0
    // Terminal config files follow the settings from startup.
    readonly property bool terminalReady: TerminalService.starshipPath.length > 0
    // Drive notifications watch UDisks2 from startup.
    readonly property bool drivesReady: DrivesService.available !== undefined
    // Custom shortcuts are bound at startup.
    readonly property bool shortcutsReady: ShortcutService.custom !== null
    // Touchpad gestures are registered at startup.
    readonly property bool gesturesReady: GestureService.slots.length > 0
    // The automatic update check runs from startup (real session only).
    readonly property bool updatesReady: UpdatesService.checkHours >= 0
    // Apps following the theme are switched from startup (opt-in).
    readonly property bool appThemeReady: AppThemeService.statePath.length > 0
    // With no weather place set, the location by IP is asked for once.
    readonly property bool locationReady: LocationService.autoLocate !== undefined
    // Minimized windows come back at every start, and an app's own minimize
    // button is heard from the start (MinimizeService).
    readonly property bool minimizeReady: MinimizeService.realSession !== undefined
    // Apps' places are sent to Hyprland from startup, and a login's work
    // apps and offer come from here (Settings > Apps; nothing without them).
    readonly property bool sessionAppsReady: SessionAppsService.storePath.length > 0
    WallpaperLayer {}
    ScreenCorners {}
    WidgetHost {}
    PillBar {}
    Notch {}
    // A track change in the notch, for a few seconds. It has no surface of its
    // own: with no notch, or with the switch off, nothing happens.
    NotchTrackChange {}
    // The dock: no surfaces while it is off (Dock.qml).
    Dock {}

    // The scrim is a Top surface and every panel an Overlay one, so the
    // layers keep it under the panels whatever the order here
    // (ScrimLayer.qml). Inside the Top layer the compositor stacks by
    // creation, and the notch, the bar and the dock are made once the layout
    // or the settings have loaded - after the scrim, so they sit above it and
    // are never dimmed.
    ScrimLayer {}

    Launcher {}
    // The panels in a LazyLoader on `PanelService.demanded` are built on their
    // first open and kept for the rest of the session: a panel is built at the
    // start whether it opens or not (testing.md pitfall 101), and these are
    // opened rarely or never in a session - Settings, the dialogs, the power
    // menu, the shortcut sheet, the pickers, the history panels. Built at the
    // start, ten of them held 13.6 MB nested (19.10.); built on the first
    // open, they add their build to it once - some 40 ms for Settings, 10-20
    // for the event editor and the power menu, a few for the others (offscreen,
    // without the window). PanelService.open asks for one that is not there
    // and opens it once it has reported in (pitfall 110); each id is in
    // PanelService.lazyPanels.
    // Each is named by its file, not by its type: a type named anywhere in
    // this file is compiled at the start, built or not - taking the nineteen
    // here out lowered the start's memory by some 3.5 MB (nested, 20.10.).
    // A file in `source` is read on its first open instead, which adds its
    // compile to that open once. `active` follows `source`, because
    // a LazyLoader builds nothing from a file it gets after it was told to be
    // active. Built from its file, a panel sees the singletons but not the
    // ids of this file (none of them uses one).
    LazyLoader { source: PanelService.demanded.emoji === true ? "shell/emoji/EmojiPanel.qml" : ""; active: source.length > 0 }
    // The tour: built for the first start (until it has been seen), or when
    // Settings > About or IPC opens it again - not at every start for a panel
    // shown once per install (PanelService.lazyPanels). Opened once, it stays
    // for the session, so marking itself completed does not unload it.
    LazyLoader {
        source: PanelService.demanded.welcome === true
            || (SettingsService.loaded && SettingsService.value("onboarding.completed") !== true)
            ? "shell/welcome/WelcomePanel.qml" : ""
        active: source.length > 0
    }
    ControlCenter {}
    NotificationPopupStack {}
    LazyLoader { source: PanelService.demanded.notifications === true ? "shell/notifications/NotificationCenter.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.powerMenu === true ? "shell/powermenu/PowerMenu.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.shortcutSheet === true ? "shell/shortcuts/ShortcutSheet.qml" : ""; active: source.length > 0 }

    IpcHandler {
        id: desktopIpc
        target: "desktop"
        // The desktop mode had no key of its own: it could only be changed in
        // Settings or through three launcher commands.
        function cycleMode(): string {
            const modes = LayoutService.desktopModes
            const next = modes[(modes.indexOf(LayoutService.desktopMode) + 1) % modes.length]
            if (!LayoutService.setDesktopMode(next)) return LayoutService.desktopMode
            osd.showMessage(LayoutService.desktopModeLabel, LayoutService.notchShown ? "󱂩" : LayoutService.barShown ? "󰘔" : "󰕰")
            return next
        }
        function setMode(name: string): bool { return LayoutService.setDesktopMode(name) }
        function getMode(): string { return LayoutService.desktopMode }
    }

    IpcHandler {
        id: editorIpc
        target: "editor"
        function toggle(): void { LayoutService.editMode = !LayoutService.editMode }
        function open(): void { LayoutService.editMode = true }
        // The editor on the dock's zones (its toolbar's "Dock").
        function dock(): void {
            if (SettingsService.value("dock.enabled") !== true) SettingsService.set("dock.enabled", true)
            LayoutService.editTarget = "dock"
            LayoutService.editMode = true
        }
        function close(): void { LayoutService.editMode = false }
        function undo(): void { LayoutService.undo() }
        // Counts only: the bar edits the real pills, so a test has to be able
        // to ask whether they reported where they are. No ids, no labels.
        function get(): string {
            const keys = Object.keys(LayoutService.surfaceRects)
            return JSON.stringify({ editing: LayoutService.editMode,
                                    rects: keys.length,
                                    notchRects: keys.filter(key => key.indexOf("/notch:") >= 0).length,
                                    notchZones: keys.filter(key => key.indexOf("/notchzone:") >= 0).length,
                                    dragging: LayoutService.editorDragging.length > 0,
                                    arranging: LayoutService.arrangeDragging.length > 0,
                                    // Frames the last open of each panel was
                                    // drawn in. A 220 ms open at 60 Hz is
                                    // about thirteen.
                                    openFrames: PanelService.openFrames,
                                    // Where the collapsed notch says it is,
                                    // per screen: the place every panel grows
                                    // out of. A geometry, not a content - it
                                    // is the one number that says whether a
                                    // panel can possibly start in the right
                                    // place.
                                    notchOrigin: Quickshell.screens.map(screen => {
                                        const rect = LayoutService.notchRect(screen.name)
                                        return rect ? { screen: screen.width, x: rect.x, w: rect.width } : null
                                    }) })
        }
        // Where the notch's items and its two zones are, for a test that has
        // to aim at one of them. Layout ids and rectangles only - they are the
        // shell's own words for its own parts, never anything the user typed.
        function notchRects(): string {
            const all = LayoutService.surfaceRects
            const result = {}
            for (const key of Object.keys(all))
                if (key.indexOf("/notch:") >= 0 || key.indexOf("/notchzone:") >= 0) result[key] = all[key]
            return JSON.stringify(result)
        }
    }

    IpcHandler {
        target: "welcome"
        // Not `show`: the IPC client takes that word for itself and prints the
        // target instead of calling anything.
        function open(): void { PanelService.open("welcome") }
        function close(): void { PanelService.close("welcome") }
    }

    IpcHandler {
        id: emojiIpc
        target: "emoji"
        function toggle(): void { PanelService.toggle("emoji") }
        function open(): void { PanelService.open("emoji") }
        function close(): void { PanelService.close("emoji") }
    }

    // The start menu (shell/startmenu). `get` and `rects` are counts, flags
    // and places, never an app's or the user's name.
    IpcHandler {
        id: startMenuIpc
        target: "startMenu"
        function toggle(): void {
            if (PanelService.isOpen("startMenu")) PanelService.close("startMenu")
            else root.openStartMenu("home")
        }
        function open(): void { root.openStartMenu("home") }
        // "home" or "all".
        function openView(view: string): bool {
            if (view !== "home" && view !== "all") return false
            if (PanelService.isOpen("startMenu") && startMenuLoader.item) startMenuLoader.item.openView(view)
            else root.openStartMenu(view)
            return true
        }
        function close(): void { PanelService.close("startMenu") }
        // The start menu's key (Super+Space, Settings > Shortcuts): a press
        // of the start button. Only while the dock is on and has one - the
        // taskbar -, and it opens what the button opens (the start menu, or
        // the launcher: Settings > Dock > Start button), out of the button;
        // pressed again, it closes it. Anywhere else it does nothing (false).
        function key(): bool {
            if (SettingsService.value("dock.enabled") !== true || !LayoutService.dockHasStart) return false
            const panel = WidgetRegistry.actionOf("start")
            if (PanelService.isOpen(panel)) PanelService.close(panel)
            else root.openFromStart(panel, "home")
            return true
        }
        function get(): string {
            const menu = startMenuLoader.item
            return JSON.stringify(Object.assign({ loaded: menu !== null && menu !== undefined },
                                                menu ? JSON.parse(menu.describe()) : {}))
        }
        // The start button and the card on the screen the menu is on (or the
        // focused one), screen-local.
        function rects(): string {
            const menu = startMenuLoader.item
            const focused = PanelService.focusedScreen()
            const name = PanelService.isOpen("startMenu") ? PanelService.screenName : focused ? focused.name : ""
            return JSON.stringify({ screen: name, button: LayoutService.dockItemRect(name, "start"),
                                    card: menu && PanelService.isOpen("startMenu") ? menu.cardPlace() : null })
        }
    }

    // Apps in their places (Settings > Apps, services/SessionAppsService.qml):
    // the work apps, the last session's apps, a place per app. get() says
    // counts and flags only, never an app's name.
    IpcHandler {
        id: sessionAppsIpc
        target: "sessionApps"
        function get(): string { return SessionAppsService.describe() }
        // The work apps not running yet, started (Super+Alt+W); with none set,
        // Settings > Apps opens. The number started.
        function startWork(): int { return SessionAppsService.startWork() }
        // The last session's apps started again and put back.
        function reopen(): bool { return SessionAppsService.reopen() }
        // The windows of now kept as the end of a session keeps them, or the
        // kept ones forgotten.
        function snapshot(): bool { return SessionAppsService.snapshotNow() }
        function forget(): bool { return SessionAppsService.forget() }
        // A place for an app: a connected screen by its connector name ("" for
        // any), one of its ten workspaces or 0 for the one it shows, floating.
        function placeApp(app: string, screen: string, workspace: int, floating: bool): bool {
            return SessionAppsService.placeApp(app, screen, workspace, floating)
        }
        function unplaceApp(app: string): bool { return SessionAppsService.unplace(app) }
    }

    IpcHandler {
        id: launcherIpc
        target: "launcher"
        function toggle(): void { PanelService.toggle("launcher") }
        function open(): void { PanelService.open("launcher") }
        function close(): void { PanelService.close("launcher") }
        // Arranging its blocks, the same as the pencil in its header. A nested
        // session cannot click one, and a drag is over before a screenshot can
        // catch it.
        function arrange(on: bool): void { LayoutService.launcherEditing = on }
        // The grid as the layout file holds it and where every block is
        // resting, the way `controlCenter rects` and `dashboard rects` do it.
        // A drag is over before a screenshot can catch it.
        function blocks(): string {
            return JSON.stringify({ editing: LayoutService.launcherEditing,
                                    blocks: LayoutService.launcherItems,
                                    cells: LayoutService.launcherCells,
                                    choices: LayoutService.launcherChoices() })
        }
        // Opened with TEXT typed, as if it had been: a nested session can
        // show a query's rows in a screenshot without a keyboard.
        function search(text: string): void { PanelService.open("launcher", { query: text }) }
        // The rows TEXT gives (kind, key, title, subtitle), without opening
        // anything. Conversions, recent files and VS Code's folders are read
        // in the background: ask again a moment later for them.
        function results(text: string): string { return LauncherService.describe(text) }
    }

    IpcHandler {
        id: controlCenterIpc
        target: "controlCenter"
        function toggle(): void { PanelService.toggle("controlCenter") }
        // A page that is not one of its seven (or "" for the overview) is
        // refused, as `settings open` refuses one of Settings'.
        function openPage(page: string): bool {
            if (!IpcLogic.controlCenterPage(page)) return false
            PanelService.open("controlCenter", { page: page })
            return true
        }
        function open(): void { PanelService.open("controlCenter") }
        function close(): void { PanelService.close("controlCenter") }
        // Arranging the tiles, the same as the pencil in the header.
        function arrange(on: bool): void { LayoutService.quickEditing = on }
        // Where the tiles are resting in the grid, so a test can check where a
        // drag actually put one instead of trusting the list order. Layout ids
        // and rectangles only - the shell's own words for its own parts.
        function rects(): string { return JSON.stringify(LayoutService.quickCells) }
        // A tile from the picker's catalogue onto the active mode's panel, as
        // the picker adds it (false for a type it does not know): a nested
        // check reaches a tile that is in nobody's layout yet this way.
        function addTile(type: string): bool { return LayoutService.quickAdd(type) }
    }

    IpcHandler {
        id: notificationsIpc
        target: "notifications"
        function toggle(): void { PanelService.toggle("notifications") }
        function open(): void { PanelService.open("notifications") }
        function close(): void { PanelService.close("notifications") }
        function toggleDnd(): void { NotificationService.toggleDnd() }
        function setDnd(mode: string): void { NotificationService.setDnd(mode) }
        function clear(): void { NotificationService.clearAll() }
        // Counts and flags only: no notification titles, bodies or app names
        // (NotificationService.report: shares, why it is quiet, the popups'
        // screen, held back, notices, kept, sounds).
        function get(): string {
            return JSON.stringify(Object.assign({ serverWanted: NotificationService.serverWanted,
                                    server: NotificationService.server !== null,
                                    history: NotificationService.history.length,
                                    popups: NotificationService.popups.length,
                                    unread: NotificationService.unread,
                                    dndMode: NotificationService.dndMode,
                                    dndBy: NotificationService.dndBy,
                                    dndActive: NotificationService.dndActive,
                                    autoSuppressed: NotificationService.autoSuppressed,
                                    suppressed: NotificationService.suppressed,
                                    fullscreenActive: HyprlandService.fullscreenActive,
                                    gameActive: HyprlandService.gameActive }, NotificationService.report()))
        }
        // A popup of the shell's own (NotificationService.postNotice): no
        // sender, no history. For scripts, and for looking at the popups in a
        // nested session, which runs no notification server. False when Do
        // Not Disturb holds it back.
        function notice(summary: string, body: string): bool {
            return NotificationService.postNotice({ summary: summary, body: body }) !== null
        }
    }

    IpcHandler {
        id: powerMenuIpc
        target: "powerMenu"
        function toggle(): void { PanelService.toggle("powerMenu") }
        function open(): void { PanelService.open("powerMenu") }
        function close(): void { PanelService.close("powerMenu") }
    }

    IpcHandler {
        id: settingsIpc
        target: "settings"
        function setAnimationMode(mode: string): bool { return SettingsService.set("appearance.animationMode", mode) }
        // The slider's value (0.5-2, 1 = the base pace), for the active mode.
        function setAnimationSpeed(speed: real): bool {
            if (!isFinite(speed) || speed < AnimationLogic.SPEED_MIN || speed > AnimationLogic.SPEED_MAX) return false
            return SettingsService.set("appearance.animationSpeed", Math.round(speed * 20) / 20)
        }
        function setTheme(theme: string): bool { return SettingsService.set("appearance.theme", theme) }
        // The theme's automatic switching and what the sun says now - no
        // times and no place (they would tell where the user is).
        function themeState(): string {
            return JSON.stringify({ theme: SettingsService.theme, autoTheme: SettingsService.value("appearance.autoTheme"),
                                    dark: Colors.dark, sun: { known: SunService.known, ready: SunService.ready,
                                                              night: SunService.night, polar: SunService.polar } })
        }
        // Not what says where the user is or what they did (the weather place,
        // the calendars, the colours picked, the folders and files used):
        // for those only whether they are set (IpcLogic.privateSetting).
        function get(path: string): string {
            const value = SettingsService.value(path)
            return JSON.stringify(IpcLogic.privateSetting(path)
                ? IpcLogic.withheldAnswer(value, SettingsService.defaultOf(path)) : value)
        }
        // A page id that is not one of Settings' pages is refused (false), so a
        // typo in a script says so instead of opening the last page.
        function open(page: string): bool {
            if (page.length && !SettingsNav.pageById(page)) return false
            PanelService.open("settings", page.length ? { page: page } : {})
            return true
        }
        function toggle(): void { PanelService.toggle("settings") }
        function close(): void { PanelService.close("settings") }
    }

    IpcHandler {
        target: "appTheme"
        // Commands for KDE/GTK apps (Settings > Appearance); test sessions only
        // log them. Returns JSON with the plan, current and saved values.
        function plan(): string { return AppThemeService.planJson() }
        function refresh(): void { AppThemeService.refresh() }
    }

    IpcHandler {
        id: dashboardIpc
        target: "dashboard"
        function toggle(): void { PanelService.toggle("dashboard") }
        // Select a day (YYYY-MM-DD) like a click in the month grid.
        function selectDay(day: string): void { PanelService.open("dashboard", { day: day }) }
        // Arranging the cards, the same as the pencil in its header, and where
        // they are resting in the grid - a drag is over before a screenshot
        // can catch it.
        function arrange(on: bool): void { LayoutService.dashboardEditing = on }
        function rects(): string { return JSON.stringify(LayoutService.dashboardCells) }
        // A card onto the dashboard of the mode in use, as the picker adds it
        // ("worldClock", "notes", a widget type); and which cards it has, and
        // how many places the world clock shows (not which).
        function add(type: string): bool { return LayoutService.dashboardAdd(type) }
        function get(): string {
            return JSON.stringify({ cards: LayoutService.dashboardTypes,
                                    worldClocks: String(SettingsService.value("desktop.worldClocks") || "").split(",")
                                        .filter(part => part.trim().length).length })
        }
        function open(): void { PanelService.open("dashboard") }
        function close(): void { PanelService.close("dashboard") }
    }

    IpcHandler {
        target: "popup"
        // Pill popups by name, centred at a screen x in logical pixels like a
        // pill click (negative: default place below the clock).
        // A plain function, not a property: an IpcHandler exports its
        // properties, and a list cannot cross IPC.
        function isPopup(name: string): bool {
            return ["network", "vpn", "bluetooth", "media", "volume", "battery",
                    "weather", "events", "privacy", "system", "profile"].indexOf(name) >= 0
        }
        // An x that is no place (NaN, an infinity) is the default place too.
        function open(name: string, anchorX: real): bool {
            if (!isPopup(name)) return false
            PanelService.open(name + "Popup", isFinite(anchorX) && anchorX >= 0 ? { anchorX: anchorX } : {})
            return true
        }
        // Like open, but the popup grows out of the given rect the way a pill
        // click makes it grow out of the pill. A rect with a NaN or an
        // infinity in it is refused (IpcLogic.originArgs).
        function openAt(name: string, x: real, y: real, width: real, height: real): bool {
            const args = IpcLogic.originArgs(x, y, width, height)
            if (!isPopup(name) || !args) return false
            PanelService.open(name + "Popup", args)
            return true
        }
        function close(): void { PanelService.close() }
        function get(): string { return PanelService.active }
    }

    // The newer widgets, for checks: the tray, the command widgets, the
    // sensors and the media popup's visualizer. Counts, flags and numbers -
    // never an app's name, a command or what it printed.
    IpcHandler {
        target: "widgets"
        function tray(): string { return JSON.stringify(TrayService.status()) }
        // The menu of the N-th app a tray widget shows, at the default place.
        function trayMenu(index: int): bool {
            const item = TrayService.shownItems[index]
            return item ? TrayService.openMenu(item, {}) : false
        }
        function commands(): string { return JSON.stringify(CommandWidgetService.status()) }
        // "one", "two" or "three": run now, as Settings' "Run now" does.
        function runCommand(slot: string): void { CommandWidgetService.runNow(slot) }
        function sensors(): string { return JSON.stringify(SystemStatsService.sensorStatus()) }
        function visualizer(): string { return JSON.stringify(MprisService.visualizerStatus()) }
    }

    IpcHandler {
        target: "weather"
        function refresh(): void { WeatherService.refresh() }
        function setLocation(name: string, lat: real, lon: real): bool { return WeatherService.setLocation(name, lat, lon) }
        function clearLocation(): void { WeatherService.clearLocation() }
        function detectLocation(): void { LocationService.detectByIp() }
        // Whether a place is set, not which: get() handlers return counts and
        // flags, never names (the place is the user's own business).
        function get(): string {
            const current = WeatherService.current
            return JSON.stringify({ status: WeatherService.status, hasLocation: WeatherService.hasLocation,
                                    temperature: current ? current.temperature : null, condition: current ? current.label : "",
                                    hours: WeatherService.hourly.length, days: WeatherService.daily.length })
        }
    }

    IpcHandler {
        target: "calendar"
        function refresh(): void { CalendarService.refresh() }
        // Status and counts only; event titles stay private.
        function get(): string {
            return JSON.stringify({ status: CalendarService.status, calendars: CalendarService.calendarRows.length,
                                    visibleCalendars: CalendarService.visibleCalendarCount,
                                    today: CalendarService.todayEvents.length,
                                    daysWithEvents: Object.keys(CalendarService.eventDays).length,
                                    writableCalendars: CalendarService.newEventCalendars.length,
                                    writeAllowed: CalendarService.writeAllowed, editor: CalendarService.saveState,
                                    eventCheck: CalendarService.identityState, eventCheckReason: CalendarService.identityReason,
                                    linkCalendars: CalendarService.linkCalendars.length, joinPreview: CalendarService.joinPreview })
        }
        // Calendars from a link: how many and in which state - no names, no
        // hosts, never the link. Asks the helper again in the real session
        // (the answer is then the one before).
        function links(): string {
            CalendarService.refreshLinks()
            return JSON.stringify({ state: CalendarService.linkState, listing: CalendarService.linkListing,
                                    count: CalendarService.linkCalendars.length,
                                    statuses: CalendarService.linkCalendars.map(row => row.status),
                                    error: CalendarService.linkError, preview: CalendarService.linkPreview.length > 0 })
        }
        // Events on a day (YYYY-MM-DD) that carry a meeting link; no titles.
        function meetings(day: string): int {
            const parts = day.split("-").map(Number)
            return CalendarService.eventsFor(new Date(parts[0], parts[1] - 1, parts[2]))
                .filter(event => CalendarService.meetingFor(event) !== null).length
        }
        // Joins the INDEX-th event of a day as its Join button does: the
        // service ("teams", "meet", "zoom", "webex") or "" without a meeting.
        // A test session opens nothing (get's joinPreview says what it would).
        function join(day: string, index: int): string {
            const parts = day.split("-").map(Number)
            const events = CalendarService.eventsFor(new Date(parts[0], parts[1] - 1, parts[2]))
            if (index < 0 || index >= events.length) return ""
            const found = CalendarService.meetingFor(events[index])
            return found && CalendarService.join(events[index]) ? found.service : ""
        }
        // New-event dialog for today in dry-run mode: saving shows the
        // request that would be sent instead of sending it.
        function editorPreview(): void {
            CalendarService.editorPreview = true
            CalendarService.openEditor(new Date())
        }
        // Synthetic events around today in eventsFor() (month, event list).
        function preview(): void {
            const choices = Colors.accentChoices
            CalendarService.startPreview([choices[0], choices[6], choices[4], choices[1]])
        }
        function stopPreview(): void { CalendarService.previewEvents = null }
        // Details dialog of the INDEX-th event on a day (like a click in the
        // event list); returns false when there is no such event. No titles.
        function showEvent(day: string, index: int): bool {
            const parts = day.split("-").map(Number)
            const events = CalendarService.eventsFor(new Date(parts[0], parts[1] - 1, parts[2]))
            if (index < 0 || index >= events.length) return false
            CalendarService.openEvent(events[index], { day: day })
            return true
        }
        // Number of events on a day (YYYY-MM-DD); no titles.
        function count(day: string): int {
            const parts = day.split("-").map(Number)
            return CalendarService.eventsFor(new Date(parts[0], parts[1] - 1, parts[2])).length
        }
    }

    IpcHandler {
        target: "network"
        function passwordDialog(ssid: string): void { PanelService.open("wifiPassword", { ssid: ssid, security: "WPA2" }) }
        function hiddenDialog(): void { PanelService.open("wifiPassword", { hidden: true }) }
        function hotspotDialog(): void { PanelService.open("wifiPassword", { hotspot: true }) }
        // A captive portal's card and line without a portal, for screenshots;
        // its "Sign in" then opens nothing (NetworkService.portalPreview).
        function previewPortal(on: bool): void { NetworkService.portalPreview = on }
        // What the card's "Sign in" does: the portal's page in the browser.
        function signIn(): void { NetworkService.openPortal() }
        // mountinfo read again, for the drives' counts in `get` a moment later.
        function readShares(): void { NetworkService.readShares() }
        // Flags and counts; no network names, no paths.
        function get(): string {
            return JSON.stringify({ wifi: NetworkService.wifiEnabled, connected: NetworkService.connected,
                                    hotspot: NetworkService.hotspotActive, busy: NetworkService.helperState,
                                    portal: NetworkService.signInNeeded, portalPreview: NetworkService.portalPreview,
                                    shares: NetworkService.shares.length,
                                    sharesMounted: NetworkService.shares.filter(item => item.mounted).length,
                                    vpnUp: NetworkService.vpnUp })
        }
    }

    IpcHandler {
        target: "bluetooth"
        // Sample dialog for tests and screenshots; answers never reach BlueZ.
        function previewPairing(kind: string): void { BluetoothService.previewPairing(kind) }
        // What a low battery warning says, logged and not sent (no device needed).
        function previewBatteryWarning(): string { return BluetoothService.previewBatteryWarning() }
        function get(): string {
            return JSON.stringify({ available: BluetoothService.available, enabled: BluetoothService.enabled,
                                    agentAllowed: BluetoothService.agentAllowed, agentReady: BluetoothService.agentReady,
                                    batteryWarning: BluetoothService.batteryWarning, lowBattery: BluetoothService.lowDevices })
        }
    }

    IpcHandler {
        id: osdIpc
        target: "osd"
        // Caps Lock's key sends this on its release (hypr: a bind that leaves
        // the key to the window): "Caps Lock on" or "off" with Settings >
        // Desktop > Caps Lock on, nothing otherwise.
        function capsLock(): void { osd.capsLock() }
        // The OSD's messages with sample text, whatever the settings say, for
        // screenshots: output, charger, vpn, capsLock, mics.
        function previewToast(kind: string): bool { return osd.previewToast(kind) }
        // Flags only: shown, the kind, push to talk, which messages are on.
        function get(): string { return JSON.stringify(osd.osdState()) }
    }

    IpcHandler {
        target: "kdeConnect"
        function refresh(): void { KdeConnectService.refresh() }
        // Synthetic devices for screenshots; actions stay disabled.
        function preview(): void { KdeConnectService.previewDevices() }
        // Opens the notification list of the first connected device so it can
        // be screenshotted; the texts never reach IPC.
        function previewNotifications(): void {
            if (KdeConnectService.connected.length) KdeConnectService.toggleNotifications(KdeConnectService.connected[0])
        }
        // Counts only: no device names, no media titles, no notification texts.
        function get(): string {
            return JSON.stringify({ known: KdeConnectService.known, running: KdeConnectService.running,
                                    devices: KdeConnectService.status.devices.length, paired: KdeConnectService.paired.length,
                                    connected: KdeConnectService.connected.length,
                                    requests: KdeConnectService.requests.length, realSession: KdeConnectService.realSession,
                                    preview: KdeConnectService.preview, trackers: KdeConnectService.trackers,
                                    notifications: KdeConnectService.notifications.length,
                                    notificationsOpen: KdeConnectService.notificationsId.length > 0 })
        }
    }

    IpcHandler {
        target: "fingerprint"
        // Read-only fprintd-list; enrolling and deleting are never reachable over IPC.
        function refresh(): void { FingerprintService.refresh() }
        // Synthetic reader and a replayed enrollment (tests/fixtures), nothing reaches fprintd.
        function preview(): void { FingerprintService.startPreview("enroll") }
        function previewDenied(): void { FingerprintService.startPreview("denied") }
        function stopPreview(): void { FingerprintService.stopPreview() }
        // Closed-lid status in the preview (tile and settings text).
        function previewLid(closed: bool): void { FingerprintService.setPreviewLid(closed) }
        // Unlock mode auto|on|off (applies at the next lock screen conversation).
        function setMode(mode: string): string {
            return FingerprintService.setMode(mode) ? FingerprintService.mode : "invalid mode: use auto, on or off"
        }
        function get(): string {
            const state = FingerprintService.enrollment
            return JSON.stringify({ known: FingerprintService.known, available: FingerprintService.available,
                                    enrolled: FingerprintService.fingers.length, stages: FingerprintService.stages,
                                    preview: FingerprintService.preview, trackers: FingerprintService.trackers,
                                    mode: FingerprintService.mode, lidClosed: FingerprintService.lidClosed,
                                    enabledNow: FingerprintService.enabledNow, polkit: FingerprintService.polkitState,
                                    phase: state ? state.phase : "", stage: state ? state.stage : 0,
                                    message: state ? state.message : FingerprintService.message })
        }
    }

    IpcHandler {
        target: "drives"
        // Synthetic drives, an encrypted volume and a phone for screenshots;
        // actions stay disabled.
        function preview(): void { DrivesService.showPreview() }
        function stopPreview(): void { DrivesService.stopPreview() }
        function open(): void { PanelService.open("controlCenter", { page: "drives" }) }
        // Safely remove a drive by id (blocked outside the real session and in preview).
        function eject(id: string): string { DrivesService.eject(DrivesService.find(id)); return DrivesService.message }
        // Opens the passphrase dialog for a volume id; never takes a passphrase.
        function unlock(id: string): string {
            const found = DrivesService.findVolume(id)
            if (!found) return "unknown volume: " + id
            DrivesService.askPassphrase(found.drive, found.volume)
            return "dialog open"
        }
        // The system disk as the last look saw it: / and /home, free and
        // total bytes and which are low; a look now; and what a filesystem of
        // SIZE bytes with FREE left would be told (worked out, never sent).
        function space(): string {
            return JSON.stringify({ enabled: DrivesService.lowSpaceEnabled, realSession: DrivesService.realSession,
                                    entries: DrivesService.spaceEntries.map(entry => ({ mounts: entry.mounts, free: entry.free, size: entry.size,
                                                                                      low: DrivesService.lowSpaceEntries.indexOf(entry) >= 0 })),
                                    warned: Object.keys(DrivesService.spaceWarned).length })
        }
        function checkSpace(): void { DrivesService.checkSpace() }
        function previewSpace(free: real, size: real): string { return DrivesService.previewSpace(free, size) }
        // Counts only, no labels, mount points or passphrases.
        function get(): string {
            return JSON.stringify({ available: DrivesService.available, drives: DrivesService.drives.length,
                                    mounted: DrivesService.drives.filter(drive => DrivesService.anyMounted(drive)).length,
                                    locked: DrivesService.drives.reduce((total, drive) =>
                                        total + drive.volumes.filter(volume => DrivesService.locked(volume)).length, 0),
                                    phones: DrivesService.phones.length,
                                    phonesOpen: DrivesService.phones.filter(phone => phone.mounted).length,
                                    mtp: DrivesService.mtpAvailable,
                                    busy: Object.keys(DrivesService.busy).length, pending: DrivesService.pending.length,
                                    realSession: DrivesService.realSession, preview: DrivesService.preview,
                                    notify: DrivesService.notifyEnabled, autoOpen: DrivesService.autoOpen,
                                    lowSpace: DrivesService.lowSpaceEnabled })
        }
    }

    IpcHandler {
        target: "accounts"
        // Read-only snapshot of Akonadi's agent instances; no account is ever
        // synchronized, configured or removed over IPC.
        function refresh(): void { AccountsService.refresh() }
        // Synthetic accounts for screenshots; actions stay disabled.
        function preview(): void { AccountsService.showPreview() }
        function stopPreview(): void { AccountsService.stopPreview() }
        // Counts, states and instance ids only, never account names.
        function get(): string {
            return JSON.stringify({ known: AccountsService.known, server: AccountsService.serverRunning,
                                    accounts: AccountsService.accounts.length, groups: AccountsService.groups.length,
                                    syncing: AccountsService.syncingCount, broken: AccountsService.brokenCount,
                                    offline: AccountsService.offlineCount,
                                    ids: AccountsService.accounts.map(item => item.id),
                                    wizards: AccountsService.addOptions.map(item => item.tool),
                                    realSession: AccountsService.realSession, preview: AccountsService.preview,
                                    actionsAllowed: AccountsService.actionsAllowed, busy: AccountsService.busyId.length > 0,
                                    confirming: AccountsService.confirmRemoveId.length > 0,
                                    command: AccountsService.previewCommand, message: AccountsService.message,
                                    trackers: AccountsService.trackers })
        }
    }

    IpcHandler {
        target: "updates"
        // Read-only check (nested sessions use the dnf cache and never notify).
        function check(): void { UpdatesService.check(false) }
        function open(): void { PanelService.open("settings", { page: "updates" }) }
        // Synthetic updates for screenshots; actions stay disabled.
        function preview(): void { UpdatesService.showPreview() }
        function stopPreview(): void { UpdatesService.stopPreview() }
        // Expands or collapses the lists on the page.
        function expand(expanded: bool): void {
            UpdatesService.packagesExpanded = expanded
            UpdatesService.flatpaksExpanded = expanded
            UpdatesService.shellExpanded = expanded
        }
        // The shell's own check, offline (local git only, no network).
        function checkShell(): void { UpdatesService.checkShell(true, false) }
        // Counts only, no package names.
        function get(): string {
            return JSON.stringify({ checking: UpdatesService.checking, packagesKnown: UpdatesService.result.packagesKnown,
                                    packages: UpdatesService.packages.length, security: UpdatesService.securityCount,
                                    flatpaks: UpdatesService.flatpaks.length, userFlatpaks: UpdatesService.userFlatpakCount,
                                    lastCheck: UpdatesService.lastCheck, message: UpdatesService.message,
                                    offline: UpdatesService.result.offline, realSession: UpdatesService.realSession,
                                    preview: UpdatesService.preview, checkHours: UpdatesService.checkHours,
                                    notify: UpdatesService.notifyEnabled,
                                    core: UpdatesService.corePackages.length, news: UpdatesService.news.length,
                                    pacnew: UpdatesService.pacnew.length, coreCheck: UpdatesService.coreCheck,
                                    whatsNew: UpdatesService.whatsNew,
                                    shell: { known: UpdatesService.shell.known, repo: UpdatesService.shell.repo,
                                             behind: UpdatesService.shell.behind, ahead: UpdatesService.shell.ahead,
                                             dirty: UpdatesService.shell.dirty, updatable: UpdatesService.shellUpdatable,
                                             checking: UpdatesService.shellChecking, auto: UpdatesService.shellAuto } })
        }
    }

    IpcHandler {
        target: "snapshots"
        // The copies of the whole setup (Settings > Profiles > Backups): names,
        // kinds, times and counts, read anew with refresh.
        function refresh(): void { SnapshotService.refresh() }
        function get(): string {
            return JSON.stringify({ listed: SnapshotService.listed, busy: SnapshotService.busy, working: SnapshotService.working,
                                    message: SnapshotService.message, takenDay: SnapshotService.takenDay,
                                    automatic: SnapshotService.automatic, snapshots: SnapshotService.snapshots })
        }
        // A copy now; the day's one as the first write of a day takes it.
        function take(): bool { return SnapshotService.takeNow() }
        function daily(): void { SnapshotService.beforeWrite() }
        // A listed copy back after keeping one of now; the shell restarts
        // when anything was written. Never an import: that is a file the
        // user picks.
        function restore(name: string): bool { return SnapshotService.restore(name) }
    }

    IpcHandler {
        target: "health"
        // session-check.sh and doctor.sh in their --json modes, read-only, as
        // Settings > About runs them, and what the shell knows on top.
        function check(): void { HealthService.check(true) }
        // Levels, sections, texts and actions; whether a command is there, not the command.
        function get(): string {
            return JSON.stringify({ running: HealthService.running, lastRun: HealthService.lastRun, summary: HealthService.summary,
                                    items: HealthService.items.map(item => ({ id: item.id, level: item.level, section: item.section,
                                                                              text: item.text, action: item.action,
                                                                              command: item.command.length > 0 })) })
        }
    }

    IpcHandler {
        id: recordingIpc
        target: "recording"
        // MODE: region, screen or window. Region selection runs slurp.
        function start(mode: string): bool { return RecordingService.start(mode) }
        function toggle(mode: string): void { RecordingService.toggle(mode) }
        function stop(): bool { return RecordingService.stop() }
        // Synthetic running recording for screenshots; nothing is recorded.
        function preview(): void { RecordingService.showPreview() }
        function stopPreview(): void { RecordingService.stopPreview() }
        function get(): string {
            return JSON.stringify({ active: RecordingService.active, preview: RecordingService.preview,
                                    mode: RecordingService.mode, elapsed: RecordingService.elapsedText,
                                    busy: RecordingService.busy, backend: RecordingService.backend,
                                    backendsKnown: RecordingService.backendsKnown, backends: RecordingService.backends,
                                    audio: RecordingService.audio, fps: RecordingService.fps,
                                    lastError: RecordingService.lastError,
                                    lastFile: RecordingService.lastFileName,
                                    realSession: RecordingService.realSession })
        }
    }

    IpcHandler {
        id: shortcutsIpc
        target: "shortcuts"
        // Super+F1: the read-only sheet of every combination.
        function toggleSheet(): void { PanelService.toggle("shortcutSheet") }
        function openSheet(): void { PanelService.open("shortcutSheet") }
        function closeSheet(): void { PanelService.close("shortcutSheet") }
        function refresh(): void { ShortcutService.sync() }
        // Modifiers joined with "+" ("SUPER+SHIFT", "" for none); returns "" or the error.
        function addCommand(mods: string, key: string, command: string): string {
            return ShortcutService.add({ mods: mods.split("+").filter(mod => mod.length), key: key, command: command })
        }
        function addApp(mods: string, key: string, app: string): string {
            return ShortcutService.add({ mods: mods.split("+").filter(mod => mod.length), key: key, app: app })
        }
        function remove(mods: string, key: string): void {
            ShortcutService.remove({ mods: mods.split("+").filter(mod => mod.length), key: key })
        }
        function get(): string {
            return JSON.stringify({ binds: ShortcutService.binds.length, custom: ShortcutService.custom.map(entry => ShortcutService.comboOf(entry)),
                                    conflicts: ShortcutService.conflicts, applying: ShortcutService.applying })
        }
    }

    IpcHandler {
        target: "nightLight"
        function toggle(): void { NightLightService.toggle() }
        function get(): string {
            return JSON.stringify({ mode: NightLightService.mode, active: NightLightService.active, running: NightLightService.running,
                                    summary: NightLightService.summary })
        }
    }

    IpcHandler {
        target: "focus"
        function toggle(): void { AdaptiveService.setFocus(!AdaptiveService.focusActive) }
        function set(active: bool): void { AdaptiveService.setFocus(active) }
        function get(): bool { return AdaptiveService.focusActive }
        // A Focus session: Focus now, and off again with a ring after the
        // time ("25m", "1h", "45" minutes) - `buchhwin focus start 25m`.
        function start(duration: string): bool { return AdaptiveService.focusForText(duration) }
        // Whether Focus is on, whether a session runs, its seconds left and
        // what the control center's tile says.
        function session(): string {
            const ends = AdaptiveService.focusEndsAt
            return JSON.stringify({ active: AdaptiveService.focusActive, session: AdaptiveService.focusSession,
                                    remaining: ends > 0 ? Math.max(0, Math.ceil((ends - Date.now()) / 1000)) : 0,
                                    label: AdaptiveService.focusLabel })
        }
    }

    IpcHandler {
        id: overviewIpc
        target: "overview"
        function toggle(): void { PanelService.toggle("overview") }
        function open(): void { PanelService.open("overview") }
        function close(): void { PanelService.close("overview") }
    }

    // The dock (shell/dock/Dock.qml, DockService). `toggle` is Super+Shift+D:
    // an off dock is switched on, one the key showed goes again, any other is
    // shown with the keyboard on it. `get` and `rects` are counts, flags and
    // places - never an app's name or a window's title.
    IpcHandler {
        id: dockIpc
        target: "dock"
        function toggle(): void {
            const result = DockService.toggleFromKey()
            if (result === "on") osd.showMessage("Dock on", Icons.dock)
            // A fullscreen window hides the dock; the key changes nothing then
            // (DockService), and says so instead of seeming to do nothing.
            else if (result === "fullscreen") osd.showMessage("No dock over fullscreen", Icons.dock)
        }
        function reveal(): void { DockService.reveal() }
        function conceal(): void { DockService.conceal() }
        function setEnabled(on: bool): bool { return SettingsService.set("dock.enabled", on) }
        function setOption(key: string, value: string): bool {
            const parsed = DockLogic.optionValue(key, value)
            return parsed !== null && SettingsService.set("dock." + key, parsed)
        }
        // A shipped preset (taskbar, dock): layout, pins and options at once.
        function preset(name: string): bool { return LayoutService.applyDockPreset(name) }
        // By index, as `rects` lists them.
        // An index into the focused dock's own list: the same as
        // DockService.items unless dock.runningOn is "screen".
        function activate(index: int): bool {
            const name = DockLogic.revealTarget(DockService.focusedName(), DockService.screenNames)
            const app = DockService.itemsOn(name)[index]
            return app ? DockService.activate(app.key, name) : false
        }
        function menu(index: int): bool {
            const name = DockLogic.revealTarget(DockService.focusedName(), DockService.screenNames)
            const app = DockService.itemsOn(name)[index]
            const list = DockService.rectsOn[name] || []
            return app && list[index] ? DockService.openMenu(app.key, name, list[index]) : false
        }
        function rects(): string { return DockService.describeRects() }
        function get(): string { return DockService.describe() }
    }

    IpcHandler {
        id: gesturesIpc
        target: "gestures"
        // Called by touchpad gestures: overview, launcher, dashboard,
        // controlCenter, notifications, clipboard (toggle) or closePanel -
        // over IPC in the conf dialect, as the global shortcut
        // `buchhwin:gestures.run.<name>` in the Lua one.
        function run(name: string): bool { return GestureService.run(name) }
        function refresh(): void { GestureService.refreshDevices() }
        // Show Settings > Input > Touchpad gestures without a touchpad.
        function preview(): void { GestureService.preview = true }
        function stopPreview(): void { GestureService.preview = false }
        function get(): string { return GestureService.describe() }
    }

    IpcHandler {
        id: colorPickerIpc
        target: "colorPicker"
        // The list, and the pick itself. `pick` opens the overlay; what it
        // lands on is the pointer's business, so there is nothing to pass.
        function toggle(): void { PanelService.toggle("colorPicker") }
        function open(): void { PanelService.open("colorPicker") }
        function close(): void { PanelService.close("colorPicker") }
        function pick(): void { PanelService.close("colorPicker"); ColorPickerService.open() }
        function cancel(): void { ColorPickerService.close() }
        // Counts and state only: a picked colour is the user's, and the list
        // of them says what they have been looking at.
        function get(): string {
            return JSON.stringify({ open: PanelService.isOpen("colorPicker"),
                                    picking: ColorPickerService.active,
                                    ready: ColorPickerService.ready,
                                    screens: ColorPickerService.frames.length,
                                    history: ColorPickerService.history.length })
        }
    }

    IpcHandler {
        id: wallpaperPickerIpc
        target: "wallpaperPicker"
        function toggle(): void { PanelService.toggle("wallpaperPicker") }
        function open(): void { PanelService.open("wallpaperPicker") }
        function close(): void { PanelService.close("wallpaperPicker") }
        // Counts only: no file names or paths.
        function get(): string {
            return JSON.stringify({ open: PanelService.isOpen("wallpaperPicker"),
                                    images: WallpaperService.images.length,
                                    favourites: WallpaperService.favourites.length,
                                    themePair: WallpaperService.themePair, themeSide: WallpaperService.themeSide })
        }
    }

    IpcHandler {
        id: switcherIpc
        target: "switcher"
        function next(): void { SwitcherService.next() }
        function previous(): void { SwitcherService.previous() }
        function confirm(): void { SwitcherService.confirm() }
        function cancel(): void { SwitcherService.cancel() }
        function get(): string { return SwitcherService.describe() }
    }

    IpcHandler {
        id: clipboardIpc
        target: "clipboard"
        function toggle(): void { PanelService.toggle("clipboard") }
        function open(): void { PanelService.open("clipboard") }
        function close(): void { PanelService.close("clipboard") }
        function get(): string {
            return JSON.stringify({ enabled: ClipboardService.enabled, entries: ClipboardService.entries.length,
                                    pinned: ClipboardService.pins.length, pinsRead: ClipboardService.pinsRead })
        }
        // Pin the history's N-th entry (0 the newest, as the panel lists them;
        // the history is read when the panel opens), or unpin the N-th pin.
        function pin(index: int): bool { return ClipboardService.pinAt(index) }
        function unpin(index: int): bool { return ClipboardService.unpinAt(index) }
    }

    // The assistant panel (shell/assistant): Ollama on this computer, never
    // another machine. `ask` opens it and asks (the question waits for the
    // model list when that is not there yet); `get` is counts and states,
    // never a question, an answer or a model's name.
    IpcHandler {
        id: assistantIpc
        target: "assistant"
        function toggle(): void { PanelService.toggle("assistant") }
        function open(): void { PanelService.open("assistant") }
        function close(): void { PanelService.close("assistant") }
        function ask(text: string): bool {
            PanelService.open("assistant")
            return AssistantService.ask(text)
        }
        function stop(): void { AssistantService.stop() }
        function clear(): void { AssistantService.clear() }
        function refresh(): void { AssistantService.refresh() }
        function get(): string { return AssistantService.describe() }
    }

    // The share picker (shell/sharepicker) for xdg-desktop-portal-hyprland:
    // scripts/share-picker.sh hands a request in (DIR: its private directory
    // under $XDG_RUNTIME_DIR/buchhwin-shell/share-picker, nowhere else) and
    // waits for the answer on a FIFO there; "opened" or why not. `open` is the
    // preview Settings has a button for (a choice in it shares nothing);
    // `get` is counts and flags, never a title.
    IpcHandler {
        id: sharePickerIpc
        target: "sharePicker"
        function request(dir: string, allowToken: bool): string { return SharePickerService.take(dir, allowToken) }
        function cancel(dir: string): bool { return SharePickerService.cancel(dir) }
        function open(): bool { return SharePickerService.openPreview() }
        function close(): void { PanelService.close("sharePicker") }
        function get(): string { return SharePickerService.describe() }
    }

    IpcHandler {
        id: brightnessIpc
        target: "brightness"
        // The brightness keys: one 5 % step through brightnessctl, then the
        // re-read (BrightnessService.step). The conf dialect's binds call
        // these over IPC, the Lua binds as global shortcuts.
        function up(): void { BrightnessService.step(1) }
        function down(): void { BrightnessService.step(-1) }
        // A change made outside the shell is seen through the udev monitor
        // (BrightnessService), after its debounce; this is the read at once.
        function refresh(): void { BrightnessService.refresh() }
        // Shows a level (0-1) without writing it, so the OSD can be seen in a
        // nested session: the backlight belongs to the host, as the keyboard
        // light does (kbdBacklight preview), and a test must never drive it.
        // `refresh` puts the truth back.
        function preview(value: real): void {
            if (!BrightnessService.available || !isFinite(value)) return
            BrightnessService.current = Math.round(Math.max(0, Math.min(1, value)) * BrightnessService.maximum)
        }
        // The external screens' brightness over DDC/CI (BrightnessService): ask
        // them now, or set one by its connector name (0-1). A nested shell runs
        // ddcutil only as the stand-in BUCHHWIN_DDCUTIL names.
        function detect(): void { BrightnessService.ddcDetect() }
        function setDisplay(name: string, value: real): bool { return BrightnessService.setDdc(name, value) }
        function get(): string {
            return JSON.stringify({ available: BrightnessService.available, value: BrightnessService.value,
                                    ddc: BrightnessService.ddcState, displays: BrightnessService.ddcSummary() })
        }
    }

    IpcHandler {
        id: workspacesIpc
        target: "workspaces"
        // `Super+N` and `Super+Shift+N` come here rather than dispatching a
        // plain `workspace N`, because only the shell knows which monitor has
        // the focus - and with workspaces per monitor, N means "the Nth of
        // that monitor". The binds keep a `|| hyprctl dispatch` tail, so a
        // session without a running shell still switches the old way.
        function switchTo(local: int): void { HyprlandService.switchLocal(local) }
        function move(local: int): void { HyprlandService.moveLocal(local) }
        // The neighbouring workspace of the monitor under the focus - the pip
        // beside the lit one, one new one past the last (Super+Page Up/Down;
        // HyprlandService.stepWorkspace) - and with the window along
        // (Super+Shift+Page Up/Down). The wheel's binds have a function of
        // their own, "down" or "up": checks.py binds holds an action to one
        // combination.
        function next(): void { HyprlandService.stepWorkspace(1) }
        function previous(): void { HyprlandService.stepWorkspace(-1) }
        function moveNext(): void { HyprlandService.stepWindow(1) }
        function movePrevious(): void { HyprlandService.stepWindow(-1) }
        function scroll(direction: string): void { HyprlandService.stepWorkspace(direction === "up" ? -1 : 1) }
        function get(): string {
            return JSON.stringify({ perMonitor: HyprlandService.perMonitor,
                                    focusedMonitor: HyprlandService.focusedMonitorName,
                                    order: HyprlandService.monitorList.map(m => m.name),
                                    active: HyprlandService.monitorList.map(m =>
                                        m.name + ":" + HyprlandService.activeWorkspaceOn(m.name)),
                                    offsets: HyprlandService.monitorList.map(m =>
                                        m.name + ":" + HyprlandService.offsetFor(m.name)),
                                    keepEmpty: HyprlandService.keepsEmpty,
                                    held: Object.keys(HyprlandService.keptOn).map(Number).sort((a, b) => a - b),
                                    holdLimit: HyprlandService.holdLimit() })
        }
        // Empty workspaces held open (Settings > Bar & notch, "Keep empty
        // workspaces open"; the profile's setting), switched while the shell
        // runs: the smoke test turns it on and off around a step of its own,
        // where a seeded settings.json would hold workspaces for every other
        // step too (testing.md pitfall 102).
        function setKeepEmpty(on: bool): bool { return SettingsService.set("workspaces.keepEmpty", on) }
    }

    // The screen zoom (Super and + / - / 0; ScreenEffectsService): one step
    // in or out along its ladder, back to 100 %, or a factor of 1 to 8 - with
    // the OSD saying when it is off again.
    IpcHandler {
        id: zoomIpc
        target: "zoom"
        function increase(): void { ScreenEffectsService.zoomBy(1); root.zoomOsd() }
        function decrease(): void { ScreenEffectsService.zoomBy(-1); root.zoomOsd() }
        function reset(): void { ScreenEffectsService.resetZoom(); root.zoomOsd() }
        function set(factor: real): void { ScreenEffectsService.setZoom(factor); root.zoomOsd() }
        function get(): string {
            return JSON.stringify({ factor: ScreenEffectsService.zoom, zoomed: ScreenEffectsService.zoomed })
        }
    }
    // Only once the zoom is off: Hyprland zooms around the pointer, and the
    // message at the bottom of the screen was zoomed off it by the very zoom
    // it reported (half gone at 1.25×, gone from 1.5×). The zoom itself is
    // the answer to the keys; the control center's tile says the factor.
    function zoomOsd() {
        if (!ScreenEffectsService.zoomed) osd.showMessage("Zoom off", "󰍊")
    }

    // The color filters (Super+Ctrl+C, Settings > Appearance;
    // ScreenEffectsService): the chosen one on and off, one by its name
    // (grayscale, deuteranopia, protanopia, tritanopia, invert), the next one.
    IpcHandler {
        id: colorFilterIpc
        target: "colorFilter"
        function toggle(): void { ScreenEffectsService.toggleFilter(); root.filterOsd() }
        function enable(name: string): bool {
            const done = ScreenEffectsService.setFilter(name)
            if (done) root.filterOsd()
            return done
        }
        function off(): void { ScreenEffectsService.setFilterOn(false); root.filterOsd() }
        function cycle(): void { ScreenEffectsService.cycleFilter(); root.filterOsd() }
        function get(): string {
            return JSON.stringify({ on: ScreenEffectsService.filterOn, filter: ScreenEffectsService.filter })
        }
    }
    function filterOsd() {
        osd.showMessage(ScreenEffectsService.filterOn ? ScreenEffectsService.filterLabel : "Color filter off", "󰌁")
    }

    // A window kept on top (Super+Ctrl+T, the dock's menu): floated if it is
    // tiled, then pinned; again to let it go (HyprlandService.keepOnTop). The
    // active window, or the one at `address` (hyprctl's, with or without 0x).
    IpcHandler {
        id: windowIpc
        target: "window"
        function keepOnTop(): void { HyprlandService.keepOnTop("") }
        function keepOnTopAt(address: string): void { HyprlandService.keepOnTop(address) }
        // Super+C: floating at a size of its own, centred, or back into the
        // layout (HyprlandService.toggleFloating).
        function toggleFloating(): void { HyprlandService.toggleFloating("") }
        // Minimize and restore (services/MinimizeService.qml): Super+H, Super+Shift+H,
        // the dock, the overview and Alt+Tab. `minimized` is counts and flags only.
        function minimize(): bool { return MinimizeService.minimizeActive() }
        function restore(): bool { return MinimizeService.restoreLast() }
        function restoreAll(): int { return MinimizeService.restoreAll() }
        function minimizeWindow(address: string): bool { return MinimizeService.minimize(address) }
        function restoreWindow(address: string): bool { return MinimizeService.restore(address, true, 0) }
        function minimized(): string { return MinimizeService.describe() }
    }

    // The drop-down terminal (Super+^): started the first time, shown or put
    // away after that (HyprlandService.toggleDropdown).
    IpcHandler {
        id: dropdownIpc
        target: "dropdown"
        function toggle(): void { HyprlandService.toggleDropdown() }
        function get(): string { return JSON.stringify({ open: HyprlandService.dropdownOpen() }) }
    }

    // The keyboard passthrough (Super+Esc in and out; HyprlandService): every
    // key to the window in front until it is left. `leave` is the way out
    // from a script, and works whoever went in.
    IpcHandler {
        target: "passthrough"
        function enter(): void { HyprlandService.setPassthrough(true) }
        function leave(): void { HyprlandService.setPassthrough(false) }
        function toggle(): void { HyprlandService.setPassthrough(!HyprlandService.passthrough) }
        function get(): string {
            return JSON.stringify({ active: HyprlandService.passthrough, auto: HyprlandService.passthroughAuto,
                                    byShell: HyprlandService.passByShell })
        }
    }

    // A Citrix session over the desk's screens side by side (the launcher,
    // Settings > Shortcuts): a floating window as large as the external
    // screens together, and back into the layout. The OSD says what came of it.
    IpcHandler {
        target: "citrix"
        function span(): void { HyprlandService.spanCitrix() }
        function unspan(): void { HyprlandService.unspanCitrix() }
        function get(): string { return JSON.stringify(HyprlandService.spanReport()) }
    }
    Connections {
        target: HyprlandService
        function onSpanFinished(message: string, ok: bool) { osd.showMessage(message, "󰍺") }
    }

    IpcHandler {
        id: kbdBacklightIpc
        target: "kbdBacklight"
        // The keyboard-light keys come here rather than running brightnessctl
        // themselves, because the LED's name carries its driver's prefix
        // (tpacpi, asus, dell, smc) and a key binding cannot know it. The
        // service finds the device; this only says which way.
        function up(): void { KbdBacklightService.nudge(1) }
        function down(): void { KbdBacklightService.nudge(-1) }
        function toggle(): void { KbdBacklightService.nudge(0) }
        // The LED class sends no udev event, so anything that changes the
        // light behind the shell's back has to say so.
        function refresh(): void { KbdBacklightService.refresh() }
        // Shows a step without writing it, so the OSD can be seen in a nested
        // session: the LED belongs to the host and a test must never drive it.
        // `refresh` puts the truth back.
        function preview(level: int): void { KbdBacklightService.current = level }
        function get(): string {
            return JSON.stringify({ available: KbdBacklightService.available, device: KbdBacklightService.device,
                                    current: KbdBacklightService.current, maximum: KbdBacklightService.maximum,
                                    label: KbdBacklightService.label, segments: KbdBacklightService.segments })
        }
    }

    IpcHandler {
        target: "power"
        function lidClosed(): void { IdleService.lidClosed() }
        function lidOpened(): void { IdleService.lidOpened() }
        function setStayAwake(value: bool): void { IdleService.stayAwake = value }
        // off, 1h, unplug (only with a charger in) or manual; false when it
        // cannot start now. Not remembered as the quick switches' choice.
        function stayAwake(mode: string): bool { return IdleService.holdAwake(mode) }
        // The battery popup's switch and the control center's tile.
        function toggleStayAwake(): bool { return IdleService.toggleStayAwake() }
        // The charge limit through UPower, real session only (false when
        // refused: no UPower support, a nested session, a change running).
        function setChargeLimit(on: bool): bool { return PowerService.setChargeLimit(on) }
        function chargeOnce(): bool { return PowerService.chargeOnce() }
        function cancelChargeOnce(): bool { return PowerService.cancelChargeOnce() }
        function refreshChargeLimit(): void { PowerService.refreshChargeLimit() }
        // Lighter effects as if their power source applied: keep, light, or
        // "" to follow the source again - for a nested session, which cannot
        // unplug the host.
        function previewEffects(value: string): void {
            PowerService.effectsPreview = ["keep", "light"].indexOf(value) >= 0 ? value : ""
        }
        // Which source Settings > Power edits: battery, ac or "" (the active one).
        function showSource(name: string): void { PowerService.pageSource = ["battery", "ac"].indexOf(name) >= 0 ? name : "" }
        function get(): string {
            const settings = name => ({ screenOff: PowerService.sourceValue(name, "screenOffMinutes"), lock: PowerService.sourceValue(name, "lockMinutes"),
                                        suspend: PowerService.sourceValue(name, "suspendMinutes"), dim: PowerService.sourceValue(name, "dimBeforeScreenOff"),
                                        lid: PowerService.sourceValue(name, "lidAction"), profile: PowerService.sourceValue(name, "profile"),
                                        effects: PowerService.sourceValue(name, "effects") })
            return JSON.stringify({ source: PowerService.source, hasBattery: PowerService.hasBattery,
                                    screenOff: IdleService.screenOffMinutes, lock: IdleService.lockMinutes, suspend: IdleService.suspendMinutes,
                                    dim: IdleService.dimBeforeScreenOff, lid: IdleService.lidAction, profileChoice: PowerService.profileChoice,
                                    lockBeforeSleep: IdleService.lockBeforeSleep, lidClosed: DisplayService.lidClosed,
                                    stayAwake: IdleService.stayAwake, stayAwakeMode: IdleService.stayAwakeMode,
                                    stayAwakeLeft: IdleService.stayAwakeSubtitle, stayAwakeLimit: IdleService.stayAwakeLimit,
                                    chargeLimit: PowerService.chargeLimit, chargeLimitLabel: PowerService.chargeLimitLabel,
                                    chargeOnce: PowerService.chargeOnceActive, chargeWritable: PowerService.chargeWritable,
                                    chargeError: PowerService.chargeLimitError, stateLabel: PowerService.stateLabel,
                                    lightEffects: PowerService.lightEffects, animationMode: Animations.mode,
                                    realSession: IdleService.realSession,
                                    battery: settings("battery"), ac: settings("ac") })
        }
    }

    IpcHandler {
        id: displaysIpc
        target: "displays"
        function get(): string {
            return JSON.stringify({ dirty: DisplayService.dirty, confirming: DisplayService.confirming, countdown: DisplayService.countdown,
                                    // Which Hyprland dialect the shell settled on. A wrong guess here
                                    // is silent and total - every keyword is rejected for the life of
                                    // the session - so it is worth being able to read it.
                                    dialect: HyprCompat.dialect,
                                    monitors: DisplayService.monitors.map(m => m.name + " " + m.width + "x" + m.height + "@" + Math.round(m.refresh)
                                        + " " + m.x + "," + m.y + " x" + m.scale + " t" + m.transform + (m.disabled ? " off" : "")
                                        + (m.mirror ? " mirror:" + m.mirror : "")),
                                    // The edited copy as well as the live state. Without it the
                                    // only way to see what a drag or an arrow-key nudge did was
                                    // to read a row on the page, which a nested test cannot.
                                    draft: DisplayService.draft.map(m => m.name + " " + m.x + "," + m.y
                                        + " x" + m.scale + " t" + m.transform + (m.disabled ? " off" : "")
                                        + (m.mirror ? " mirror:" + m.mirror : "")),
                                    // The display switcher: what the screens do now (internal, duplicate,
                                    // extend, external), the choice in force ("" for none), the mirrors.
                                    projection: DisplayService.currentProjection, projectionHeld: DisplayService.projection,
                                    mirrors: DisplayService.mirrorNames })
        }
        // A scale a saved file may ask for too (DisplayLogic.validScale,
        // 0.5-3): `Number()` alone let NaN or 0 through into the draft, and
        // from there into the monitor rule.
        function setScale(name: string, scale: string): void {
            if (DisplayLogic.validScale(scale)) DisplayService.setScale(name, scale)
        }
        function setPosition(name: string, x: int, y: int): void { DisplayService.setPosition(name, x, y) }
        function setTransform(name: string, transform: int): void { DisplayService.setTransform(name, transform) }
        // Not `show()`: the client takes that word for itself.
        function identify(): void { DisplayService.identify() }
        function apply(): bool { return DisplayService.apply() }
        function keep(): bool { return DisplayService.keep() }
        function revert(): bool { return DisplayService.revert() }
        // The display switcher (Super+Shift+P): open, or closed again.
        function toggleSwitcher(): void { PanelService.toggle("displaySwitcher") }
        // The projector key (XF86Display): open, or with the switcher open the
        // next choice - as Windows' Win+P.
        function key(): void {
            if (PanelService.active === "displaySwitcher") DisplayService.stepSwitcher()
            else PanelService.open("displaySwitcher")
        }
        // One of the switcher's choices at once: internal, duplicate, extend or
        // external (ProjectionLogic). False where it cannot be made.
        function setProjection(mode: string): bool { return DisplayService.setProjection(mode) }
        // Settings > Displays' Mirror into the draft ("" for none); apply and
        // keep as for the rest of the page.
        function setMirror(name: string, source: string): bool { return DisplayService.setMirror(name, source) }
    }

    IpcHandler {
        target: "bar"
        function setMode(mode: string): bool { return LayoutService.setDesktopMode(mode) }
        function addPill(zone: string, type: string): bool { return LayoutService.barAddPill(zone, type, "") }
        // Keys: reserve true|false, fullscreen hide|show, scale 0.9|1|1.15,
        // style pills|bar, position floating|attached, edge top|bottom|left|
        // right, panelSpot and notificationSpot widget|start|centre|end.
        function setOption(key: string, value: string): bool {
            // 0.7-1.5, the range the bar clamps its scale to when the layout
            // is read (LayoutLogic.sanitizeBar): refused here rather than
            // stored as NaN or clamped silently.
            if (key === "scale") {
                const number = Number(value)
                if (!isFinite(number) || number < 0.7 || number > 1.5) return false
                return LayoutService.setBarOption("scale", number)
            }
            return LayoutService.setBarOption(key, key === "reserve" ? value === "true" : value)
        }
        function reset(): bool { return LayoutService.resetBar() }
        // Workspace indicator: mode "open", "gapless" or "fixed", 1–10 slots.
        // Both or neither: the mode used to be stored before a count out of
        // range was refused.
        function setWorkspaces(mode: string, count: int): bool {
            const values = { "workspaces.mode": mode, "workspaces.count": count }
            return IpcLogic.allAllowed(values, SettingsService.allowed) && SettingsService.setAll(values)
        }
        // How the pips are drawn, which is a separate question from which
        // workspaces are shown.
        function setWorkspaceStyle(style: string): bool {
            return SettingsService.set("workspaces.style", style)
        }
        function get(): string {
            const bar = LayoutService.bar
            const describe = zone => bar[zone].map(pill => pill.items.map(item => item.type + (item.display === "icon" ? "*" : "")).join("+"))
            return JSON.stringify({ mode: LayoutService.desktopMode, reserve: bar.reserve, fullscreen: bar.fullscreen, scale: bar.scale,
                                    style: bar.style, position: bar.position, edge: bar.edge,
                                    left: describe("left"), center: describe("center"), right: describe("right") })
        }
    }

    IpcHandler {
        target: "notch"
        // Nested sessions cannot hover: expand the notch on the focused
        // screen like a hover, collapse it again.
        function expand(): void {
            const screen = PanelService.focusedScreen()
            if (screen) NotchService.expand(screen.name)
        }
        function collapse(): void { NotchService.collapse() }
        // Synthetic now-playing row for screenshots; controls stay disabled.
        function previewMedia(enabled: bool): void { NotchService.mediaPreview = enabled }
        function setOption(key: string, value: string): bool {
            if (["fullscreen", "hoverMode", "clickAction", "middleAction", "rightAction", "panelOrigin", "osdStyle", "accentGlyphs"].indexOf(key) >= 0)
                return SettingsService.set("notch." + key, value)
            // The delays (openDelay 0-1000, closeDelay 0-2000 ms) and the
            // collapsed body (bodyHeight 24-64, bodyRadius 0-32, bodyPadding
            // 0-48): the ranges the notch clamps to, so a value outside them
            // is refused here rather than stored and silently clamped
            // (NotchLogic.optionNumber).
            if (NotchLogic.optionRange(key) !== null) {
                const number = NotchLogic.optionNumber(key, value)
                return number !== null && SettingsService.set("notch." + key, number)
            }
            if (key === "reserve") return SettingsService.set("notch.reserve", value === "true")
            if (key === "swipe") return SettingsService.set("notch.swipe", value === "true")
            // The form (notch or pill), the editor's switch: one undo step.
            if (key === "shape") return SettingsService.allowed["notch.shape"].indexOf(value) >= 0
                && LayoutService.changeNotch("notch.shape", value) !== false
            // The switch this replaced, for scripts written against it.
            if (key === "expandOnHover") return SettingsService.set("notch.hoverMode", value === "true" ? "hover" : "click")
            return false
        }
        // A built-in ("island") or saved preset, by id; one undo step.
        function applyPreset(id: string): bool { return LayoutService.applyNotchPreset(id) }
        // Mode, settings and per screen what is shown (row ids and sizes, no titles).
        function get(): string { return NotchService.describe() }
    }

    IpcHandler {
        target: "timer"
        // A countdown in the notch: "5m", "90s", "1h30m", "1:30" or minutes.
        function start(duration: string): bool { return TimerService.startText(duration) }
        // The timer, and a Focus session only when no timer runs.
        function stop(): void { TimerService.stopTimer() }
        // Running, and the seconds left of the one shown; what it counts
        // ("timer" or "focus") and every run with its seconds left. No label,
        // there is none.
        function get(): string {
            return JSON.stringify({ running: TimerService.running, remaining: Math.ceil(TimerService.remaining / 1000),
                                    kind: TimerService.kind, runs: TimerService.describe() })
        }
    }

    IpcHandler {
        id: audioIpc
        target: "audio"
        // The volume keys (hypr/hyprland.lua sends them as global shortcuts;
        // the conf dialect keeps wpctl): one 5 % step of the default output,
        // up to 100 % as wpctl's -l 1.0 keeps it, and the two mutes. Without
        // a bound default node yet, wpctl does it as before.
        function up(): void { if (!AudioService.stepVolume(AudioService.sink, 0.05)) Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "5%+"]) }
        function down(): void { if (!AudioService.stepVolume(AudioService.sink, -0.05)) Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]) }
        function mute(): void { if (AudioService.sink && AudioService.sink.audio) AudioService.toggleMute(AudioService.sink); else Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) }
        // The microphone key: every microphone, and pressed again the ones it
        // muted (AudioService.micKey; with one microphone or the setting off,
        // the default as before, wpctl without a bound node).
        function micMute(): void { AudioService.micKey() }
        // Push to talk (Super+T held): the default microphone on while the key
        // is down, back the way it was when it is let go. The shortcut passes
        // the key's edge (ShellShortcuts.HOLD).
        function talk(down: bool): void { AudioService.pushToTalk(down) }
        // Route an app stream (node id) to a sink, by its id (as `get` lists
        // them) or its node.name; "default" resets.
        function route(stream: string, sink: string): bool {
            const node = AudioService.playbackStreams.find(item => String(item.id) === stream)
            const target = sink === "default" ? null : IpcLogic.sinkFor(sink, AudioService.sinkInfo)
            if (!node || (sink !== "default" && !target)) return false
            AudioService.routeStream(node, target ? target.name : "")
            return true
        }
        // Stream and sink ids, a stream's target as its sink's id: no app
        // names, and no node names - a Bluetooth sink's carries the
        // headphones' address (IpcLogic.sinkIds).
        function get(): string {
            const sinks = AudioService.sinkInfo
            return JSON.stringify({ ready: AudioService.ready, sinkCount: sinks.length, sinks: IpcLogic.sinkIds(sinks),
                                    streams: AudioService.playbackStreams.map(item => ({
                                        id: item.id, target: IpcLogic.sinkIdOf(AudioService.streamTarget(item), sinks) })),
                                    routingTrackers: AudioService.routingTrackers, meterTrackers: AudioService.meterTrackers,
                                    meterRunning: AudioService.meterRunning, micInUse: AudioService.micInUse,
                                    level: AudioService.inputLevel, talking: AudioService.talking,
                                    sources: AudioService.sources.length, micKeyAll: AudioService.micKeyAll,
                                    micMuted: AudioService.micMuted })
        }
    }

    IpcHandler {
        // The five: minimal, work, gaming, laptop and docked. This is what
        // `profile` did before v3; `profile` is the level above now, and
        // `profile cycle` stays as an alias so nothing that exists breaks.
        id: modeIpc
        target: "mode"
        function set(name: string): bool { return LayoutService.setActiveMode(name) }
        function get(): string { return LayoutService.activeMode }
        function list(): string { return LayoutService.modeNames.join(" ") }
        // There are five modes and, until this key, none at all: they could
        // only be changed in Settings, in the editor or from the launcher.
        // Cycling by hand also settles the automatic mode - see ProfileLogic,
        // the rule is the user's.
        function cycle(): string { return root.cycleMode() }
    }

    // Everything the mode key does, in one place: the IPC target above and the
    // `profile cycle` alias below both call it, and `Super+Alt+P` goes through
    // the alias.
    function cycleMode(): string {
        const step = Profile.cycleMode(LayoutService.activeMode, LayoutService.modeNames,
                                       SettingsService.value("desktop.autoProfile"), AdaptiveService.autoOwned)
        // Do Not Disturb before the switch: a mode can turn it on, and leaving
        // it off again, and nothing else on screen says so.
        const dndBefore = { active: NotificationService.dndActive, by: NotificationService.dndBy }
        if (!step || !LayoutService.setActiveMode(step.mode)) return LayoutService.activeMode
        if (step.autoChanged) SettingsService.set("desktop.autoProfile", step.auto)
        const dnd = Profile.dndChange(dndBefore, { active: NotificationService.dndActive, by: NotificationService.dndBy },
                                      step.mode)
        osd.showMessage(Profile.osdText(Profile.label(step.mode, LayoutService.templates), step, dnd),
                        Profile.icon(step.mode))
        return step.mode
    }

    IpcHandler {
        // The level above: a profile holds its own five modes. Adding,
        // duplicating, renaming, removing and resetting are here too, because a
        // profile is the one thing in the layout file with no fixed set of
        // names - it is the user's list.
        id: profileIpc
        target: "profile"
        function set(name: string): bool { return LayoutService.setActiveProfile(name) }
        function get(): string { return LayoutService.activeProfile }
        // Where the automatic switching goes and where it would go now: mode
        // names only.
        function automatic(): string {
            return JSON.stringify({ on: SettingsService.value("desktop.autoProfile") === true, targets: AdaptiveService.autoTargets,
                                    suggested: AdaptiveService.suggestedMode, mode: LayoutService.activeMode,
                                    laptop: AdaptiveService.hasInternal })
        }
        function list(): string { return LayoutService.profileNames.join(" ") }
        // `Super+P`. The two levels small enough to be a key.
        function toggle(): void { PanelService.toggle("profilePopup") }
        function add(label: string): string { return LayoutService.addProfile(label) }
        function duplicate(name: string, label: string): string { return LayoutService.duplicateProfile(name, label) }
        function rename(name: string, label: string): bool { return LayoutService.renameProfile(name, label) }
        function remove(name: string): bool { return LayoutService.removeProfile(name) }
        // With no mode named, all five of them. A built-in profile resets to
        // the modes it shipped with, and with all five to its shipped state.
        function reset(name: string, mode: string): bool { return LayoutService.resetProfile(name, mode) }
        // A built-in profile's shipped state again, without switching to it:
        // in use, its settings, notch, lock screen, default apps and fastfetch
        // at once, after a backup; otherwise the next time it is entered.
        // Takes the built-in id or the profile's name; anything else is
        // refused there.
        function restore(name: string): bool { return LayoutService.applyBuiltin(name) }
        // The alias. `Super+Alt+P` has always been the mode key and still is.
        function cycle(): string { return root.cycleMode() }
        function cycleProfile(): string {
            const names = LayoutService.profileNames
            const next = Profile.nextProfile(LayoutService.activeProfile, names)
            if (!next.length || !LayoutService.setActiveProfile(next)) return LayoutService.activeProfile
            osd.showMessage(LayoutService.activeProfileLabel, Profile.profileIcon())
            return next
        }
    }

    DashboardPanel {}
    // The event editor keeps an unsaved draft in itself, one more reason it
    // stays once built.
    LazyLoader { source: PanelService.demanded.eventEditor === true ? "shell/dashboard/EventEditor.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.wifiPassword === true ? "shell/network/WifiDialog.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.pairing === true ? "shell/bluetooth/PairingDialog.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.driveUnlock === true ? "shell/drives/UnlockDialog.qml" : ""; active: source.length > 0 }
    Osd { id: osd }
    // While the keys go to a window (the keyboard passthrough): the chip that
    // says so. No surface the rest of the time; its file is read the first
    // time and kept, as the panels' are.
    LazyLoader {
        readonly property bool passing: HyprlandService.passthrough
        property bool seen: false
        onPassingChanged: if (passing) seen = true
        source: seen || passing ? "shell/shortcuts/PassthroughChip.qml" : ""
        active: passing && source.length > 0
    }
    LazyLoader { source: PanelService.demanded.clipboard === true ? "shell/clipboard/ClipboardPanel.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.wallpaperPicker === true ? "shell/wallpaper/WallpaperPicker.qml" : ""; active: source.length > 0 }
    Overview {}
    Switcher {}
    LazyLoader { source: PanelService.demanded.settings === true ? "shell/settings/SettingsPanel.qml" : ""; active: source.length > 0 }
    // The assistant (a model Ollama runs on this computer) and the share
    // picker (xdg-desktop-portal-hyprland's custom picker,
    // scripts/share-picker.sh): built on their first open and nothing before
    // (PanelService.lazyPanels).
    LazyLoader { source: PanelService.demanded.assistant === true ? "shell/assistant/AssistantPanel.qml" : ""; active: source.length > 0 }
    LazyLoader { source: PanelService.demanded.sharePicker === true ? "shell/sharepicker/SharePickerPanel.qml" : ""; active: source.length > 0 }
    NetworkPopup {}
    VpnPopup {}
    BluetoothPopup {}
    MediaPopup {}
    VolumePopup {}
    BatteryPopup {}
    WeatherPopup {}
    EventsPopup {}
    PrivacyPopup {}
    SystemPopup {}
    ProfilePopup {}
    // The display switcher (Super+Shift+P, the projector key): built on its
    // first open - most sessions never meet a projector (PanelService.lazyPanels).
    LazyLoader { source: PanelService.demanded.displaySwitcher === true ? "shell/displays/DisplaySwitcher.qml" : ""; active: source.length > 0 }
    // A tray widget's menu, out of the icon it was opened from: built the
    // first time a menu opens (a right click on a tray widget's icon).
    LazyLoader { source: PanelService.demanded.trayMenu === true ? "shell/popups/TrayMenuPopup.qml" : ""; active: source.length > 0 }
    // Built on their first open, not at the start: a panel is built whether it
    // opens or not (testing.md pitfall 101; 5-10 MB nested), and these may
    // never open. PanelService asks for them (`demanded`) and opens them once
    // they are there; a feature switched off lets its panel go again.
    // The dock's menu: only with a dock, which a right click needs.
    LazyLoader {
        readonly property bool feature: SettingsService.value("dock.enabled") === true
        onFeatureChanged: if (!feature) PanelService.release("dockMenu")
        source: feature && PanelService.demanded.dockMenu === true ? "shell/dock/DockMenu.qml" : ""
        active: source.length > 0
    }
    // The start menu: opened by a dock's start button (Settings > Dock >
    // Start button) or by IPC, which works without a dock too (centred then).
    // The dock's start button going away lets it go.
    LazyLoader {
        id: startMenuLoader
        readonly property bool feature: SettingsService.value("dock.enabled") === true && LayoutService.dockHasStart
            && SettingsService.value("dock.startOpens") !== "launcher"
        onFeatureChanged: if (!feature) PanelService.release("startMenu")
        source: PanelService.demanded.startMenu === true ? "shell/startmenu/StartMenu.qml" : ""
        active: source.length > 0
    }
    // Out of the dock's start button when there is one on that screen, a gap
    // off the dock's body as a click on it does (Pill.qml), in the middle of
    // the screen otherwise. PanelService builds it first if it is not.
    // DockService only with a dock that is on (testing.md pitfall 101: the
    // service is not made for one that is off), whose button it is.
    function openStartMenu(view) { openFromStart("startMenu", view) }
    // A panel out of the dock's start button on the focused screen, when
    // there is one there - the start menu, or the launcher the button may
    // open instead -, else where the panel opens on its own.
    function openFromStart(panel, view) {
        const screen = PanelService.focusedScreen()
        const name = screen ? screen.name : ""
        const button = SettingsService.value("dock.enabled") === true ? LayoutService.dockItemRect(name, "start") : null
        const args = { onScreen: name, startView: view }
        if (button) Object.assign(args, DockLogic.panelAnchor(SettingsService.value("dock.position"), button,
                                                              Metrics.dockPanelGap, DockService.placeOf(name)),
                                  { originX: button.x, originY: button.y, originWidth: button.width, originHeight: button.height })
        PanelService.open(panel, args)
    }
    ColorPickerPopup {}
    ColorPickerOverlay {}
    IdentifyOverlay {}
    EditLayer {}

    // ---- keyboard shortcuts straight from Hyprland --------------------------
    // Each `shell("…")` bind in hypr/hyprland.lua is a Hyprland global
    // shortcut that lands here and runs the IPC function of the same name
    // (services/shortcuts/ShellShortcuts.js): the same action, without the
    // two processes a key press used to start. Touchpad swipes that open a
    // panel send one too (GestureLogic, `gestures run <name>`).
    readonly property var shortcutTargets: ({
        editor: editorIpc, desktop: desktopIpc, mode: modeIpc, profile: profileIpc, shortcuts: shortcutsIpc,
        launcher: launcherIpc, controlCenter: controlCenterIpc, settings: settingsIpc,
        notifications: notificationsIpc, dashboard: dashboardIpc, powerMenu: powerMenuIpc,
        overview: overviewIpc, wallpaperPicker: wallpaperPickerIpc, colorPicker: colorPickerIpc,
        switcher: switcherIpc, clipboard: clipboardIpc, emoji: emojiIpc, recording: recordingIpc,
        workspaces: workspacesIpc, kbdBacklight: kbdBacklightIpc, brightness: brightnessIpc, audio: audioIpc, osd: osdIpc,
        gestures: gesturesIpc, dock: dockIpc, startMenu: startMenuIpc, displays: displaysIpc, sessionApps: sessionAppsIpc, assistant: assistantIpc,
        zoom: zoomIpc, colorFilter: colorFilterIpc, window: windowIpc, dropdown: dropdownIpc
    })
    function runShortcut(name, pressed) {
        const call = ShellShortcuts.parse(name)
        const handler = call ? shortcutTargets[call.target] : null
        if (!handler || typeof handler[call.fn] !== "function") {
            console.warn("buchhwin-shell: unknown shortcut", name)
            return
        }
        // A held key's shortcut (push to talk) gets its edge after its arguments.
        handler[call.fn].apply(handler, ShellShortcuts.holds(name) ? call.args.concat([pressed === true]) : call.args)
    }
    Variants {
        model: ShellShortcuts.names()
        GlobalShortcut {
            required property string modelData
            appid: ShellShortcuts.APPID
            name: modelData
            description: modelData
            onPressed: if (ShellShortcuts.runsOn(modelData, true)) root.runShortcut(modelData, true)
            onReleased: if (ShellShortcuts.runsOn(modelData, false)) root.runShortcut(modelData, false)
        }
    }
}
