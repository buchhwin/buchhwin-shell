.pragma library

// Media popup helpers: find the PipeWire stream that belongs to an MPRIS
// player (for its volume) and step through loop modes.

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
