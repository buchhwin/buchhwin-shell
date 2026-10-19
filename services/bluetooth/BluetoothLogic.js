.pragma library

// Pure decisions for BluetoothService and the pairing dialog: who keeps
// discovery running, what a typed passkey means, when the pairing agent runs
// and what follows a pairing. Nothing here talks to BlueZ.

// ---- discovery --------------------------------------------------------------

// One step of the discovery count: a view arriving (`value` true) or leaving
// (false), against the adapter as it is now. → { viewers, start } where
// `start` is true to ask BlueZ to search, false to ask it to stop, and null to
// ask nothing at all.
//
// Counted rather than switched, because the last view out used to win: the
// popup's "Bluetooth settings" link opened Settings, whose page started the
// search, and the popup's body, torn down 260 ms later, stopped it again under
// the page meant for pairing.
//
// Asked only when the answer changes: BlueZ answers a StartDiscovery on an
// adapter that is already searching with "Operation already in progress".
//
// A view arriving while the search should be running and is not (BlueZ
// refused or dropped it) is Settings' "Search again": a retry, not one more
// viewer. Counted, it would be a viewer nobody ever lets go of, and the search
// would outlive every page.
function discoveryStep(viewers, value, enabled, discovering) {
    const count = Math.max(0, Number(viewers) || 0)
    if (value && count > 0 && enabled && !discovering)
        return { viewers: count, start: true }
    const next = value ? count + 1 : Math.max(0, count - 1)
    if (!enabled) return { viewers: next, start: null }
    const wanted = next > 0
    return { viewers: next, start: wanted === !!discovering ? null : wanted }
}

// ---- pairing ----------------------------------------------------------------

// The six digits of a passkey as typed, or "" while it is not one. Spaces are
// left out: the dialog itself prints codes as "482 913", so typing one that
// way is what the dialog taught. BlueZ takes 0-999999 and devices show all six
// digits, leading zeros included, so six it is.
function passkey(text) {
    const digits = String(text || "").replace(/\s+/g, "")
    return /^\d{6}$/.test(digits) ? digits : ""
}

// Whether what is typed so far can still become a passkey: digits and spaces
// only, and no more than six digits. Anything else is marked at once rather
// than refused by the agent after Confirm, which closed the dialog without a
// word.
function passkeyPossible(text) {
    const digits = String(text || "").replace(/\s+/g, "")
    return /^\d{0,6}$/.test(digits)
}

// ---- the pairing agent --------------------------------------------------------

// Whether scripts/bluetooth-agent.py runs. It answers what BlueZ asks while a
// pairing comes in or is under way, and nothing else, so it runs only then:
// while the adapter is switched on and a Bluetooth view is open (that is where
// pairings start), the adapter is discoverable (others may pair now), a
// pairing this shell started is under way or just ended (`grace`), some
// device is pairing, or a paired device is not trusted yet - BlueZ asks the
// agent before each connection of one of those ("wants to use a service"). A
// question or a code on screen keeps it whatever else changed. Off while the
// adapter is off: BlueZ cannot pair or ask anything then. The agent registers
// within a fraction of a second of a view opening, long before the first
// pairing can start there. `state`: { enabled, viewers, discoverable, grace,
// pairing, untrusted, asking }.
function agentWanted(state) {
    const s = state || {}
    if (s.asking === true) return true
    if (s.enabled !== true) return false
    return (Number(s.viewers) || 0) > 0 || s.discoverable === true || s.grace === true
        || s.pairing === true || s.untrusted === true
}

// The agent's process has stopped. A stop the shell asked for (`asked`, or
// `wanted` false: Bluetooth switched off, the last view gone) or one during
// a pause is no failure → null - unless it is wanted again by the time it is
// gone (a view reopened while the agent was saying goodbye), when it starts
// again at once (retryIn 0): Quickshell ignores a start while the old run is
// still exiting. Any other stop is a failure, counted, and the next start
// comes after a backoff of 5 s, doubling → { failures, retryIn }, with retryIn
// -1 once five have failed (the agent stays off then).
function agentStopped(failures, wanted, paused, asked) {
    const count = Math.max(0, Math.floor(Number(failures) || 0))
    if (paused === true) return null
    if (asked === true) return wanted === true ? { failures: count, retryIn: 0 } : null
    if (wanted !== true) return null
    return { failures: count + 1, retryIn: count + 1 > 5 ? -1 : 5000 * Math.pow(2, count) }
}

// ---- after a pairing ------------------------------------------------------------

// A device's address from its BlueZ object path (…/dev_00_11_22_33_44_55),
// or "".
function addressFromPath(path) {
    const match = /dev_([0-9A-Fa-f]{2}(?:_[0-9A-Fa-f]{2}){5})$/.exec(String(path || ""))
    return match ? match[1].replace(/_/g, ":").toUpperCase() : ""
}

// The state of the device a path or address names, among `states`
// ([{ address, path, paired, pairing, connected, trusted }]), or null.
function stateFor(states, path, address) {
    const list = Array.isArray(states) ? states : []
    const wanted = String(address || addressFromPath(path)).toUpperCase()
    return list.find(item => item && ((path && item.path === path)
        || (wanted.length && String(item.address || "").toUpperCase() === wanted))) || null
}

// A pairing this shell starts (toggleConnection): remembered by address until
// it is over. → the new map ({ address: { seen } }, `seen` once the device
// reported `pairing`).
function startPairing(started, address) {
    const next = Object.assign({}, started || {})
    const key = String(address || "").toUpperCase()
    if (key.length) next[key] = { seen: false }
    return next
}

// What follows a pairing this shell started, once the device's state says so.
// BlueZ never trusts a device itself, and a Just Works pairing (headphones,
// mice) asks the agent nothing - so nothing trusted it, and each reconnect
// asked "wants to use a service" again. A device that has paired is trusted
// and connected (`trust`, by address; bluedevil and GNOME do the same). One
// that was seen pairing and stopped without a bond failed and is forgotten;
// one that has not started yet, or is not listed, waits (`grace` ends the
// wait). → { trust: [address], started }.
function afterPairing(started, states, grace) {
    const trust = []
    const next = {}
    for (const address of Object.keys(started || {})) {
        const entry = started[address] || {}
        const state = stateFor(states, "", address)
        if (state && state.paired) { trust.push(address); continue }
        if (state && state.pairing) { next[address] = { seen: true }; continue }
        if (entry.seen || grace === false) continue
        next[address] = { seen: entry.seen === true }
    }
    return { trust: trust, started: next }
}

// A code shown for a device to type (the agent's "display" line): BlueZ sends
// no Cancel once that pairing is done, so the code stayed on screen. It is
// for the device the line names, as it was when the code came (`paired`,
// `pairing`). → { name, passkey, device, address, paired, pairing }.
function displayFor(message, states) {
    const m = message || {}
    const state = stateFor(states, m.device || "", "")
    return {
        name: m.name || "", passkey: String(m.passkey || ""), device: m.device || "",
        address: state ? String(state.address || "") : addressFromPath(m.device),
        paired: !!(state && state.paired), pairing: !!(state && state.pairing)
    }
}

// Whether the shown code is done with: its device has paired since it came,
// or a pairing that was under way has stopped (failed - a wrong code). A code
// without a device (an older agent, the preview) waits for the user.
// → { done, display } with the display's `pairing` brought up to date.
function displayStep(display, states) {
    if (!display || !display.device) return { done: false, display: display || null }
    const state = stateFor(states, display.device, display.address)
    if (!state) return { done: false, display: display }
    if (state.paired && !display.paired) return { done: true, display: null }
    if (display.pairing && !state.pairing && !state.paired) return { done: true, display: null }
    if (state.pairing && !display.pairing) return { done: false, display: Object.assign({}, display, { pairing: true }) }
    return { done: false, display: display }
}
