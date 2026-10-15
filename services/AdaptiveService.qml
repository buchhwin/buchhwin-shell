pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

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
    readonly property bool hasInternal: screenNames.some(name => /^(eDP|LVDS|DSI)/.test(name))
    readonly property int externalCount: screenNames.filter(name => !/^(eDP|LVDS|DSI)/.test(name)).length
    // Only laptops switch; desktops without an internal panel keep their mode.
    readonly property string suggestedMode: !hasInternal ? "" : externalCount > 0 ? "docked" : "laptop"

    onSuggestedModeChanged: modeDelay.restart()
    onAutoProfileChanged: if (autoProfile) modeDelay.restart()
    Timer {
        id: modeDelay
        interval: 1500
        onTriggered: {
            if (root.autoProfile && root.suggestedMode.length && LayoutService.loaded
                    && LayoutService.activeMode !== root.suggestedMode)
                LayoutService.setActiveMode(root.suggestedMode)
        }
    }

    // ---- focus mode -------------------------------------------------------------
    property bool focusActive: false
    property bool dndBeforeFocus: false

    function setFocus(active) {
        if (active === focusActive) return
        if (active) {
            dndBeforeFocus = NotificationService.dndActive
            if (!dndBeforeFocus) NotificationService.setDnd("manual")
        } else if (!dndBeforeFocus) {
            NotificationService.setDnd("off")
        }
        focusActive = active
    }
}
