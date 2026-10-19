.pragma library

// The keyboard passthrough: a Hyprland submap that holds nothing but its way
// out, so every key the session would otherwise take - Alt+Tab, Super+L,
// Super+E, the Windows key itself - reaches the focused window instead. Made
// for the Citrix session the user works in all day, where every Hyprland
// bind won over Windows' own shortcuts; good for a virtual machine too.
//
// The way in is Super+Esc (or IPC, or by itself while a full-screen Citrix
// session has the focus, Settings > Shortcuts), and the way out is the same
// key, which hypr/ binds inside the submap itself: it never waits for the
// shell, so a shell that hangs cannot leave the keyboard with the window.
// The hardware keys (volume, brightness, media, the lid) are bound for every
// submap and keep working. Pure, unit tested in PassthroughTest.qml.

var NAME = "passthrough"

// Who asked for the submap the shell is about to enter or leave: "enter"
// for the user (the IPC call, the chip) and "auto" for the automatic
// handover. Only "auto" is the shell's own: the IPC way in counted as the
// shell's too, and `decide` took the keys back at once from every window
// that is not a full-screen Citrix session.
function enteredByItself(asked) {
    return asked === "auto"
}

// Hyprland's socket2 `submap>>NAME` event, with an empty name for the normal
// binds.
function activeIn(submap) {
    return String(submap || "") === NAME
}

// A Citrix session window: class Wfica, and not one of its own dialogs, which
// are titled exactly "wfica" (hypr/'s citrix-dialogs rule floats those).
function citrixSession(appId, title) {
    const name = String(title || "")
    return /^wfica$/i.test(String(appId || "")) && name.length > 0 && name.toLowerCase() !== "wfica"
}

// Whether the automatic passthrough wants this window: the setting on and a
// full-screen Citrix session in front.
function autoWanted(enabled, focused) {
    const window = focused || {}
    return enabled === true && window.present === true && window.fullscreen === true
        && citrixSession(window.appId, window.title)
}

// Whether `focused` still counts as the window the keys were given to
// (`owner`, as { appId, title, same }): the same window, or - for a Citrix
// session - another window of Citrix's own, a dialog of the session the keys
// went to.
function sameOwner(owner, focused) {
    const window = focused || {}
    if (!owner || window.present !== true) return false
    if (window.same === true) return true
    return /^wfica$/i.test(String(owner.appId || "")) && /^wfica$/i.test(String(window.appId || ""))
}

// What to do about the submap now: "enter", "leave" or "". `state`:
//   active      the submap is on (Hyprland said so)
//   owner       { appId, title } of the window it was entered for, or null
//               when nothing had the focus then
//   ownerGone   that window has closed since
//   auto        whether the shell entered it by itself
//   focused     { present, same (the owner itself), appId, title, fullscreen }
//   enabled     the automatic passthrough is on
//   declined    the focused window is the one the user took the keys back
//               from while it still wanted them: not entered again until the
//               focus has been elsewhere
// The keys come back when the focus goes to another window - the binds the
// user reaches for there are the session's - and, when they went by
// themselves, when the session leaves full screen.
function decide(state) {
    const s = state || {}
    const focused = s.focused || {}
    if (s.active === true) {
        if (s.ownerGone === true) return "leave"
        if (s.owner ? !sameOwner(s.owner, focused) : focused.present === true) return "leave"
        if (s.auto === true && !autoWanted(true, focused)) return "leave"
        return ""
    }
    if (s.declined === true) return ""
    return autoWanted(s.enabled === true, focused) ? "enter" : ""
}

// What the chip says, short enough for one line: where the keys go, and the
// key that brings them back (ShortcutService.keyHint, so a moved key reads
// right).
function chipText(owner, key) {
    const target = owner && citrixSession(owner.appId, owner.title) ? "Keys go to Citrix" : "Keys go to the window"
    const back = String(key || "")
    return back.length ? target + " · " + back + " gives them back" : target
}

function chipShort(key) {
    const back = String(key || "")
    return back.length ? back : "Keys"
}
