.pragma library

// The shell's keyboard shortcuts as Hyprland global shortcuts: what
// hypr/hyprland.lua's `shell("launcher toggle")` sends as
// `buchhwin:launcher.toggle`, and what shell.qml registers and runs. A key
// press used to start `sh` and the Quickshell IPC client, 30-40 ms before the
// shell heard of it; a global shortcut arrives over the Wayland connection the
// shell already has. The action is the IPC call it always was - target,
// function, arguments - so a shortcut does exactly what `buchhwin <target>
// <function>` does. `checks.py binds` holds hyprland.lua to this list.

var APPID = "buchhwin"

var ACTIONS = [
    "editor toggle", "desktop cycleMode", "mode cycle", "profile toggle", "shortcuts toggleSheet",
    "launcher toggle", "controlCenter toggle", "settings toggle", "notifications toggle",
    "dashboard toggle", "powerMenu toggle", "overview toggle", "wallpaperPicker toggle",
    "colorPicker pick", "switcher next", "switcher previous", "switcher confirm",
    "clipboard toggle", "emoji toggle", "recording toggle region", "recording toggle screen",
    "kbdBacklight up", "kbdBacklight down", "kbdBacklight toggle"
].concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => "workspaces switchTo " + n))
 .concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => "workspaces move " + n))

// The shortcuts that act when the key is let go (`release = true` in the
// bind): Hyprland sends "released" for them, and "pressed" for the rest.
var ON_RELEASE = ["switcher confirm"]

// "launcher toggle" <-> "launcher.toggle": the protocol's id has no spaces.
function nameOf(action) {
    return String(action || "").trim().split(/\s+/).join(".")
}

// { target, fn, args } for a name, numbers as numbers (`switchTo(local: int)`).
function parse(name) {
    const parts = String(name || "").split(".").filter(part => part.length)
    if (parts.length < 2) return null
    return { target: parts[0], fn: parts[1],
             args: parts.slice(2).map(part => /^\d+$/.test(part) ? Number(part) : part) }
}

function onRelease(name) {
    return ON_RELEASE.map(nameOf).indexOf(String(name)) >= 0
}

function names() {
    return ACTIONS.map(nameOf)
}
