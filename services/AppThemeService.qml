pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "appearance/AppThemeLogic.js" as Logic

// Settings > Appearance "Apps follow theme" and "Use the shell accent in apps"
// (both opt-in): KDE/Qt and GTK apps switch with the shell's effective theme
// (selector, Dark Mode chip, Automatic at 07:00/19:00), KDE apps (Dolphin's
// folder icons, selections) take the effective shell accent. Each change first
// queries the current values (read-only, including a backup of the kdeglobals
// colour entries), then runs only the commands that differ, one process at a
// time. The Plasma values from before the first change are kept in
// $XDG_STATE_HOME/buchhwin-shell/apptheme.json and restored when the options
// are turned off, at logout (scripts/apptheme-restore.py from
// session-action.sh) or, after a crash, at the next Plasma login (autostart
// entry with OnlyShowIn=KDE, installed with the first change). kdeglobals is
// shared with Plasma, so nested test sessions only log the commands (IPC
// `appTheme plan`) and never write the state file or the autostart entry.
Singleton {
    id: root

    // Like IdleService: nested sessions and sandboxed config dirs never touch
    // the host's colour scheme.
    readonly property bool realSession: AppearanceService.realSession
        && ((Quickshell.env("XDG_CONFIG_HOME") || "").length === 0
            || Quickshell.env("XDG_CONFIG_HOME") === Quickshell.env("HOME") + "/.config")
    readonly property bool enabled: SettingsService.value("appearance.appsFollowTheme")
    readonly property bool accentEnabled: SettingsService.value("appearance.appsAccent")
    readonly property bool anyEnabled: enabled || accentEnabled
    // Also the wallpaper accent when "From wallpaper" is on.
    readonly property string accent: SettingsService.accent
    readonly property bool restoreOnLogout: SettingsService.value("appearance.appsRestoreOnLogout")
    readonly property bool dark: Logic.effectiveDark(SettingsService.theme, clock.hours)
    readonly property string statePath: Paths.stateDir + "/apptheme.json"
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config"
    readonly property string autostartPath: configHome + "/autostart/" + Logic.AUTOSTART_NAME
    readonly property string autostartText: Logic.autostartEntry(Paths.script("apptheme-restore.py"))
    // Plasma's look-and-feel defaults (e.g. ColorScheme=BreezeDark) live in
    // kdedefaults, which only Plasma puts into XDG_CONFIG_DIRS. Reads and
    // writes use the same view so the current scheme matches Plasma's.
    readonly property string kdeConfigDirs: configHome + "/kdedefaults:" + (Quickshell.env("XDG_CONFIG_DIRS") || "/etc/xdg")

    property var state: Logic.emptyState()
    property bool stateReady: false
    property var current: null
    // Test sessions only: the values after the logged commands.
    property var simulated: null
    property var lastPlan: ({ action: "none", commands: [], error: "", state: Logic.emptyState() })
    property string lastError: ""
    property var queue: []
    property var pendingState: null
    property bool pending: false
    readonly property bool busy: queryProc.running || runner.running || queue.length > 0
    // One line for Settings: what the options did, or why nothing happened.
    readonly property string statusText: !anyEnabled ? ""
        : !realSession ? "Apps only switch in the buchhwin-shell session. This test session logs the commands instead."
        : lastError.length > 0 ? lastError
        : busy ? "Applying …"
        : state.applied ? "Applied. Dolphin redraws folder icons after it is restarted."
        : lastPlan.error.length > 0 ? lastPlan.error
        : "No changes were needed."
    readonly property bool statusIsError: realSession && (lastError.length > 0 || (!busy && !state.applied && lastPlan.error.length > 0))

    SystemClock { id: clock; precision: SystemClock.Hours }

    onEnabledChanged: schedule()
    onAccentEnabledChanged: schedule()
    onAccentChanged: if (accentEnabled) schedule()
    onDarkChanged: if (enabled) schedule()
    onRestoreOnLogoutChanged: schedule()
    Connections {
        target: SettingsService
        function onLoadedChanged() { root.schedule() }
    }

    function schedule() {
        if (SettingsService.loaded && stateReady) debounce.restart()
    }

    function options() {
        return { followTheme: enabled, accentEnabled: accentEnabled, accent: accent, dark: dark, restoreOnLogout: restoreOnLogout }
    }

    function refresh() {
        if (busy) {
            pending = true
        } else if (!anyEnabled && !state.applied) {
            // Off and nothing changed: no need to ask the system.
            lastPlan = Logic.plan(options(), current, state)
        } else {
            queryProc.running = true
        }
    }

    // Backups are summarised: IPC output stays short.
    function summary(values) {
        if (!values) return values
        const result = Object.assign({}, values)
        if ("kdeColors" in result) result.kdeColors = result.kdeColors ? result.kdeColors.entries.length + " entries" : null
        return result
    }

    function planJson() {
        return JSON.stringify({ realSession: realSession, enabled: enabled, accentEnabled: accentEnabled, accent: accent,
                                restoreOnLogout: restoreOnLogout, dark: dark, theme: SettingsService.theme, busy: busy,
                                action: lastPlan.action, commands: lastPlan.commands, current: summary(current),
                                applied: state.applied, saved: summary(state.saved), autostart: autostartPath,
                                lastError: lastError })
    }

    function queryFinished(text) {
        // Test sessions plan from the values their earlier plans would have set.
        current = realSession || !simulated ? Logic.parseQuery(text) : simulated
        const previousSaved = state.saved
        const next = Logic.plan(options(), current, state)
        lastPlan = next
        if (next.commands.length || next.error.length) lastError = next.error
        if (!realSession) {
            if (next.commands.length) console.info("buchhwin-shell: appTheme (test session) would run", JSON.stringify(next.commands))
            if (next.action === "apply" && next.state.applied && !state.applied)
                console.info("buchhwin-shell: appTheme (test session) would install", root.autostartPath)
            simulated = Logic.afterCommands(current, next.commands, previousSaved || next.state.saved)
            state = next.state
            finishRun()
            return
        }
        // The saved values must be on disk before anything changes; a restore
        // only forgets them once the commands ran.
        if (next.action === "apply") {
            writeState(next.state)
            if (next.state.applied) installAutostart()
        } else {
            pendingState = next.state
        }
        queue = next.commands
        runNext()
    }

    function writeState(next) {
        state = next
        const text = Logic.stateText(next)
        // Nothing to remember and no file yet: do not create one.
        if (!next.applied && stateFile.text().length === 0) return
        if (stateFile.text() !== text) stateFile.setText(text)
    }

    // Real session only (callers check). Writes only when the content differs.
    function installAutostart() {
        autostartProc.command = ["sh", "-c",
            "printf '%s' \"$2\" | cmp -s - \"$1\" 2>/dev/null && exit 0; "
            + "mkdir -p -- \"${1%/*}\" && printf '%s' \"$2\" > \"$1.tmp\" && mv -f -- \"$1.tmp\" \"$1\"",
            "sh", autostartPath, autostartText]
        autostartProc.running = true
    }

    function removeAutostart() {
        autostartProc.command = ["rm", "-f", "--", autostartPath]
        autostartProc.running = true
    }

    function runNext() {
        if (!queue.length) {
            if (pendingState) {
                writeState(pendingState)
                // Both options off and nothing left to restore: no safety net needed.
                if (!state.applied && !anyEnabled) removeAutostart()
            }
            pendingState = null
            finishRun()
            return
        }
        const command = queue[0]
        queue = queue.slice(1)
        console.info("buchhwin-shell: appTheme runs", JSON.stringify(command))
        runner.command = command
        runner.running = true
    }

    function finishRun() {
        if (!pending) return
        pending = false
        debounce.restart()
    }

    Timer { id: debounce; interval: 600; onTriggered: root.refresh() }

    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.state = Logic.parseState(text())
            root.stateReady = true
            root.schedule()
        }
        onLoadFailed: {
            root.stateReady = true
            root.schedule()
        }
    }

    // Read-only: current values, installed schemes and GTK themes, tools and
    // the kdeglobals colour backup.
    Process {
        id: queryProc
        stderr: ErrorLog { label: "AppThemeService.queryProc" }
        command: ["sh", "-c", "export XDG_CONFIG_DIRS=\"$2\"\n"
            + "echo '[tools]'; command -v plasma-apply-colorscheme gsettings\n"
            + "echo '[colorScheme]'; kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null\n"
            + "echo '[accentColor]'; kreadconfig6 --file kdeglobals --group General --key AccentColor 2>/dev/null\n"
            + "echo '[kdeColors]'; python3 \"$1\" --snapshot 2>/dev/null\n"
            + "echo '[schemes]'; plasma-apply-colorscheme --list-schemes 2>/dev/null\n"
            + "echo '[gtkColorScheme]'; gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null\n"
            + "echo '[colorSchemeRange]'; gsettings range org.gnome.desktop.interface color-scheme 2>/dev/null\n"
            + "echo '[gtkTheme]'; gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null\n"
            + "echo '[themes]'; for d in \"${XDG_DATA_HOME:-$HOME/.local/share}/themes\" \"$HOME/.themes\" /usr/share/themes; do "
            + "[ -d \"$d\" ] && find \"$d\" -mindepth 3 -maxdepth 3 -path '*/gtk-3.0/gtk.css'; done; true",
            "sh", Paths.script("apptheme-restore.py"), root.kdeConfigDirs]
        stdout: StdioCollector { onStreamFinished: root.queryFinished(text) }
    }

    Process {
        id: runner
        environment: ({ XDG_CONFIG_DIRS: root.kdeConfigDirs })
        stderr: StdioCollector { id: runnerErr }
        onExited: (exitCode, exitStatus) => {
            // Without a session bus the palette notification fails; the
            // colours are written all the same.
            if (exitCode !== 0 && runner.command[0] !== "dbus-send") {
                root.lastError = runner.command[0] + " failed (" + exitCode + "): " + runnerErr.text.trim()
                console.warn("buchhwin-shell: appTheme", root.lastError)
            }
            // Start the next command outside this process's exit handler.
            Qt.callLater(root.runNext)
        }
    }

    Process {
        id: autostartProc
        stderr: ErrorLog { label: "AppThemeService.autostartProc" }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) console.warn("buchhwin-shell: appTheme could not update", root.autostartPath)
        }
    }
}
