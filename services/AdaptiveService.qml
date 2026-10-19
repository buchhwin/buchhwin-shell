pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "display/DisplayLogic.js" as DisplayLogic
import "profile/AutoModeLogic.js" as AutoMode
import "adaptive/FocusLogic.js" as FocusLogic
import "timer/TimerLogic.js" as TimerLogic

// Adaptive behaviour: accent colour from the wallpaper, the automatic mode
// when external monitors (or the charger) come and go, and a focus mode that
// silences notifications and hides desktop widgets except the clock - open
// ended, or as a session that ends by itself (`focusFor`).
//
// It switches the **mode**, never the profile: the profile is what the user
// chose and nothing changes it on its own.
Singleton {
    id: root

    // ---- accent from wallpaper ------------------------------------------------
    readonly property bool accentFromWallpaper: SettingsService.value("appearance.accentFromWallpaper")
    readonly property string wallpaper: WallpaperService.current
    // The wallpaper the last run was for, whatever it answered.
    property string accentSource: ""
    // Where the script keeps its last answer, by the image's path, mtime and
    // size: every login decoded the whole wallpaper again (a 6000x3750 PNG)
    // for the accent that was already stored, and the same image now answers
    // from here without a decode. In the cache directory beside the wallpaper
    // thumbnails, which are kept by the same key: both are made from the
    // image and can always be made again.
    readonly property string accentCache: Paths.cacheDir + "/wallpaper-accent.json"

    function updateAccent() {
        if (!accentFromWallpaper || !wallpaper.length || wallpaper === accentSource || accentProc.running) return
        accentProc.source = wallpaper
        accentProc.command = [Paths.script("wallpaper-accent.py"), "--cache", accentCache, wallpaper]
        accentProc.running = true
    }

    onAccentFromWallpaperChanged: { accentSource = ""; accentDelay.restart() }
    onWallpaperChanged: accentDelay.restart()
    Timer { id: accentDelay; interval: 300; onTriggered: root.updateAccent() }

    Process {
        id: accentProc
        stderr: ErrorLog { label: "AdaptiveService.accentProc" }
        property string source: ""
        stdout: StdioCollector {
            onStreamFinished: {
                // Done with this image whatever it said, or a wallpaper that
                // cannot be read would be asked for again every 300 ms.
                root.accentSource = accentProc.source
                // A missing or unreadable image answers with no accent (and
                // exit 1), not with the default blue: that is no colour of
                // the wallpaper, and taking it turned the accent blue on
                // every machine without the shipped wallpaper file. The
                // accent in use stays.
                let accent = ""
                try {
                    accent = String(JSON.parse(text).accent || "")
                } catch (error) {
                    accent = ""
                }
                if (/^#[0-9a-f]{6}$/i.test(accent) && root.accentFromWallpaper
                        && SettingsService.accent.toLowerCase() !== accent.toLowerCase())
                    SettingsService.set("appearance.accent", accent)
            }
        }
        onExited: if (root.wallpaper !== root.accentSource) accentDelay.restart()
    }

    // ---- automatic mode ----------------------------------------------------
    readonly property bool autoProfile: SettingsService.value("desktop.autoProfile")
    // Where it goes (Settings > Profiles): at the desk, on the road, on
    // battery - shipped Docked, Laptop, none (AutoModeLogic.js). Checked
    // against the profile's modes only while the switching is on; off, the
    // shipped five do, and nothing here makes LayoutService (a service test
    // that reaches this one gets no profile laid over its settings).
    readonly property var autoTargets: AutoMode.targets(path => SettingsService.value(path),
                                                        autoProfile ? LayoutService.modeNames : [])
    // The modes it picks, for the mode key's rule (ProfileLogic.cycleMode).
    readonly property var autoOwned: AutoMode.owned(autoTargets)
    readonly property var screenNames: Quickshell.screens.map(screen => screen.name)
    // The panel counts while the lid has it switched off, too: docked with
    // the lid shut it is not among the screens, and judged by those alone
    // the laptop was a desktop - no switch to Docked, Auto hidden.
    // DisplayService knows it from `hyprctl monitors all`.
    readonly property bool hasInternal: DisplayLogic.hasInternalPanel(screenNames, DisplayService.internalName)
    readonly property int externalCount: DisplayLogic.externalCount(screenNames, DisplayService.internalName)
    // Only laptops switch; desktops without an internal panel keep their mode.
    // The power state is read only with a battery target: without one the
    // switching never asks.
    readonly property string suggestedMode: AutoMode.suggested(DisplayLogic.suggestedMode(screenNames, DisplayService.internalName),
                                                               AutoMode.watchesBattery(autoTargets) && PowerService.onBattery,
                                                               autoTargets)

    onSuggestedModeChanged: modeDelay.restart()
    onAutoProfileChanged: if (autoProfile) modeDelay.restart()
    Timer {
        id: modeDelay
        interval: 1500
        onTriggered: {
            if (root.autoProfile && root.suggestedMode.length && LayoutService.loaded
                    && LayoutService.activeMode !== root.suggestedMode)
                // Automatic: no undo step of its own, and undoing an earlier
                // edit keeps the mode the machine chose (LayoutLogic.modeAfterUndo).
                LayoutService.setActiveMode(root.suggestedMode, true)
        }
    }

    // ---- focus mode -------------------------------------------------------------
    // Focus owns the Do Not Disturb it turns on (FocusLogic.dndOnFocus), as a
    // mode does: leaving gaming under Focus keeps it, and ending Focus hands
    // it back to a mode that wants it.
    property bool focusActive: false

    function setFocus(active) {
        // Ending Focus by hand ends its session too: the countdown would
        // ring for a Focus that is over.
        if (!active) TimerService.cancel("focus")
        if (active === focusActive) return
        // The mode's effects with its own Do Not Disturb choice in them: Focus
        // hands it back to a mode that turns it on (LayoutService.modeDnd).
        const effects = LayoutService.modeDndEffects(LayoutService.activeMode)
        const change = FocusLogic.dndOnFocus(active, NotificationService.dndBy, NotificationService.dndActive,
                                             LayoutService.activeMode, effects)
        if (change) NotificationService.setDnd(change.mode, change.by)
        focusActive = active
    }

    // A deploy, reload or crash restart keeps Focus's Do Not Disturb - it is
    // read back from state.json with its owner - and Focus comes back with
    // it; before, the tile said Off, the desktop widgets were back and the
    // Do Not Disturb stayed on until switched off by hand. Asked once, after
    // the state has loaded (and after an early setDnd laid over it). Only in
    // the shell itself (BUCHHWIN_SHELL_PATH, which the unit tests run
    // without): asking from a test that reaches this service - WallpaperTest
    // reads the accent - would build NotificationService there, and its
    // server would queue for the session's notifications (testing.md
    // pitfall 82).
    readonly property bool restoresFocus: (Quickshell.env("BUCHHWIN_SHELL_PATH") || "").length > 0
    property bool focusChecked: false
    function restoreFocus() {
        if (!restoresFocus || focusChecked || !NotificationService.stateLoaded) return
        focusChecked = true
        const step = FocusLogic.restartStep(NotificationService.dndBy, NotificationService.dndActive, sessionEnded)
        sessionEnded = false
        if (step !== "off") focusActive = true
        if (step === "end") setFocus(false)
        checkSession()
    }

    // ---- a Focus session ----------------------------------------------------------
    // Focus for a while (FocusLogic): Focus on, and a countdown of its own
    // beside any timer - TimerService's "focus" run - whose end turns Focus
    // off and rings. From the launcher ("Focus: 25 minutes") or IPC
    // (`buchhwin focus start 25m`). Stopping the countdown (the chip, `timer
    // stop`) ends Focus; ending Focus drops the countdown. A Focus already on
    // gets the end; a session already running a new one.
    readonly property real focusEndsAt: focusActive ? TimerService.endOf("focus") : 0
    readonly property bool focusSession: focusEndsAt > 0
    readonly property string focusLabel: FocusLogic.focusLabel(focusActive, focusEndsAt, SettingsService.twelveHourClock)

    function focusFor(seconds) {
        const s = Math.round(Number(seconds) || 0)
        if (s <= 0 || s > TimerLogic.MAX_SECONDS) return false
        setFocus(true)
        return TimerService.start(s, "focus")
    }
    // A typed duration ("25m", "1h", "45"), as the launcher and IPC take it.
    function focusForText(text) { return focusFor(TimerLogic.parseDuration(text)) }

    // A session that ran out before Focus was read back after a restart
    // (TimerService rings an overdue run as it starts): `restoreFocus` ends
    // that Focus instead of bringing it back for good.
    property bool sessionEnded: false
    function sessionRanOut() {
        if (restoresFocus && !focusChecked) {
            sessionEnded = true
            return
        }
        setFocus(false)
    }
    // A countdown restored from timer.json whose Focus did not come back
    // (its Do Not Disturb was changed before the restart) is dropped; asked
    // once both are known.
    function checkSession() {
        if ((restoresFocus && !focusChecked) || !TimerService.loaded) return
        if (FocusLogic.sessionAfterRestart(focusActive, TimerService.has("focus")) === "drop") TimerService.cancel("focus")
    }
    Connections {
        target: TimerService
        function onEnded(kind) { if (kind === "focus") root.sessionRanOut() }
        function onStopped(kind) { if (kind === "focus") root.setFocus(false) }
        function onLoadedChanged() { root.checkSession() }
    }
    Connections {
        target: root.restoresFocus ? NotificationService : null
        function onStateLoadedChanged() { Qt.callLater(root.restoreFocus) }
    }
    Component.onCompleted: Qt.callLater(restoreFocus)
}
