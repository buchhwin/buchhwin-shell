import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
    LazyLoader { active: PanelService.demanded.emoji === true; EmojiPanel {} }
    // The tour: built for the first start (until it has been seen), or when
    // Settings > About or IPC opens it again - not at every start for a panel
    // shown once per install (PanelService.lazyPanels). Opened once, it stays
    // for the session, so marking itself completed does not unload it.
    LazyLoader {
        active: PanelService.demanded.welcome === true
            || (SettingsService.loaded && SettingsService.value("onboarding.completed") !== true)
        WelcomePanel {}
    }
    ControlCenter {}
    NotificationPopupStack {}
    LazyLoader { active: PanelService.demanded.notifications === true; NotificationCenter {} }
    LazyLoader { active: PanelService.demanded.powerMenu === true; PowerMenu {} }
    LazyLoader { active: PanelService.demanded.shortcutSheet === true; ShortcutSheet {} }

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
        // Counts and flags only: no notification titles, bodies or app names.
        function get(): string {
            return JSON.stringify({ serverWanted: NotificationService.serverWanted,
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
                                    gameActive: HyprlandService.gameActive })
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
                                    eventCheck: CalendarService.identityState, eventCheckReason: CalendarService.identityReason })
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
        function get(): string {
            return JSON.stringify({ wifi: NetworkService.wifiEnabled, connected: NetworkService.connected,
                                    hotspot: NetworkService.hotspotActive, busy: NetworkService.helperState })
        }
    }

    IpcHandler {
        target: "bluetooth"
        // Sample dialog for tests and screenshots; answers never reach BlueZ.
        function previewPairing(kind: string): void { BluetoothService.previewPairing(kind) }
        function get(): string {
            return JSON.stringify({ available: BluetoothService.available, enabled: BluetoothService.enabled,
                                    agentAllowed: BluetoothService.agentAllowed, agentReady: BluetoothService.agentReady })
        }
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
                                    enabledNow: FingerprintService.enabledNow,
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
                                    notify: DrivesService.notifyEnabled, autoOpen: DrivesService.autoOpen })
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
                                    shell: { known: UpdatesService.shell.known, repo: UpdatesService.shell.repo,
                                             behind: UpdatesService.shell.behind, ahead: UpdatesService.shell.ahead,
                                             dirty: UpdatesService.shell.dirty, updatable: UpdatesService.shellUpdatable,
                                             checking: UpdatesService.shellChecking, auto: UpdatesService.shellAuto } })
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
                                    favourites: WallpaperService.favourites.length })
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
        function get(): string { return JSON.stringify({ enabled: ClipboardService.enabled, entries: ClipboardService.entries.length }) }
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
        function get(): string { return JSON.stringify({ available: BrightnessService.available, value: BrightnessService.value }) }
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
        function get(): string {
            return JSON.stringify({ perMonitor: HyprlandService.perMonitor,
                                    focusedMonitor: HyprlandService.focusedMonitorName,
                                    order: HyprlandService.monitorList.map(m => m.name),
                                    active: HyprlandService.monitorList.map(m =>
                                        m.name + ":" + HyprlandService.activeWorkspaceOn(m.name)),
                                    offsets: HyprlandService.monitorList.map(m =>
                                        m.name + ":" + HyprlandService.offsetFor(m.name)) })
        }
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
        // Which source Settings > Power edits: battery, ac or "" (the active one).
        function showSource(name: string): void { PowerService.pageSource = ["battery", "ac"].indexOf(name) >= 0 ? name : "" }
        function get(): string {
            const settings = name => ({ screenOff: PowerService.sourceValue(name, "screenOffMinutes"), lock: PowerService.sourceValue(name, "lockMinutes"),
                                        suspend: PowerService.sourceValue(name, "suspendMinutes"), dim: PowerService.sourceValue(name, "dimBeforeScreenOff"),
                                        lid: PowerService.sourceValue(name, "lidAction"), profile: PowerService.sourceValue(name, "profile") })
            return JSON.stringify({ source: PowerService.source, hasBattery: PowerService.hasBattery,
                                    screenOff: IdleService.screenOffMinutes, lock: IdleService.lockMinutes, suspend: IdleService.suspendMinutes,
                                    dim: IdleService.dimBeforeScreenOff, lid: IdleService.lidAction, profileChoice: PowerService.profileChoice,
                                    lockBeforeSleep: IdleService.lockBeforeSleep, lidClosed: DisplayService.lidClosed,
                                    stayAwake: IdleService.stayAwake, realSession: IdleService.realSession,
                                    battery: settings("battery"), ac: settings("ac") })
        }
    }

    IpcHandler {
        target: "displays"
        function get(): string {
            return JSON.stringify({ dirty: DisplayService.dirty, confirming: DisplayService.confirming, countdown: DisplayService.countdown,
                                    // Which Hyprland dialect the shell settled on. A wrong guess here
                                    // is silent and total - every keyword is rejected for the life of
                                    // the session - so it is worth being able to read it.
                                    dialect: HyprCompat.dialect,
                                    monitors: DisplayService.monitors.map(m => m.name + " " + m.width + "x" + m.height + "@" + Math.round(m.refresh)
                                        + " " + m.x + "," + m.y + " x" + m.scale + " t" + m.transform + (m.disabled ? " off" : "")),
                                    // The edited copy as well as the live state. Without it the
                                    // only way to see what a drag or an arrow-key nudge did was
                                    // to read a row on the page, which a nested test cannot.
                                    draft: DisplayService.draft.map(m => m.name + " " + m.x + "," + m.y
                                        + " x" + m.scale + " t" + m.transform + (m.disabled ? " off" : "")) })
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
        function stop(): void { TimerService.stop() }
        // Running, and the seconds left; no label, there is none.
        function get(): string {
            return JSON.stringify({ running: TimerService.running, remaining: Math.ceil(TimerService.remaining / 1000) })
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
        function micMute(): void { if (AudioService.source && AudioService.source.audio) AudioService.toggleMute(AudioService.source); else Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]) }
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
                                    level: AudioService.inputLevel })
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
                                       SettingsService.value("desktop.autoProfile"))
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
    LazyLoader { active: PanelService.demanded.eventEditor === true; EventEditor {} }
    LazyLoader { active: PanelService.demanded.wifiPassword === true; WifiDialog {} }
    LazyLoader { active: PanelService.demanded.pairing === true; PairingDialog {} }
    LazyLoader { active: PanelService.demanded.driveUnlock === true; UnlockDialog {} }
    Osd { id: osd }
    LazyLoader { active: PanelService.demanded.clipboard === true; ClipboardPanel {} }
    LazyLoader { active: PanelService.demanded.wallpaperPicker === true; WallpaperPicker {} }
    Overview {}
    Switcher {}
    LazyLoader { active: PanelService.demanded.settings === true; SettingsPanel {} }
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
    // Built on their first open, not at the start: a panel is built whether it
    // opens or not (testing.md pitfall 101; 5-10 MB nested), and these may
    // never open. PanelService asks for them (`demanded`) and opens them once
    // they are there; a feature switched off lets its panel go again.
    // The dock's menu: only with a dock, which a right click needs.
    LazyLoader {
        readonly property bool feature: SettingsService.value("dock.enabled") === true
        onFeatureChanged: if (!feature) PanelService.release("dockMenu")
        active: feature && PanelService.demanded.dockMenu === true
        DockMenu {}
    }
    // The start menu: opened by a dock's start button (Settings > Dock >
    // Start button) or by IPC, which works without a dock too (centred then).
    // The dock's start button going away lets it go.
    LazyLoader {
        id: startMenuLoader
        readonly property bool feature: SettingsService.value("dock.enabled") === true && LayoutService.dockHasStart
            && SettingsService.value("dock.startOpens") !== "launcher"
        onFeatureChanged: if (!feature) PanelService.release("startMenu")
        active: PanelService.demanded.startMenu === true
        StartMenu {}
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
        workspaces: workspacesIpc, kbdBacklight: kbdBacklightIpc, brightness: brightnessIpc, audio: audioIpc,
        gestures: gesturesIpc, dock: dockIpc, startMenu: startMenuIpc
    })
    function runShortcut(name) {
        const call = ShellShortcuts.parse(name)
        const handler = call ? shortcutTargets[call.target] : null
        if (!handler || typeof handler[call.fn] !== "function") {
            console.warn("buchhwin-shell: unknown shortcut", name)
            return
        }
        handler[call.fn].apply(handler, call.args)
    }
    Variants {
        model: ShellShortcuts.names()
        GlobalShortcut {
            required property string modelData
            appid: ShellShortcuts.APPID
            name: modelData
            description: modelData
            onPressed: if (ShellShortcuts.runsOn(modelData, true)) root.runShortcut(modelData)
            onReleased: if (ShellShortcuts.runsOn(modelData, false)) root.runShortcut(modelData)
        }
    }
}
