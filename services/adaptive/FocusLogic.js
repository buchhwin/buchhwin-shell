.pragma library

// Focus mode and Do Not Disturb (AdaptiveService). Focus owns the Do Not
// Disturb it turns on, the way a mode owns its own (LayoutLogic.dndOnModeChange,
// NotificationService.dndBy): it is "focus"'s, kept with its owner in
// state.json, and only its owner turns it off again. Before, Focus kept a
// private flag instead. Turned on inside gaming, it found gaming's Do Not
// Disturb on and took nothing, so leaving gaming turned it off under Focus;
// and a shell restart forgot Focus while the Do Not Disturb it had set stayed
// on for good.

var OWNER = "focus"

// Do Not Disturb as Focus starts (`entering`) or ends, against how it is now
// (`by` its owner, `active`) and the mode in use (`mode`, its template's
// `effects`). null leaves it as it is; else `{ mode, by }` for
// NotificationService.setDnd.
//
// Starting: off, Focus turns it on and owns it. A mode's own is taken over,
// so leaving that mode under Focus no longer ends it. The user's own (set by
// hand, or changed since) stays theirs: Focus leaves it alone and will not
// turn it off either.
//
// Ending: only Focus's own goes - the user has changed it since otherwise.
// It is handed back to the mode in use when that mode turns it on itself
// (gaming), as a mode switch would hand it on, and turned off otherwise.
function dndOnFocus(entering, by, active, mode, effects) {
    const owner = typeof by === "string" ? by : ""
    if (entering) {
        if (!active || (owner.length && owner !== OWNER)) return { mode: "manual", by: OWNER }
        return null
    }
    if (!active || owner !== OWNER) return null
    const wanted = effects && typeof effects.dnd === "string" && effects.dnd !== "off" ? effects.dnd : ""
    const name = typeof mode === "string" && /^[a-z]{1,32}$/.test(mode) ? mode : ""
    return wanted.length && name.length ? { mode: wanted, by: name } : { mode: "off", by: "" }
}

// Whether Focus was on before a restart: the Do Not Disturb it owns is still
// on (NotificationService read it back from state.json, which a reboot
// clears for a manual one).
function focusRestored(by, active) {
    return active === true && by === OWNER
}
