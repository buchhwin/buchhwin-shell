//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.shell.lock

// Lock screen entry point, a separate Quickshell process started by
// scripts/session-action.sh lock. It never reloads on file changes: a reload
// would drop the session lock surfaces.
ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    LockScreen {}
}
