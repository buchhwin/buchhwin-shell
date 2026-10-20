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
