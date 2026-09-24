.pragma library

// KDE Connect for Settings > Phone: parses scripts/kdeconnect-status.sh and
// scripts/kdeconnect-notifications.sh output (sections of busctl JSON from the
// daemon), builds device rows with what the phone's plugins report (battery,
// cellular signal, media player, mirrored notifications, lock state) and the
// argv lists for actions (kdeconnect-cli, kdeconnect-sms, busctl). Device and
// notification ids are validated before they reach a command line or a D-Bus
// object path, and so are shared links, texts, player names and volumes.

// Pair states of org.kde.kdeconnect.device.pairState.
var PAIR_NONE = 0
var PAIR_REQUESTED = 1
var PAIR_REQUESTED_BY_PEER = 2
var PAIR_PAIRED = 3

function validId(id) {
    return typeof id === "string" && /^[A-Za-z0-9_]{1,128}$/.test(id)
}

// busctl --json=short value: {"type":"s","data":…}. Method calls wrap the
// return values in an array, properties do not.
function busValue(text, isCall) {
    let parsed
    try { parsed = JSON.parse(String(text || "").trim()) } catch (error) { return undefined }
    if (!parsed || typeof parsed !== "object" || !("data" in parsed)) return undefined
    return isCall ? (Array.isArray(parsed.data) ? parsed.data[0] : undefined) : parsed.data
}

// Properties.GetAll result → plain object of property values.
function busProperties(text) {
    const map = busValue(text, true)
    const result = {}
    if (!map || typeof map !== "object" || Array.isArray(map)) return result
    for (const key of Object.keys(map)) {
        const variant = map[key]
        if (variant && typeof variant === "object" && "data" in variant) result[key] = variant.data
    }
    return result
}

// Splits the status script output into sections keyed "@name arg".
function sections(text) {
    const result = []
    let current = null
    for (const line of String(text || "").split("\n")) {
        const match = /^@([a-z]+)(?: (.*))?$/.exec(line)
        if (match) {
            current = { name: match[1], arg: (match[2] || "").trim(), lines: [] }
            result.push(current)
        } else if (current) {
            current.lines.push(line)
        }
    }
    return result
}

// Daemon deviceNames (id → name) → [{ id, name }] with valid ids only.
function deviceList(text) {
    const names = busValue(text, true)
    if (!names || typeof names !== "object" || Array.isArray(names)) return []
    return Object.keys(names).filter(validId).map(id => ({ id: id, name: String(names[id]) }))
}

// connectivity_report properties → { type, strength } (strength 0–4, -1 for
// "no signal or unknown"); null when the phone does not report a SIM at all.
function connectivity(props) {
    if (!props || typeof props !== "object") return null
    const type = typeof props.cellularNetworkType === "string" ? props.cellularNetworkType : ""
    const raw = typeof props.cellularNetworkStrength === "number" ? props.cellularNetworkStrength : -1
    if (!type.length && raw < 0) return null
    return { type: type === "Unknown" ? "" : type, strength: raw < 0 ? -1 : Math.max(0, Math.min(4, Math.round(raw))) }
}

// mprisremote properties → the current player; null while the phone has none.
function media(props) {
    if (!props || typeof props !== "object") return null
    const players = Array.isArray(props.playerList)
        ? props.playerList.filter(name => typeof name === "string" && name.length) : []
    if (!players.length) return null
    const volume = typeof props.volume === "number" ? Math.round(props.volume) : -1
    return {
        players: players,
        player: typeof props.player === "string" ? props.player : "",
        playing: props.isPlaying === true,
        title: typeof props.title === "string" ? props.title : "",
        artist: typeof props.artist === "string" ? props.artist : "",
        album: typeof props.album === "string" ? props.album : "",
        volume: volume >= 0 && volume <= 100 ? volume : -1
    }
}

// The runcommand plugin reports its commands as a JSON string of its own:
// { "<key>": { "name": "…", "command": "…" } }. The command line itself is not
// kept - the phone runs it, and it would only be a line to leak.
function remoteCommands(raw) {
    if (typeof raw !== "string" || !raw.length) return []
    let data = null
    try {
        data = JSON.parse(raw)
    } catch (error) {
        return []
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) return []
    return Object.keys(data).filter(validId).map(key => {
        const entry = data[key] || {}
        const name = typeof entry.name === "string" ? entry.name.trim() : ""
        return { key: key, name: name.length ? name : "Command" }
    }).sort((a, b) => a.name.localeCompare(b.name))
}

function device(entry, props, battery, key, extra) {
    const p = props || {}
    const more = extra || {}
    const paired = p.isPaired === true
    const reachable = p.isReachable === true
    const pairState = typeof p.pairState === "number" ? p.pairState
        : paired ? PAIR_PAIRED : PAIR_NONE
    const plugins = Array.isArray(p.supportedPlugins) ? p.supportedPlugins.filter(name => typeof name === "string") : []
    let charge = null
    if (battery && typeof battery.charge === "number" && battery.charge >= 0 && battery.charge <= 100)
        charge = { charge: Math.round(battery.charge), charging: battery.isCharging === true }
    const notifications = Array.isArray(more.notifications) ? more.notifications.filter(validId) : []
    return {
        id: entry.id,
        name: typeof p.name === "string" && p.name.length ? p.name : entry.name,
        type: typeof p.type === "string" ? p.type : "",
        paired: paired,
        reachable: reachable,
        requestedByPeer: p.isPairRequestedByPeer === true || pairState === PAIR_REQUESTED_BY_PEER,
        requested: p.isPairRequested === true || pairState === PAIR_REQUESTED,
        plugins: plugins,
        battery: charge,
        connectivity: connectivity(more.connectivity),
        media: media(more.mpris),
        locked: !!(more.lock && more.lock.isLocked === true),
        notificationCount: notifications.length,
        commands: remoteCommands(more.commands),
        mounted: more.mounted === true,
        verificationKey: typeof key === "string" ? key : ""
    }
}

// Whole snapshot → { daemon, selfId, name, devices, requests }.
function parseStatus(text) {
    const result = { daemon: false, known: false, selfId: "", name: "", devices: [], requests: [] }
    const props = {}
    const batteries = {}
    const keys = {}
    const extras = {}
    function extra(id) {
        if (!extras[id]) extras[id] = {}
        return extras[id]
    }
    let entries = []
    for (const section of sections(text)) {
        const body = section.lines.join("\n")
        if (section.name === "daemon") {
            result.known = true
            result.daemon = section.arg === "running"
        } else if (section.name === "self") {
            const id = busValue(body, true)
            result.selfId = validId(id) ? id : ""
        } else if (section.name === "name") {
            const name = busValue(body, true)
            result.name = typeof name === "string" ? name : ""
        } else if (section.name === "devices") {
            entries = deviceList(body)
        } else if (section.name === "requests") {
            const requests = busValue(body, false)
            result.requests = Array.isArray(requests) ? requests.filter(validId) : []
        } else if (validId(section.arg)) {
            if (section.name === "device") props[section.arg] = busProperties(body)
            else if (section.name === "battery") batteries[section.arg] = busProperties(body)
            else if (section.name === "key") keys[section.arg] = busValue(body, true)
            else if (section.name === "connectivity") extra(section.arg).connectivity = busProperties(body)
            else if (section.name === "mpris") extra(section.arg).mpris = busProperties(body)
            else if (section.name === "lock") extra(section.arg).lock = busProperties(body)
            else if (section.name === "notify") {
                const ids = busValue(body, true)
                extra(section.arg).notifications = Array.isArray(ids) ? ids : []
            }
            else if (section.name === "commands") extra(section.arg).commands = busValue(body, true)
            else if (section.name === "sftp") extra(section.arg).mounted = busValue(body, true) === true
        }
    }
    result.devices = sortDevices(entries.map(entry =>
        device(entry, props[entry.id], batteries[entry.id], keys[entry.id], extras[entry.id])))
    for (const item of result.devices)
        if (result.requests.indexOf(item.id) >= 0) item.requestedByPeer = true
    return result
}

// Incoming requests first, then connected, paired, available; by name.
function rank(item) {
    if (item.requestedByPeer) return 0
    if (item.paired && item.reachable) return 1
    if (item.paired) return 2
    return 3
}

function sortDevices(devices) {
    return devices.slice().sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name) || a.id.localeCompare(b.id))
}

function stateText(item) {
    if (item.requestedByPeer) return "Wants to pair"
    if (item.requested) return "Waiting for the phone to accept…"
    if (item.paired && item.reachable) return "Connected"
    if (item.paired) return "Paired, not reachable"
    if (item.reachable) return "Available to pair"
    return "Not paired"
}

function batteryText(battery) {
    if (!battery) return ""
    return (battery.charging ? "Charging · " : "") + battery.charge + "%"
}

// Cellular signal as the phone reports it (0–4, -1 unknown).
var SIGNAL_LABELS = ["No signal", "Weak", "Fair", "Good", "Excellent"]

function signalText(conn) {
    if (!conn) return ""
    const label = conn.strength < 0 ? "No signal" : SIGNAL_LABELS[conn.strength]
    return conn.type.length ? conn.type + " · " + label : label
}

function signalIcon(conn) {
    if (!conn || conn.strength <= 0) return "󰤯"
    return conn.strength >= 4 ? "󰤨" : conn.strength === 3 ? "󰤥" : conn.strength === 2 ? "󰤢" : "󰤟"
}

// One line under the device name: state, battery and signal.
function detailText(item) {
    const parts = [stateText(item)]
    const battery = batteryText(item.battery)
    if (battery.length) parts.push(battery)
    const signal = signalText(item.connectivity)
    if (signal.length) parts.push(signal)
    if (item.locked) parts.push("Locked")
    return parts.join(" · ")
}

function mediaTitle(player) {
    if (!player) return ""
    return player.title.length ? player.title : player.player.length ? player.player : "Media"
}

function mediaSubtitle(player) {
    if (!player) return ""
    const parts = []
    if (player.artist.length) parts.push(player.artist)
    else if (player.album.length) parts.push(player.album)
    if (player.title.length && player.player.length) parts.push(player.player)
    parts.push(player.playing ? "Playing" : "Paused")
    return parts.join(" · ")
}

// Phone notification objects → rows for the read-only list. Newest first:
// public ids are a counter in the daemon, activeNotifications() is unordered.
function parseNotifications(text) {
    const result = []
    for (const section of sections(text)) {
        if (section.name !== "item" || !validId(section.arg)) continue
        const p = busProperties(section.lines.join("\n"))
        const title = typeof p.title === "string" ? p.title : ""
        const ticker = typeof p.ticker === "string" ? p.ticker : ""
        result.push({
            id: section.arg,
            appName: typeof p.appName === "string" ? p.appName : "",
            title: title.length ? title : ticker,
            text: typeof p.text === "string" ? p.text : "",
            dismissable: p.dismissable === true,
            // A notification that can be answered carries the id its answer
            // has to go back with; one without it has no reply action on the
            // phone, and the field is not offered there.
            replyId: typeof p.replyId === "string" ? p.replyId : ""
        })
    }
    return result.sort((a, b) => (Number(b.id) || 0) - (Number(a.id) || 0))
}

function notificationCountText(count) {
    return count === 1 ? "1 notification" : count + " notifications"
}

function deviceIcon(type) {
    return type === "tablet" ? "󰓶" : type === "desktop" ? "󰇄" : type === "laptop" ? "󰌢" : type === "tv" ? "󰔂" : "󰄜"
}

// Plugins the phone supports; an empty list (older daemons) allows all.
function supports(item, plugin) {
    return !item.plugins.length || item.plugins.indexOf("kdeconnect_" + plugin) >= 0
}

function summary(status) {
    if (!status.known) return "Checking KDE Connect…"
    if (!status.daemon) return "KDE Connect is not running"
    const connected = status.devices.filter(item => item.paired && item.reachable).length
    const paired = status.devices.filter(item => item.paired).length
    if (!paired) return "No paired phones"
    return connected + " connected · " + paired + " paired"
}

// Actions the mprisremote plugin accepts (the phone's own player names them).
var MEDIA_ACTIONS = { play: "PlayPause", next: "Next", previous: "Previous" }
var MPRIS = "org.kde.kdeconnect.device.mprisremote"
var REMOTE_COMMANDS = "org.kde.kdeconnect.device.remotecommands"
var SFTP = "org.kde.kdeconnect.device.sftp"

function busArgs(verb, path, iface) {
    return ["busctl", "--user", "--auto-start=no", verb, "org.kde.kdeconnect", path, iface]
}

// Commands for one device action; null for unknown actions or invalid input.
// The id and paths are always their own argv entries.
function command(action, id, extra) {
    if (!validId(id)) return null
    const cli = ["kdeconnect-cli", "--device", id]
    const path = "/modules/kdeconnect/devices/" + id
    const bus = busArgs("call", path, "org.kde.kdeconnect.device")
    switch (action) {
    case "pair": return cli.concat(["--pair"])
    case "unpair": return cli.concat(["--unpair"])
    case "ping": return cli.concat(["--ping"])
    case "ring": return cli.concat(["--ring"])
    case "clipboard": return cli.concat(["--send-clipboard"])
    case "share": return validFile(extra) ? cli.concat(["--share", extra]) : null
    case "url": return validUrl(extra) ? cli.concat(["--share", extra]) : null
    case "text": return validText(extra) ? cli.concat(["--share-text", extra]) : null
    case "lock": return cli.concat(["--lock"])
    case "unlock": return cli.concat(["--unlock"])
    case "sms": return ["kdeconnect-sms", "--device", id]
    case "accept": return bus.concat(["acceptPairing"])
    case "reject": return bus.concat(["rejectPairing"])
    case "play":
    case "next":
    case "previous":
        return busArgs("call", path + "/mprisremote", MPRIS).concat(["sendAction", "s", MEDIA_ACTIONS[action]])
    case "volume":
        return validVolume(extra)
            ? busArgs("set-property", path + "/mprisremote", MPRIS).concat(["volume", "i", String(Math.round(extra))]) : null
    case "player":
        return validPlayer(extra)
            ? busArgs("set-property", path + "/mprisremote", MPRIS).concat(["player", "s", extra]) : null
    case "dismiss":
        return validId(extra)
            ? busArgs("call", path + "/notifications/" + extra,
                      "org.kde.kdeconnect.device.notifications.notification").concat(["dismiss"]) : null
    // Answering a notification: the id and the text arrive together, because
    // the object path holds the one and the argument the other.
    // sendReply takes the text; the plain reply() only opens a dialog.
    case "reply":
        return extra && validId(extra.note) && validText(extra.text)
            ? busArgs("call", path + "/notifications/" + extra.note,
                      "org.kde.kdeconnect.device.notifications.notification").concat(["sendReply", "s", extra.text]) : null
    // A command the phone offers (runcommand plugin). The key is a hash the
    // phone made up, so it is checked like every other id that becomes an
    // argument.
    case "runCommand":
        return validId(extra)
            ? busArgs("call", path + "/remotecommands", REMOTE_COMMANDS).concat(["triggerCommand", "s", extra]) : null
    // Browsing the phone: the daemon mounts it over SFTP and opens the file
    // manager itself, so nothing here has to know where it landed.
    case "browse":
        return busArgs("call", path + "/sftp", SFTP).concat(["startBrowsing"])
    default: return null
    }
}

function validFile(path) {
    return typeof path === "string" && path.charAt(0) === "/" && path.indexOf("\n") < 0 && path.length < 4096
}

function validUrl(url) {
    return typeof url === "string" && url.length <= 2048 && /^https?:\/\/[^\s]+$/i.test(url)
}

function validText(text) {
    return typeof text === "string" && text.trim().length > 0 && text.length <= 8192
}

function validVolume(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= 100
}

function validPlayer(name) {
    return typeof name === "string" && name.length > 0 && name.length <= 256 && name.indexOf("\n") < 0
}

// "Send link or text": a web address is opened on the phone (share plugin
// shareUrl), everything else arrives as text. Bare hosts get https://, and a
// bare host's last label holds a letter - "1.5" or "v2.0" is text, not a site.
var BARE_HOST = /^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z0-9-]*[a-z][a-z0-9-]*(\/\S*)?$/i

function shareAction(input) {
    const value = String(input === undefined || input === null ? "" : input).trim()
    if (!value.length) return null
    if (/^(https?:\/\/|www\.)\S+$/i.test(value) || BARE_HOST.test(value)) {
        const url = /^https?:\/\//i.test(value) ? value : "https://" + value
        if (validUrl(url)) return { action: "url", value: url }
    }
    return validText(value) ? { action: "text", value: value } : null
}

// kdialog --multiple --separate-output: one absolute path per line.
function parseFiles(text) {
    return String(text || "").split("\n").filter(validFile)
}
