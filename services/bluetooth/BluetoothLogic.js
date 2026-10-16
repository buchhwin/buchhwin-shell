.pragma library

// Pure decisions for BluetoothService and the pairing dialog: who keeps
// discovery running, and what a typed passkey means. Nothing here talks to
// BlueZ.

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
