pragma Singleton
import Quickshell
import QtQuick
import qs.theme
import "session/IconThemeLogic.js" as IconTheme

// Session and power actions through scripts/session-action.sh.
Singleton {
    readonly property var allowed: ["lock", "suspend", "logout", "reboot", "poweroff"]

    function run(actionId) {
        if (allowed.indexOf(actionId) < 0) return false
        // The clipboard history goes first when the user asked for that
        // (clipboard.forgetAtLogout); the wipe is detached and takes
        // milliseconds.
        if (["logout", "reboot", "poweroff"].indexOf(actionId) >= 0) ClipboardService.sessionEnding()
        Quickshell.execDetached([Paths.script("session-action.sh"), actionId])
        return true
    }

    // The icon theme the shell started with no longer fits its panels: the
    // panels chose it at the start (scripts/start-shell.sh) and have changed
    // brightness since, and Qt cannot change it in a running process
    // (session/IconThemeLogic.js). Settings offers the restart that fixes it.
    readonly property bool iconThemeStale: IconTheme.stale(Quickshell.env("QS_ICON_THEME"),
        Quickshell.env("BUCHHWIN_ICON_THEME_AUTO"), Colors.surfaceDark)

    // What Super+Ctrl+R does: reload-shell.sh ends this shell and starts it
    // again through start-shell.sh, which picks the icon theme anew. Detached,
    // so it outlives the shell it ends.
    function restartShell() {
        Quickshell.execDetached([Paths.script("reload-shell.sh")])
    }
}
