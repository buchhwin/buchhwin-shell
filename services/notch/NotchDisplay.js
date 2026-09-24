.pragma library

// Which of the things that want to be seen may take the notch itself, instead
// of opening a surface of their own below it.
//
// Three ask: the on-screen displays (volume, microphone, brightness, keyboard
// light), a notification popup, and a track change. **Each is switched on
// separately** - "put it in the notch" is not one taste, and a volume bar in
// the notch with notifications still below it is a perfectly ordinary thing to
// want.
//
// Two rules decide everything else, and they are the whole of the arbitration
// the plan said the time would go into:
//
//   * **The most recent wins.** A volume bar that arrives while a notification
//     is up is the thing the user just caused, and a level from a moment ago
//     is useless. What it displaces simply ends early - a notification is in
//     the notification center either way, and an OSD that is gone is a value
//     that has already changed.
//   * **Hover wins.** While the pointer is on the notch, the notch is the
//     overview, which the user asked for on purpose. A display that arrives
//     then goes to its own surface - exactly what it does on a screen that has
//     no notch at all, which is the rule that was chosen for those.

var KINDS = ["osd", "notification", "media"]

// The setting that governs each kind. One place, so a page and a service
// cannot disagree about which switch belongs to which display.
var SETTINGS = {
    osd: "notch.displayOsd",
    notification: "notch.displayNotifications",
    media: "notch.displayMedia"
}

function setting(kind) {
    return SETTINGS[String(kind)] || ""
}

// Whether the notch on this screen may take this kind right now.
//
// `state` is what the shell knows at that moment:
//   enabled       the kind's own setting
//   notchShown    the desktop mode is "notch" and the notch is on screen
//   hasNotch      this screen reported a notch rectangle
//   overviewOpen  the notch is expanded (hover, or held open over IPC)
//   arranging     the notch is being arranged in the layout editor
function takes(kind, state) {
    const s = state || {}
    if (KINDS.indexOf(String(kind)) < 0) return false
    if (!s.enabled) return false
    // No notch here: widgets or bar mode, a second monitor without one, or a
    // notch hidden behind a fullscreen window. The display does what it always
    // did, which is the whole answer for a screen without a notch.
    if (!s.notchShown || !s.hasNotch) return false
    if (s.overviewOpen) return false
    // Arranged, the notch shows both of its lists and every item in them.
    // Anything else taking it over would make the drop maths count a shorter
    // list than the one on screen.
    if (s.arranging) return false
    return true
}

// The most recent of the slots that has something in it. Each slot is
// `{ stamp, content }` or null; `stamp` is a number that only goes up.
//
// A plain "last one set" rather than a priority order, because priorities
// invite the case this is meant to avoid: a notification that outranks the
// volume bar would leave the user pressing a key and seeing nothing happen.
function current(slots) {
    let best = null
    for (const kind of KINDS) {
        const slot = slots ? slots[kind] : null
        if (!slot || !slot.content) continue
        if (!best || slot.stamp > best.stamp) best = { kind: kind, stamp: slot.stamp, content: slot.content }
    }
    return best
}

// Which kinds are switched on, for a page that wants to say so in one line.
function enabledKinds(values) {
    return KINDS.filter(kind => values && values[kind])
}
