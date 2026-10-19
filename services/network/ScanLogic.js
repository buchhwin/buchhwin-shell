.pragma library

// Who keeps the Wi-Fi scan running, and what nmcli's answers say.
//
// The scan: every network view - the popup, the control-center page, the
// settings page - says when it arrives (true) and when it leaves (false), in
// pairs. Counted rather than switched, because the last view out used to win:
// the popup's "Network settings" link or the control center's gear opened
// Settings, whose page started the scan, and the popup's body, torn down
// about 260 ms later, stopped it again under the page (as
// BluetoothLogic.discoveryStep for the Bluetooth search).
function scanViewers(viewers, value) {
    const count = Math.max(0, Math.round(Number(viewers)) || 0)
    return value ? count + 1 : Math.max(0, count - 1)
}

// ---- nmcli's answers --------------------------------------------------------

// One line of `nmcli -t` as its fields: ':' separates them, and a ':' or '\'
// inside a value comes escaped ('\:', '\\').
function splitTerse(line) {
    const text = String(line || "")
    const fields = []
    let field = ""
    for (let i = 0; i < text.length; ++i) {
        const ch = text[i]
        if (ch === "\\" && i + 1 < text.length) { field += text[++i]; continue }
        if (ch === ":") { fields.push(field); field = ""; continue }
        field += ch
    }
    fields.push(field)
    return fields
}

// `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE connection show` →
// { connections: [{ name, uuid, type, device, active }], wired, device, hotspot }:
// `wired` while an ethernet connection is up, `device` the first Wi-Fi or
// ethernet device in use (for its address), `hotspot` while the connection
// named `hotspotName` is active - the same test network-helper.py's
// hotspot-status makes over D-Bus (an active connection with that id), which
// cost a python start per network view open and per NetworkManager event
// while one was open.
function parseConnections(text, hotspotName) {
    const connections = []
    let wired = false
    let device = ""
    let hotspot = false
    for (const line of String(text || "").split("\n")) {
        if (!line.length) continue
        const [name, uuid, type, dev, active] = splitTerse(line)
        const shortType = String(type || "").replace("802-11-wireless", "wifi").replace("802-3-ethernet", "ethernet")
        const isActive = active === "yes"
        connections.push({ name: name || "", uuid: uuid || "", type: shortType, device: dev || "", active: isActive })
        if (isActive && shortType === "ethernet") wired = true
        if (isActive && (shortType === "wifi" || shortType === "ethernet") && !device.length) device = dev || ""
        if (isActive && hotspotName && name === hotspotName) hotspot = true
    }
    return { connections: connections, wired: wired, device: device, hotspot: hotspot }
}

// Whether a line of `nmcli monitor` is news. The first line it prints is
// "NetworkManager is running" - the state at its start, not a change - and
// counted as one it ran the whole refresh again 1.5 s after the shell's own
// at start, and after every restart of the monitor. Later banners (NetworkManager
// stopped, or back) are news.
function monitorNews(line, first) {
    return !(first === true && /^NetworkManager is (running|stopped)/.test(String(line || "")))
}
