pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "hypr/HyprCommands.js" as Commands
import "hypr/HyprAnimations.js" as Anim
import "display/DisplayLogic.js" as DisplayLogic

// Applies appearance settings that live outside QML: Hyprland blur, window
// rounding, borders and gaps, and the cursor theme. Session environment
// updates only happen in the real buchhwin-shell session (BUCHHWIN_SHELL_PATH
// is set by its launcher), never in nested test sessions.
Singleton {
    id: root
    // Rounded screen corners (shell/desktop/ScreenCorners.qml). The radius is
    // the window rounding itself, so the display's corners and a maximized
    // window's corners are the same curve.
    readonly property bool screenCorners: SettingsService.value("appearance.screenCorners") === true
    readonly property int screenCornerRadius: screenCorners ? Math.max(0, SettingsService.windowRadius) : 0
    property var cursorThemes: []
    // Nested test sessions also export BUCHHWIN_SHELL_PATH (for the Lua config)
    // but must never touch the host's systemd environment.
    readonly property bool realSession: (Quickshell.env("BUCHHWIN_SHELL_PATH") || "").length > 0
        && Quickshell.env("BUCHHWIN_NESTED") !== "1"
    readonly property bool macCursorInstalled: cursorThemes.some(theme => theme.name.toLowerCase().startsWith("macos"))

    function label(name) {
        const known = { "breeze_cursors": "Breeze", "Breeze_Light": "Breeze Light", "Adwaita": "Adwaita",
                        "macOS": "macOS", "macOS-White": "macOS White" }
        return known[name] || name.replace(/[_-]+/g, " ")
    }

    function applyHyprland() {
        const blurSize = Math.round(2 + SettingsService.blurStrength * 10)
        HyprCompat.setOptions({
            "decoration:blur:enabled": SettingsService.blurStrength > 0,
            "decoration:blur:size": blurSize,
            "decoration:rounding": SettingsService.windowRadius,
            "general:border_size": SettingsService.borderEnabled ? SettingsService.borderSize : 0,
            "general:gaps_in": SettingsService.gapsIn,
            "general:gaps_out": SettingsService.gapsOut,
            // Decided by how many screens there are, not by taste - see
            // AnimationLogic.frameScheduling. The configuration files ship the
            // safe value; this is what turns it on again on a single screen.
            "render:new_render_scheduling": Anim.frameScheduling(Quickshell.screens.length),
            // Settings > Displays > "Sharp X11 applications". Off by default
            // and it changes nothing at all while every screen is at scale 1,
            // where logical and physical are the same size; it only means
            // something with fractional scaling, and there it is a trade
            // rather than a fix. The files ship `false` so a fresh install
            // behaves as it always did.
            "xwayland:force_zero_scaling": SettingsService.xwaylandSharp
        })
        applyAnimations()
    }

    // The animation mode reaches the compositor, not only the shell's own
    // surfaces. Hyprland has no global speed multiplier, so each leaf is
    // re-emitted; the numbers come from HyprAnimations, which is also what the
    // two configuration files are checked against.
    function applyAnimations() {
        const mode = SettingsService.animationMode
        HyprCompat.configure(Commands.animationMode(Anim.entries(mode, SettingsService.animationSpeed),
                                                   Anim.enabled(mode),
                                                   Anim.pointerAnimated(mode)))
    }

    // Settings > Displays > "Sharp X11 applications" makes XWayland draw in
    // real pixels, and X11 then believes its screen is 96 DPI: every X11
    // window a third smaller on a screen at 1.5. `Xft.dpi` is the one scale
    // X11 clients read and Wayland clients never see, so it carries the
    // largest scale any screen runs at (DisplayLogic.x11Scale) - 144 for 1.5.
    // Off, the key goes and X11 is back at 96 with XWayland stretching it, as
    // before. A dock or undock can change the largest scale, which is why this
    // follows the monitors and not only the switch. Like the compositor
    // option, only applications started afterwards read it.
    // The user may name the scale instead (Settings > Displays > X11 scale):
    // Citrix at the screen's own 1.5 was still a little small to read, and
    // a session that is mostly one remote desktop may well want 1.75 on a
    // 4K screen. 0 is "the largest screen".
    readonly property real x11Scale: !SettingsService.xwaylandSharp ? 1
        : SettingsService.x11ScaleSetting > 0 ? SettingsService.x11ScaleSetting
        : DisplayLogic.x11Scale(DisplayService.monitors)

    function applyX11Scale() {
        if (!realSession) return
        // Before the monitors are known the largest scale reads as 1, and a
        // reset written then is a wrong answer for a moment - and a moment is
        // enough for an application starting at login to read it.
        if (SettingsService.xwaylandSharp && SettingsService.x11ScaleSetting === 0 && !DisplayService.monitors.length) return
        const dpi = x11Scale > 1 ? String(Math.round(96 * x11Scale)) : "reset"
        Quickshell.execDetached([Paths.script("apply-x11-dpi.sh"), dpi])
    }

    function applyCursor() {
        const theme = SettingsService.cursorTheme
        const size = String(SettingsService.cursorSize)
        Quickshell.execDetached(["hyprctl", "setcursor", theme, size])
        // XWayland draws its own cursor from the X resource, in real pixels
        // when X11 is sharp - so that one gets the scaled size, or the pointer
        // shrinks by a third the moment it crosses into an X11 window.
        const x11Size = String(Math.round(SettingsService.cursorSize * x11Scale))
        if (realSession) Quickshell.execDetached([Paths.script("apply-cursor-env.sh"), theme, size, x11Size])
    }

    function refreshCursorThemes() { cursorScan.running = true }

    Connections {
        target: SettingsService
        function onBlurStrengthChanged() { debounce.restart() }
        function onWindowRadiusChanged() { debounce.restart() }
        function onBorderEnabledChanged() { debounce.restart() }
        function onBorderSizeChanged() { debounce.restart() }
        function onGapsInChanged() { debounce.restart() }
        function onGapsOutChanged() { debounce.restart() }
        function onAnimationModeChanged() { debounce.restart() }
        function onAnimationSpeedChanged() { debounce.restart() }
        function onXwaylandSharpChanged() { debounce.restart() }
        function onCursorThemeChanged() { root.applyCursor() }
        function onCursorSizeChanged() { root.applyCursor() }
        function onLoadedChanged() { if (SettingsService.loaded) { root.applyHyprland(); root.applyX11Scale(); root.applyCursor() } }
    }

    // The scale and the cursor's X11 size both move with it, so one change
    // writes both resources - the cursor last, as it is at start.
    onX11ScaleChanged: { if (SettingsService.loaded) { applyX11Scale(); applyCursor() } }

    Connections {
        target: HyprlandService
        function onConfigReloaded() {
            if (!SettingsService.loaded) return
            root.applyHyprland()
            root.applyX11Scale()
            root.applyCursor()
        }
    }

    // `render:new_render_scheduling` follows the screen count (above), so a
    // dock or an undock has to apply it again. Nothing did: the count was read
    // in `applyHyprland` but no change of it ran `applyHyprland`, and the
    // option stayed as the last settings change had left it - on, with three
    // monitors - until the next one.
    Connections {
        target: Quickshell
        function onScreensChanged() { if (SettingsService.loaded) debounce.restart() }
    }

    Timer { id: debounce; interval: 150; onTriggered: root.applyHyprland() }

    Process {
        id: cursorScan
        stderr: ErrorLog { label: "AppearanceService.cursorScan" }
        running: true
        command: ["sh", "-c", "for d in \"$HOME/.local/share/icons\" \"$HOME/.icons\" /usr/share/icons; do [ -d \"$d\" ] && find \"$d\" -mindepth 2 -maxdepth 2 -type d -name cursors; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}
                root.cursorThemes = text.split("\n").filter(line => line.length)
                    .map(line => line.split("/").slice(-2, -1)[0])
                    .filter(name => !seen[name] && (seen[name] = true))
                    .sort((a, b) => root.label(a).localeCompare(root.label(b)))
                    .map(name => ({ name: name, label: root.label(name) }))
            }
        }
    }
}
