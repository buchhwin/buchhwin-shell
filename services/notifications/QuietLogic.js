.pragma library

// When popups keep quiet by themselves, where they go instead, and what is
// said once they may speak again. Unit tested (NotificationQuietTest).

// ---- the screen is shared ----------------------------------------------------
//
// A screen, a window or a region shared through the portal is a PipeWire
// video node of xdg-desktop-portal-hyprland's ("xdph-streaming-N"; wlr's
// portal names its own "xdpw-..."), there for exactly as long as the share
// runs and listed again by a shell that starts in the middle of one.
// Hyprland's own `screencast>>STATE,OWNER` is one event per capture session
// of any client - the shell's overview thumbnails too - and a lone
// `screencast>>0` follows every workspace switch here, which cleared a plain
// flag in the middle of a call; a shell restarted during a share never heard
// its start at all. A webcam is a video source too, so it goes by the name.
var SHARE_PREFIXES = ["xdph-streaming", "xdpw"]

function isShareNode(node) {
    const name = String((node && node.name) || "")
    return SHARE_PREFIXES.some(prefix => name.indexOf(prefix) === 0)
}

// How many shares run among PipeWire's nodes (objects with a `name`). Unit
// tested.
function shareCount(nodes) {
    let count = 0
    for (const node of nodes || []) if (isShareNode(node)) count += 1
    return count
}

// ---- fullscreen ---------------------------------------------------------------
//
// "Wfica, Example" -> ["wfica", "example"]: window classes, any case, commas
// or spaces between them.
function classList(text) {
    return String(text || "").split(/[,\s]+/).map(item => item.trim().toLowerCase()).filter(item => item.length)
}

// Whether a fullscreen window of `appId` still lets popups through: a remote
// desktop (Citrix's Wfica) is a workplace, not a film, and the mail and the
// chat that come while one is in front all day are the ones that matter.
// Unit tested.
function isException(appId, exceptions) {
    const name = String(appId || "").trim().toLowerCase()
    return name.length > 0 && classList(exceptions).indexOf(name) >= 0
}

// The screen the popups go to: `focused`, unless it shows a fullscreen
// window and another screen does not - then the first of those (at the desk
// the portrait screen beside a Citrix desktop spanning the two big ones).
// `screens` is [{ name, fullscreen }] in the shell's order. "" means the
// focused screen, as always. Unit tested.
function popupScreen(focused, screens, elsewhere) {
    if (!elsewhere) return ""
    const list = screens || []
    const own = list.find(screen => screen && screen.name === focused)
    if (!own || !own.fullscreen) return ""
    const free = list.find(screen => screen && screen.name !== focused && !screen.fullscreen)
    return free ? String(free.name) : ""
}

// Why popups keep quiet by themselves right now: "sharing", "game",
// "fullscreen", or "" for not at all. `state` carries the three settings
// (suppressSharing, suppressGames, suppressFullscreen) beside what is the
// case: `shares` (shareCount), `gameActive`, `fullscreenActive` with the
// window's `appId` and the `exceptions` setting, and `elsewhere` - true when
// the popups go to another screen instead, where a fullscreen window holds
// nothing back. A game in front keeps them back on every screen. Unit tested.
function reason(state) {
    const it = state || {}
    if (it.suppressSharing === true && Number(it.shares) > 0) return "sharing"
    if (it.suppressGames === true && it.gameActive === true) return "game"
    if (it.suppressFullscreen === true && it.fullscreenActive === true && it.elsewhere !== true
        && !isException(it.appId, it.exceptions)) return "fullscreen"
    return ""
}

// ---- what came meanwhile --------------------------------------------------------
//
// `missed` (id -> true) with one more held back. The same table when it is
// in it already. Unit tested.
function withMissed(missed, id) {
    const table = missed || {}
    if (id === undefined || id === null || table[id] === true) return table
    const next = Object.assign({}, table)
    next[id] = true
    return next
}

// How many of the held-back ones are still to be seen: in the history and
// unread (`unseen`, id -> true). One read in the centre meanwhile, or closed,
// was seen or is gone - the notice is about what is still waiting. Unit
// tested.
function missedCount(missed, history, unseen) {
    const held = missed || {}
    const marks = unseen || {}
    let count = 0
    for (const notification of history || [])
        if (notification && held[notification.id] === true && marks[notification.id] === true) count += 1
    return count
}

// Why it was quiet, for the notice: Do Not Disturb first (it was what the
// user chose), else the automatic reason.
function quietCause(dndActive, autoReason) {
    return dndActive ? "dnd" : String(autoReason || "")
}

// The notice's two lines: "3 notifications", then "Came in while Do Not
// Disturb was on" and the like - one line of it was cut off on a popup.
// Unit tested.
function missedTitle(count) {
    const number = Math.max(0, Math.floor(Number(count) || 0))
    return number === 1 ? "1 notification" : number + " notifications"
}
function missedBody(cause) {
    return cause === "sharing" ? "Came in while you shared your screen"
        : cause === "game" ? "Came in while you played"
        : cause === "fullscreen" ? "Came in during fullscreen"
        : "Came in while Do Not Disturb was on"
}
