pragma Singleton
import Quickshell
import QtQuick

// Session and power actions through scripts/session-action.sh.
Singleton {
    readonly property var allowed: ["lock", "suspend", "logout", "reboot", "poweroff"]

    function run(actionId) {
        if (allowed.indexOf(actionId) < 0) return false
        Quickshell.execDetached([Paths.script("session-action.sh"), actionId])
        return true
    }
}
