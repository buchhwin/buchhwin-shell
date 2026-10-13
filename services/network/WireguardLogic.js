.pragma library

// The "New WireGuard tunnel" form (Settings > Network): what each field must
// look like, the interface name a tunnel's name turns into, and the wg-quick
// configuration the form becomes. scripts/wireguard-helper.py parses that
// text and checks it again, so a file and the form take one road into
// NetworkManager. Unit tested in WireguardTest.qml.

// 32 bytes in base64: 43 characters and a padding "=", the last character
// before it one of the sixteen a 256-bit value can end in.
function isKey(value) {
    return /^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$/.test(String(value || "").trim())
}

function list(value) {
    return String(value || "").split(",").map(item => item.trim()).filter(item => item.length)
}

function isIPv4(text) {
    const parts = String(text).split(".")
    return parts.length === 4 && parts.every(part => /^\d{1,3}$/.test(part) && Number(part) <= 255)
}

function isIPv6(text) {
    const value = String(text)
    return /^[0-9A-Fa-f:]+$/.test(value) && value.indexOf(":") >= 0 && (value.match(/::/g) || []).length <= 1
}

// "10.0.0.2/32", "fd00::2/128"; a bare address counts as one host.
function isCidr(text) {
    const [address, prefix] = String(text).split("/")
    if (prefix !== undefined && !/^\d{1,3}$/.test(prefix)) return false
    if (isIPv4(address)) return prefix === undefined || Number(prefix) <= 32
    if (isIPv6(address)) return prefix === undefined || Number(prefix) <= 128
    return false
}

// "host:port" or "[v6]:port".
function isEndpoint(text) {
    const match = /^(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.-]+):(\d{1,5})$/.exec(String(text || "").trim())
    return !!match && Number(match[2]) >= 1 && Number(match[2]) <= 65535
}

// The kernel allows 15 characters; the tunnel's name, lower case, the rest
// turned into dashes, with "wg-" in front so it says what it is.
function interfaceName(name) {
    const slug = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return ("wg-" + (slug.length ? slug : "tunnel")).slice(0, 15).replace(/-+$/, "")
}

// field -> what is wrong with it; an empty object is a form that can be sent.
function errors(form) {
    const f = form || {}
    const result = {}
    if (!String(f.name || "").trim().length) result.name = "A name"
    if (!list(f.address).length || !list(f.address).every(isCidr)) result.address = "An address such as 10.0.0.2/32"
    if (list(f.dns).some(server => !isIPv4(server) && !isIPv6(server))) result.dns = "Addresses only, separated by commas"
    if (!isKey(f.privateKey)) result.privateKey = "A WireGuard key; Generate makes one"
    if (!isKey(f.peerKey)) result.peerKey = "The server's public key"
    if (String(f.presharedKey || "").trim().length && !isKey(f.presharedKey)) result.presharedKey = "A WireGuard key, or nothing"
    if (!isEndpoint(f.endpoint)) result.endpoint = "host:port, such as vpn.example.org:51820"
    if (!list(f.allowedIps).length || !list(f.allowedIps).every(isCidr)) result.allowedIps = "Networks such as 0.0.0.0/0, ::/0"
    const keepalive = String(f.keepalive || "").trim()
    if (keepalive.length && !(/^\d+$/.test(keepalive) && Number(keepalive) <= 65535)) result.keepalive = "Seconds, or nothing"
    return result
}

// The form as a wg-quick configuration.
function config(form) {
    const f = form || {}
    const lines = ["[Interface]", "PrivateKey = " + String(f.privateKey).trim(),
                   "Address = " + list(f.address).join(", ")]
    if (list(f.dns).length) lines.push("DNS = " + list(f.dns).join(", "))
    lines.push("", "[Peer]", "PublicKey = " + String(f.peerKey).trim())
    if (String(f.presharedKey || "").trim().length) lines.push("PresharedKey = " + String(f.presharedKey).trim())
    lines.push("Endpoint = " + String(f.endpoint).trim(), "AllowedIPs = " + list(f.allowedIps).join(", "))
    if (String(f.keepalive || "").trim().length) lines.push("PersistentKeepalive = " + String(f.keepalive).trim())
    return lines.join("\n") + "\n"
}

// A file's name as the tunnel's: "office-vpn.conf" -> "office-vpn".
function nameFromPath(path) {
    const base = String(path || "").split("/").pop()
    return base.replace(/\.conf$/i, "") || "WireGuard"
}
