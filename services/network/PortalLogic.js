.pragma library

// Captive portals: a hotel's, a train's or a guest network's sign-in page.
// NetworkManager's connectivity check finds one ("portal"), and the shell
// drew the "!" and wrote "Sign-in required" (SignalLogic) - and then left the
// user to guess an address the portal would catch. This decides when the
// way to the page is offered and where it leads; NetworkService opens it in
// the default browser on a click and sends the one notification.

// Where the browser goes when NetworkManager names no check address of its
// own: a page that is plain http on purpose, so the portal can answer in
// its place. An https page is never intercepted (the browser refuses the
// portal's certificate), and neither is a page the browser upgrades to https.
var FALLBACK_URL = "http://neverssl.com"

// How long a network that has notified once stays quiet, even after it
// reached the internet in between: NetworkManager's check runs again every
// few minutes and on each change, and a portal that flaps between "full"
// and "portal" would otherwise notify on every turn.
var COOLDOWN_MS = 10 * 60 * 1000

// Whether the way to the sign-in page is offered: a portal, once "no
// internet" has held for the settle time (`limited`, NetworkService's
// settled flag - a reconnect reports a portal for a moment before the check
// has run).
function signInNeeded(connectivity, limited) {
    return limited === true && connectivity === "portal"
}

// The connection a portal belongs to, as a key: the Wi-Fi network by its
// name, a wired connection as one. "" while there is none.
function connectionKey(wifiName, wired) {
    const name = String(wifiName || "")
    if (name.length) return "wifi:" + name
    return wired === true ? "wired" : ""
}

// The network as the notice and the button name it.
function networkName(wifiName, wired) {
    const name = String(wifiName || "")
    if (name.length) return name
    return wired === true ? "the wired network" : "this network"
}

// One step of the notification's state. `state`: { notified: { key: { at,
// cleared } } }, kept for the session. `input`: { key, portal, full, now,
// enabled } - `portal` the settled sign-in state, `full` whether the
// connection reaches the internet now.
// → { state, notify, dismiss }: `notify` once per network until it reached
// the internet (signed in) and the cooldown has passed, never twice on a
// flap of the check or of the Wi-Fi; `dismiss` when the internet is back
// for a network that has a notice out, which is then pointless.
function notifyStep(state, input) {
    const notified = Object.assign({}, state && state.notified ? state.notified : {})
    const now = Number(input && input.now) || 0
    const key = String(input && input.key || "")
    let notify = false
    let dismiss = false
    if (key.length) {
        const entry = notified[key]
        if (input.full === true && entry && !entry.cleared) {
            notified[key] = { at: entry.at, cleared: true }
            dismiss = true
        } else if (input.portal === true && input.enabled !== false) {
            const quiet = entry && (!entry.cleared || now - entry.at < COOLDOWN_MS)
            if (!quiet) {
                notified[key] = { at: now, cleared: false }
                notify = true
            }
        }
    }
    return { state: { notified: notified }, notify: notify, dismiss: dismiss }
}

// The notification for `name` (networkName).
function notice(name) {
    return {
        title: "Sign in to " + String(name || "this network"),
        body: "This network asks you to sign in before it reaches the internet.",
        icon: "network-wireless"
    }
}

// What `busctl get-property … ConnectivityCheckUri` printed (`s "http://…"`)
// → the address, or "".
function parseUri(text) {
    const match = /^\s*s\s+"((?:[^"\\]|\\.)*)"\s*$/.exec(String(text || "").split("\n")[0] || "")
    return match ? match[1].replace(/\\(.)/g, "$1") : ""
}

// The address the browser opens: NetworkManager's check address while it is
// a plain http one (the portal answers it in its place - that is how
// NetworkManager found the portal), else the fallback.
function signInUrl(uri) {
    const text = String(uri || "").trim()
    return /^http:\/\/[^\s/?#]+[^\s]*$/i.test(text) ? text : FALLBACK_URL
}
