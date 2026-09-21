import Quickshell
import Quickshell.Io
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
import qs.services
import qs.theme
import "services/profile/ProfileLogic.js" as Profile

ShellRoot {
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
    readonly property bool adaptiveReady: AdaptiveService.suggestedProfile !== undefined
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
    WallpaperLayer {}
    ScreenCorners {}
    WidgetHost {}
    PillBar {}
    Notch {}
    Launcher {}
    EmojiPanel {}
    WelcomePanel {}
    ControlCenter {}
    NotificationPopupStack {}
    NotificationCenter {}
    PowerMenu {}
    ShortcutSheet {}

    IpcHandler {
        target: "desktop"
        // The desktop mode had no key of its own: it could only be changed in
        // Settings or through three launcher commands.
        function cycleMode(): string {
            const modes = LayoutService.modes
            const next = modes[(modes.indexOf(LayoutService.mode) + 1) % modes.length]
            if (!LayoutService.setMode(next)) return LayoutService.mode
            osd.showMessage(LayoutService.modeLabel, LayoutService.notchShown ? "󱂩" : LayoutService.barShown ? "󰘔" : "󰕰")
            return next
        }
        function setMode(name: string): bool { return LayoutService.setMode(name) }
        function getMode(): string { return LayoutService.mode }
    }

    IpcHandler {
        target: "editor"
        function toggle(): void { LayoutService.editMode = !LayoutService.editMode }
        function open(): void { LayoutService.editMode = true }
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
        target: "emoji"
        function toggle(): void { PanelService.toggle("emoji") }
        function open(): void { PanelService.open("emoji") }
        function close(): void { PanelService.close("emoji") }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { PanelService.toggle("launcher") }
        function open(): void { PanelService.open("launcher") }
        function close(): void { PanelService.close("launcher") }
    }

    IpcHandler {
        target: "controlCenter"
        function toggle(): void { PanelService.toggle("controlCenter") }
        function openPage(page: string): void { PanelService.open("controlCenter", { page: page }) }
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
                                    dndActive: NotificationService.dndActive,
                                    autoSuppressed: NotificationService.autoSuppressed,
                                    suppressed: NotificationService.suppressed,
                                    fullscreenActive: HyprlandService.fullscreenActive,
                                    gameActive: HyprlandService.gameActive })
        }
    }

    IpcHandler {
        target: "powerMenu"
        function toggle(): void { PanelService.toggle("powerMenu") }
        function open(): void { PanelService.open("powerMenu") }
        function close(): void { PanelService.close("powerMenu") }
    }

    IpcHandler {
        target: "settings"
        function setAnimationMode(mode: string): bool { return SettingsService.set("appearance.animationMode", mode) }
        function setTheme(theme: string): bool { return SettingsService.set("appearance.theme", theme) }
        function get(path: string): string { return JSON.stringify(SettingsService.value(path)) }
        function open(page: string): void { PanelService.open("settings", { page: page }) }
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
        // Calendar view: month | week | day.
        function setView(view: string): bool { return SettingsService.set("calendar.dashboardView", view) }
    }

    IpcHandler {
        target: "popup"
        // Pill popups by name, centred at a screen x in logical pixels like a
        // pill click (negative: default place below the clock).
        // A plain function, not a property: an IpcHandler exports its
        // properties, and a list cannot cross IPC.
        function isPopup(name: string): bool {
            return ["network", "vpn", "bluetooth", "media", "volume", "battery",
                    "weather", "events", "privacy", "system"].indexOf(name) >= 0
        }
        function open(name: string, anchorX: real): bool {
            if (!isPopup(name)) return false
            PanelService.open(name + "Popup", anchorX >= 0 ? { anchorX: anchorX } : {})
            return true
        }
        // Like open, but the popup grows out of the given rect the way a pill
        // click makes it grow out of the pill.
        function openAt(name: string, x: real, y: real, width: real, height: real): bool {
            if (!isPopup(name) || width <= 0 || height <= 0) return false
            PanelService.open(name + "Popup", { anchorX: x + width / 2, anchorTop: y + height,
                                                originX: x, originY: y, originWidth: width, originHeight: height })
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
        function get(): string {
            const current = WeatherService.current
            return JSON.stringify({ status: WeatherService.status, location: WeatherService.locationName,
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
        // Synthetic events around today in eventsFor() (week view, event list).
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
        // Expands or collapses both lists on the page.
        function expand(expanded: bool): void {
            UpdatesService.packagesExpanded = expanded
            UpdatesService.flatpaksExpanded = expanded
        }
        // Counts only, no package names.
        function get(): string {
            return JSON.stringify({ checking: UpdatesService.checking, packagesKnown: UpdatesService.result.packagesKnown,
                                    packages: UpdatesService.packages.length, security: UpdatesService.securityCount,
                                    flatpaks: UpdatesService.flatpaks.length, userFlatpaks: UpdatesService.userFlatpakCount,
                                    lastCheck: UpdatesService.lastCheck, message: UpdatesService.message,
                                    offline: UpdatesService.result.offline, realSession: UpdatesService.realSession,
                                    preview: UpdatesService.preview, checkHours: UpdatesService.checkHours,
                                    notify: UpdatesService.notifyEnabled })
        }
    }

    IpcHandler {
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
        target: "overview"
        function toggle(): void { PanelService.toggle("overview") }
        function open(): void { PanelService.open("overview") }
        function close(): void { PanelService.close("overview") }
    }

    IpcHandler {
        target: "gestures"
        // Called by touchpad gestures: overview, launcher, dashboard,
        // controlCenter, notifications, clipboard (toggle) or closePanel.
        function run(name: string): bool { return GestureService.run(name) }
        function refresh(): void { GestureService.refreshDevices() }
        // Show Settings > Input > Touchpad gestures without a touchpad.
        function preview(): void { GestureService.preview = true }
        function stopPreview(): void { GestureService.preview = false }
        function get(): string { return GestureService.describe() }
    }

    IpcHandler {
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
        target: "switcher"
        function next(): void { SwitcherService.next() }
        function previous(): void { SwitcherService.previous() }
        function confirm(): void { SwitcherService.confirm() }
        function cancel(): void { SwitcherService.cancel() }
        function get(): string { return SwitcherService.describe() }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { PanelService.toggle("clipboard") }
        function open(): void { PanelService.open("clipboard") }
        function close(): void { PanelService.close("clipboard") }
        function get(): string { return JSON.stringify({ enabled: ClipboardService.enabled, entries: ClipboardService.entries.length }) }
    }

    IpcHandler {
        target: "brightness"
        // Called by the brightness keys: amdgpu sends no udev event for their
        // changes, so the OSD would not notice them otherwise.
        function refresh(): void { BrightnessService.refresh() }
        function get(): string { return JSON.stringify({ available: BrightnessService.available, value: BrightnessService.value }) }
    }

    IpcHandler {
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
        function setScale(name: string, scale: string): void { DisplayService.setScale(name, scale) }
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
        function setMode(mode: string): bool { return LayoutService.setMode(mode) }
        function addPill(zone: string, type: string): bool { return LayoutService.barAddPill(zone, type, "") }
        // Keys: reserve true|false, fullscreen hide|show, scale 0.9|1|1.15,
        // style pills|bar, position floating|attached, edge top|bottom|left|
        // right, panelSpot and notificationSpot widget|start|centre|end.
        function setOption(key: string, value: string): bool {
            return LayoutService.setBarOption(key, key === "reserve" ? value === "true" : key === "scale" ? Number(value) : value)
        }
        function reset(): bool { return LayoutService.resetBar() }
        // Workspace indicator: mode "open", "gapless" or "fixed", 1–10 slots.
        function setWorkspaces(mode: string, count: int): bool {
            return SettingsService.set("workspaces.mode", mode) && SettingsService.set("workspaces.count", count)
        }
        // How the pips are drawn, which is a separate question from which
        // workspaces are shown.
        function setWorkspaceStyle(style: string): bool {
            return SettingsService.set("workspaces.style", style)
        }
        function get(): string {
            const bar = LayoutService.bar
            const describe = zone => bar[zone].map(pill => pill.items.map(item => item.type + (item.display === "icon" ? "*" : "")).join("+"))
            return JSON.stringify({ mode: LayoutService.mode, reserve: bar.reserve, fullscreen: bar.fullscreen, scale: bar.scale,
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
            return key === "fullscreen" ? SettingsService.set("notch.fullscreen", value)
                : ["reserve", "expandOnHover"].indexOf(key) >= 0 ? SettingsService.set("notch." + key, value === "true") : false
        }
        // Mode, settings and per screen what is shown (row ids and sizes, no titles).
        function get(): string { return NotchService.describe() }
    }

    IpcHandler {
        target: "audio"
        // Route an app stream (node id) to a sink node.name; "default" resets.
        function route(stream: string, sink: string): bool {
            const node = AudioService.playbackStreams.find(item => String(item.id) === stream)
            if (!node || (sink !== "default" && !AudioService.sinkInfo.some(item => item.name === sink))) return false
            AudioService.routeStream(node, sink === "default" ? "" : sink)
            return true
        }
        // Stream ids with their target, no app names.
        function get(): string {
            return JSON.stringify({ ready: AudioService.ready, sinks: AudioService.sinkInfo.map(item => item.name),
                                    streams: AudioService.playbackStreams.map(item => ({ id: item.id, target: AudioService.streamTarget(item) })),
                                    routingTrackers: AudioService.routingTrackers, meterTrackers: AudioService.meterTrackers,
                                    meterRunning: AudioService.meterRunning, micInUse: AudioService.micInUse,
                                    level: AudioService.inputLevel })
        }
    }

    IpcHandler {
        target: "profile"
        function set(name: string): bool { return LayoutService.setActiveProfile(name) }
        function get(): string { return LayoutService.activeProfile }
        // There are five profiles and, until now, no key at all: they could
        // only be changed in Settings, in the editor or from the launcher.
        // Cycling by hand also settles the automatic profile - see
        // ProfileLogic, the rule is the user's.
        function cycle(): string {
            const step = Profile.cycle(LayoutService.activeProfile, LayoutService.profileNames,
                                       SettingsService.value("desktop.autoProfile"))
            if (!step || !LayoutService.setActiveProfile(step.profile)) return LayoutService.activeProfile
            if (step.autoChanged) SettingsService.set("desktop.autoProfile", step.auto)
            osd.showMessage(Profile.osdText(Profile.label(step.profile, LayoutService.templates), step),
                            Profile.icon(step.profile))
            return step.profile
        }
    }

    DashboardPanel {}
    EventEditor {}
    WifiDialog {}
    PairingDialog {}
    UnlockDialog {}
    Osd { id: osd }
    ClipboardPanel {}
    WallpaperPicker {}
    Overview {}
    Switcher {}
    SettingsPanel {}
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
    ColorPickerPopup {}
    ColorPickerOverlay {}
    IdentifyOverlay {}
    EditLayer {}
}
