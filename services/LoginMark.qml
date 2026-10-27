import Quickshell
import Quickshell.Io
import QtQuick

// Whether this is the shell's first start in the login: a mark in the
// runtime directory, which is emptied when the login ends - a restarted
// shell finds it. Named after the compositor's instance as well, as
// AutostartService's and SessionAppsService's markers are: the directory
// stays while the user has another session or lingers, and a quick log out
// and in found the last login's mark. `check()` asks; `decided` answers.
Scope {
    id: mark
    required property string name
    readonly property string path: Paths.runtimeDir + "/" + name + "-" + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none")
    signal decided(bool first)

    function check() { checker.running = true }

    Process {
        id: checker
        command: ["sh", "-c", "[ -e \"$1\" ] && exit 0; mkdir -p -m 700 -- \"${1%/*}\" && : > \"$1\"; exit 3", "sh", mark.path]
        onExited: code => mark.decided(code === 3)
    }
}
