pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "display/DisplayLogic.js" as DisplayLogic
import "adaptive/FocusLogic.js" as FocusLogic

// Adaptive behaviour: accent colour from the wallpaper, automatic Laptop /
// Docked mode when external monitors come and go, and a focus mode that
// silences notifications and hides desktop widgets except the clock.
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
    readonly property var screenNames: Quickshell.screens.map(screen => screen.name)
    // The panel counts while the lid has it switched off, too: docked with
    // the lid shut it is not among the screens, and judged by those alone
    // the laptop was a desktop - no switch to Docked, Auto hidden.
    // DisplayService knows it from `hyprctl monitors all`.
    readonly property bool hasInternal: DisplayLogic.hasInternalPanel(screenNames, DisplayService.internalName)
    readonly property int externalCount: DisplayLogic.externalCount(screenNames, DisplayService.internalName)
    // Only laptops switch; desktops without an internal panel keep their mode.
    readonly property string suggestedMode: DisplayLogic.suggestedMode(screenNames, DisplayService.internalName)

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
        if (active === focusActive) return
        const effects = (LayoutService.templates[LayoutService.activeMode] || {}).effects || {}
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
        if (FocusLogic.focusRestored(NotificationService.dndBy, NotificationService.dndActive)) focusActive = true
    }
    Connections {
        target: root.restoresFocus ? NotificationService : null
        function onStateLoadedChanged() { Qt.callLater(root.restoreFocus) }
    }
    Component.onCompleted: Qt.callLater(restoreFocus)
}
