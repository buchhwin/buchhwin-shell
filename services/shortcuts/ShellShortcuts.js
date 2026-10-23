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
    "audio up", "audio down", "audio mute", "audio micMute", "audio talk", "osd capsLock",
    "dock toggle", "startMenu toggle", "startMenu key", "displays toggleSwitcher", "displays key",
    "sessionApps startWork",
    "workspaces next", "workspaces previous", "workspaces moveNext", "workspaces movePrevious",
    "workspaces scroll down", "workspaces scroll up",
    "zoom increase", "zoom decrease", "zoom reset", "colorFilter toggle",
    "window keepOnTop", "window toggleFloating", "window minimize", "window restore", "dropdown toggle", "assistant toggle"
].concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => "workspaces switchTo " + n))
 .concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => "workspaces move " + n))

// The actions Settings > Shortcuts offers to put on a key of one's own
// (ShortcutLogic: a custom shortcut `{ shell }`), beside the built-in keys it
// can move. The start menu's: `startMenu key` acts only while the dock has a
// start button (the taskbar) and opens what a click on it opens - its
// built-in key is Super+Space; `startMenu toggle` is IPC's, which opens the
// menu even without a dock and is not offered. The assistant's has no key of
// its own: it is there for whoever wants one.
var BINDABLE = ["startMenu key", "assistant toggle"]

// The touchpad swipes that open a panel (Settings > Input): in a Lua session
// a swipe's action sends `buchhwin:gestures.run.<name>` (GestureLogic.shortcut)
// instead of starting the Quickshell IPC client at the end of every swipe.
// Not bound to a key, so not in ACTIONS, which checks.py reads.
var GESTURES = Gestures.actions.filter(action => Gestures.shellAction(action.value) !== null)
    .map(action => "gestures run " + action.value)

// The shortcuts that act when the key is let go (`release = true` in the
// bind): Hyprland sends "released" for them, and "pressed" for the rest.
var ON_RELEASE = ["switcher confirm", "osd capsLock"]

// The shortcuts that act on both edges of their key - push to talk, on
// while held: the press and the release each run the action, with `true` or
// `false` after its arguments (`audio talk(down: bool)`, shell.qml's
// runShortcut). Should Hyprland not report a release (Super let go before
// the key), the next press ends the hold (MicLogic.talkStep).
var HOLD = ["audio talk"]

function holds(name) {
    return HOLD.map(nameOf).indexOf(String(name)) >= 0
}

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
    if (holds(name)) return true
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
