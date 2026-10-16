.pragma library

// Media popup helpers: find the PipeWire stream that belongs to an MPRIS
// player (for its volume), step through loop modes, tell a real track length
// from a live stream's, format times, and fit the player chips into a row.

function normalize(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
}

// Names an MPRIS player is known by: identity ("Elisa"), desktop entry and
// its last segment ("org.kde.elisa" → "elisa") and the bus name
// ("org.mpris.MediaPlayer2.chromium.instance42" → "chromium", pid 42).
function playerKeys(player) {
    const keys = []
    const add = value => { const key = normalize(value); if (key.length > 1 && keys.indexOf(key) < 0) keys.push(key) }
    add(player.identity)
    const entry = String(player.desktopEntry || "")
    add(entry)
    const segments = entry.split(".")
    if (segments.length > 1) add(segments[segments.length - 1])
    const bus = String(player.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "")
    add(bus.split(".")[0])
    const instance = bus.match(/\.instance(\d+)$/)
    return { names: keys, pid: instance ? Number(instance[1]) : 0 }
}

// streams: [{ appName, binary, appId, pid }]; returns the index of the
// matching stream or -1. A process id match wins over a name match.
function streamIndex(player, streams) {
    if (!player || !streams || !streams.length) return -1
    const keys = playerKeys(player)
    if (keys.pid > 0) {
        const byPid = streams.findIndex(stream => Number(stream.pid) === keys.pid)
        if (byPid >= 0) return byPid
    }
    return streams.findIndex(stream => [stream.appName, stream.binary, stream.appId]
        .map(normalize).some(name => name.length > 1 && keys.names.indexOf(name) >= 0))
}

// Loop button order: off → whole list → one track → off (MprisLoopState
// None = 0, Track = 1, Playlist = 2).
function nextLoopState(state) {
    return state === 0 ? 2 : state === 2 ? 1 : 0
}

// ---- length and time --------------------------------------------------------
// The longest track taken at its word: about 115 days. A live stream has no
// end, and players say so in different ways - no length, zero, or the
// largest number the protocol can carry (INT64_MAX µs, 9.2e12 s), which the
// popup turned into a remaining time of "−153722867280:48" and a seek bar
// that went nowhere. Anything past this is "no length".
var MAX_LENGTH = 1e7

// The length a player reports when it is a real one, else 0. `supported` is
// MPRIS's lengthSupported: without it the number means nothing.
function realLength(supported, length) {
    const value = Number(length)
    return supported === true && isFinite(value) && value > 0 && value < MAX_LENGTH ? value : 0
}

// m:ss, or h:mm:ss once either the time itself or the track it belongs to
// (`reference`, its length) reaches an hour - so the elapsed and the
// remaining time of a long track keep one shape ("0:05:00" beside
// "−1:25:00") instead of switching it at the hour.
function formatTime(seconds, reference) {
    const total = Math.max(0, Math.floor(isFinite(Number(seconds)) ? Number(seconds) : 0))
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const rest = String(total % 60).padStart(2, "0")
    if (hours > 0 || Number(reference) >= 3600)
        return hours + ":" + String(minutes).padStart(2, "0") + ":" + rest
    return minutes + ":" + rest
}

// ---- the player chips -----------------------------------------------------
// One row of chips, one per player, in a row `room` wide. Returns how many of
// them to show: all when they fit side by side, otherwise as many as fit
// with the "+N" chip (`moreWidth`) after them. Never negative; zero leaves
// only the "+N" chip, which still reaches every player.
function chipsThatFit(widths, room, spacing, moreWidth) {
    const list = widths || []
    const gap = Math.max(0, Number(spacing) || 0)
    let used = 0
    for (let index = 0; index < list.length; ++index)
        used += Math.max(0, Number(list[index]) || 0) + (index > 0 ? gap : 0)
    if (used <= room) return list.length
    let shown = 0
    used = Math.max(0, Number(moreWidth) || 0)
    for (let index = 0; index < list.length; ++index) {
        const next = used + gap + Math.max(0, Number(list[index]) || 0)
        if (next > room) break
        used = next
        shown += 1
    }
    return shown
}

// Which player the "+N" chip selects: the hidden one after the active one if
// the active one is hidden too, else the first hidden one - so pressing it
// again walks through every player the row had no room for. -1 when none is
// hidden.
function nextHiddenIndex(count, shown, active) {
    if (shown >= count) return -1
    if (active >= shown && active < count - 1) return active + 1
    return shown
}

// ---- cover art ---------------------------------------------------------------
// What MprisService does with a player's art url, by its scheme - in any case,
// as URL schemes are (RFC 3986): "remote" for http(s), which curl fetches
// into the cache; "file" for a path, checked once before it is handed out;
// "data" for a picture inline in the url, handed straight on; "none" for
// nothing and for every other scheme. "none" hands out no art at all: a url
// handed on unchecked is fetched by Qt's own network stack in each of the
// seven Images that show it - the lock screen's among them - which is the
// path the curl fetch exists to keep the shell out of (pitfall 28). A player
// that said "HTTPS://" went that way while the check read only lower case.
function artKind(url) {
    const text = String(url || "")
    if (/^https?:\/\//i.test(text)) return "remote"
    if (/^file:\/\//i.test(text)) return "file"
    if (/^data:/i.test(text)) return "data"
    return "none"
}

// The path of a file:// url, decoded; "" for anything else. A bare "%" in a
// file name is a malformed escape and throws; the undecoded path is the
// better guess then.
function artPath(url) {
    if (artKind(url) !== "file") return ""
    const rest = String(url).slice("file://".length)
    try { return decodeURIComponent(rest) } catch (error) { return rest }
}

// The url an art file is handed out as once checked: the player's own, with
// the scheme in the lower case every consumer expects.
function artFileUrl(url) {
    return artKind(url) === "file" ? "file://" + String(url).slice("file://".length) : ""
}
