.pragma library
.import "../input/GestureLogic.js" as Gestures

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
    "kbdBacklight up", "kbdBacklight down", "kbdBacklight toggle", "brightness up", "brightness down",
    "dock toggle", "startMenu toggle"
].concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => "workspaces switchTo " + n))
 .concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => "workspaces move " + n))

// The actions without a key of their own in hypr/, which Settings > Shortcuts
// offers to put on one (ShortcutLogic: a custom shortcut `{ shell }`). The
// start menu was reachable by a click or IPC only (round 12); its key is the
// user's choice - Super+D stays the launcher.
var BINDABLE = ["startMenu toggle"]

// The touchpad swipes that open a panel (Settings > Input): in a Lua session
// a swipe's action sends `buchhwin:gestures.run.<name>` (GestureLogic.shortcut)
// instead of starting the Quickshell IPC client at the end of every swipe.
// Not bound to a key, so not in ACTIONS, which checks.py reads.
var GESTURES = Gestures.actions.filter(action => Gestures.shellAction(action.value) !== null)
    .map(action => "gestures run " + action.value)

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

// Whether a shortcut acts on this event (`pressed` true, or false for the
// release). A swipe's shortcut comes from a gesture's Lua function, where no
// key is held down for Hyprland to report on, and one dispatch sends exactly
// one of the two events: it acts on whichever arrives.
function runsOn(name, pressed) {
    if (GESTURES.map(nameOf).indexOf(String(name)) >= 0) return true
    return onRelease(name) !== pressed
}

function names() {
    return ACTIONS.concat(GESTURES).map(nameOf)
}

function bindable(action) {
    return BINDABLE.indexOf(String(action || "")) >= 0
}

// The global shortcut of an action as a bind sends it: "buchhwin:startMenu.toggle".
function shortcutName(action) {
    return APPID + ":" + nameOf(action)
}
