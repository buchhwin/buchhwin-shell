pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "hypr/HyprCommands.js" as Commands
import "hypr/HyprAnimations.js" as Anim

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
            "render:new_render_scheduling": Anim.frameScheduling(Quickshell.screens.length)
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

    function applyCursor() {
        const theme = SettingsService.cursorTheme
        const size = String(SettingsService.cursorSize)
        Quickshell.execDetached(["hyprctl", "setcursor", theme, size])
        if (realSession) Quickshell.execDetached([Paths.script("apply-cursor-env.sh"), theme, size])
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
        function onCursorThemeChanged() { root.applyCursor() }
        function onCursorSizeChanged() { root.applyCursor() }
        function onLoadedChanged() { if (SettingsService.loaded) { root.applyHyprland(); root.applyCursor() } }
    }

    Connections {
        target: HyprlandService
        function onConfigReloaded() {
            if (!SettingsService.loaded) return
            root.applyHyprland()
            root.applyCursor()
        }
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
