.pragma library

// VPN switches (NetworkService.setVpn): what a row shows while nmcli brings a
// tunnel up or down, and what its answer means. A switch used to be fired
// off and forgotten: the row said "Off" until NetworkManager's next event,
// 1.5 s later at the earliest, so it was clicked again; and a tunnel that
// could not come up (missing secrets, an endpoint out of reach) said nothing
// at all.

// `pending`: { uuid: { up, seq } } - the switches under way, each the latest
// one asked for that tunnel.

// A switch asked for → the new map.
function begin(pending, uuid, up, seq) {
    const next = Object.assign({}, pending || {})
    if (uuid) next[uuid] = { up: up === true, seq: seq }
    return next
}

// A switch has answered → { pending, current }: `current` false when a newer
// switch of the same tunnel came since (its answer, say "deactivated", is
// not news then, and the newer one stays pending).
function finish(pending, uuid, seq) {
    const entry = (pending || {})[uuid]
    if (!entry || entry.seq !== seq) return { pending: pending || {}, current: false }
    const next = Object.assign({}, pending)
    delete next[uuid]
    return { pending: next, current: true }
}

// Where a tunnel's switch stands: where it is going while a switch is under
// way, else where it is.
function checked(item, pending) {
    const entry = item ? (pending || {})[item.uuid] : null
    return entry ? entry.up : !!(item && item.active)
}

// The row's line under the name.
function status(item, pending) {
    const entry = item ? (pending || {})[item.uuid] : null
    if (entry) return entry.up ? "Connecting …" : "Disconnecting …"
    return item && item.active ? "Connected" : "Off"
}

// The quick tile's line while any switch is under way, else "".
function pendingText(pending) {
    const entries = Object.keys(pending || {}).map(uuid => pending[uuid])
    if (!entries.length) return ""
    return entries.some(entry => entry.up) ? "Connecting …" : "Disconnecting …"
}

// The connection list once a switch has answered that it is done: that
// tunnel where it was sent, before nmcli's list says so as well. The row
// would fall back to the list read before the switch for the moment the
// refresh takes, and the switch twitch back and forth. → the same list when
// nothing changes.
function settled(connections, uuid, up) {
    const list = Array.isArray(connections) ? connections : []
    let changed = false
    const next = list.map(item => {
        if (!item || item.uuid !== uuid || item.active === (up === true)) return item
        changed = true
        return Object.assign({}, item, { active: up === true })
    })
    return changed ? next : list
}

// The tunnel the quick tile brings up: the one used last, while it is still
// there, else the first.
function preferred(vpns, last) {
    const list = Array.isArray(vpns) ? vpns : []
    const found = list.find(item => item && item.uuid === last)
    return found ? found.uuid : list.length ? list[0].uuid : ""
}

// The answer of `nmcli connection up|down` with its exit status on the first
// line (NetworkService's wrapper) → { ok, message }. nmcli says why it failed
// as "Error: …", often followed by a "Hint:" about journalctl, which is left
// out.
function result(text) {
    const lines = String(text || "").split("\n")
    const code = parseInt(lines[0], 10)
    if (code === 0) return { ok: true, message: "" }
    const error = lines.slice(1).map(line => line.trim()).find(line => /^Error:/.test(line))
    const message = error ? error.replace(/^Error:\s*/, "")
        : lines.slice(1).map(line => line.trim()).find(line => line.length && !/^Hint:/.test(line)) || ""
    return { ok: false, message: message.length ? message : "nmcli exited with " + (isNaN(code) ? "an error" : code) }
}
