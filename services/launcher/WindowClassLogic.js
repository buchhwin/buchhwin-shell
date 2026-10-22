.pragma library

// Window classes whose app's desktop entry does not say it owns them: no
// StartupWMClass, and a class that is neither the entry's id nor its name, so
// Quickshell's heuristic lookup finds nothing and the window is drawn with the
// generic program icon. Citrix Workspace's window says "selfservice" (its
// binary); its entry is citrix-workspace.desktop. Lower-case class -> entry
// id. Unit tested.
var ALIASES = {
    "selfservice": "citrix-workspace"
}

function aliasFor(cls) {
    const key = String(cls || "").trim().toLowerCase()
    return Object.prototype.hasOwnProperty.call(ALIASES, key) ? ALIASES[key] : ""
}

// The desktop entry ids a process's systemd unit names, the likelier first.
// Launchers that follow the XDG naming - Plasma, GNOME, Flatpak,
// scripts/launch-app.sh - run an app in a unit named after its entry:
// app[-<launcher>]-<id>-<random>.scope or app[-<launcher>]-<id>[@<random>].service,
// every '-' inside the id escaped as \x2d. xdg-desktop-portal reads an app's
// identity the same way (xdp-app-info-host.c). It names the app of a window
// whose class names nothing: Modrinth's Flatpak says "modrinth-app-wrapped"
// (its entry promises "ModrinthApp"), and the game it starts says
// "Minecraft* 1.21.1" from inside the same unit. `cgroup` is the text of
// /proc/<pid>/cgroup; [] for a process outside such a unit.
function unitEntryIds(cgroup) {
    const line = String(cgroup || "").split("\n").map(text => text.trim()).find(text => text.indexOf("0::") === 0) || ""
    const unit = line.slice(3).split("/").pop() || ""
    let parts = []
    let match = /^app-(.+)\.scope$/.exec(unit)
    if (match) {
        parts = match[1].split("-")
        // The random part; a scope without one is no app's.
        if (parts.length < 2) return []
        parts.pop()
    } else if ((match = /^app-(.+)\.service$/.exec(unit))) {
        parts = match[1].split("@")[0].split("-")
    } else {
        return []
    }
    const unescape = text => text.replace(/\\x([0-9a-fA-F]{2})/g, (all, hex) => String.fromCharCode(parseInt(hex, 16)))
    // With a launcher in front the id follows it; a launcher that leaves its
    // dashes unescaped is read both ways.
    const ids = parts.length > 1 ? [parts.slice(1).join("-"), parts.join("-")] : [parts[0]]
    return ids.map(unescape).filter((id, index, list) => id.length > 0 && list.indexOf(id) === index)
}

// Whether an entry found by the unit may stand for a window: not a terminal,
// whose unit runs every program started from its shell.
function unitEntryUsable(categories) {
    return !Array.prototype.slice.call(categories || []).some(category => String(category) === "TerminalEmulator")
}
