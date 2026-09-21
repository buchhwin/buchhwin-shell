pragma Singleton
import Quickshell
import QtQuick

// Central file-system locations. XDG variables are honoured so nested test
// sessions can sandbox configuration and state.
Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/buchhwin-shell"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/buchhwin-shell"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/buchhwin-shell"
    // For what must not outlive the session: a frozen screen capture is the
    // whole screen, so it belongs in the runtime directory and nowhere else.
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/buchhwin-shell"

    function script(name) {
        return Quickshell.shellPath("scripts/" + name)
    }

    function shellFile(relativePath) {
        return Quickshell.shellPath(relativePath)
    }
}
