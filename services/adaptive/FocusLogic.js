.pragma library
.import "../appearance/TimeFormat.js" as TimeFormat

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

// ---- a Focus session ------------------------------------------------------------
// Focus for a while (AdaptiveService.focusFor: the launcher's "Focus: 25
// minutes", `buchhwin focus start 25m`): Focus with a countdown of its own,
// TimerService's "focus" run, whose end ends Focus and rings. Focus mode and
// the timer stood side by side; together they are the focus session people
// use, and Focus owning its Do Not Disturb makes the end clean.

// What the control center's chip says: "Off", "On", or the end of the
// session ("→ 14:25", the time as the clock shows it - `twelve`,
// TimeFormat). The arrow, not "Until": the chip is one of four in a row, and
// "Until 22:…" cut off the time, the one thing it is there to say.
function focusLabel(active, endsAt, twelve) {
    if (active !== true) return "Off"
    const end = Number(endsAt)
    return end > 0 ? "\u2192 " + TimeFormat.time(new Date(end), twelve === true, ":") : "On"
}

// What a restart does with Focus: "off" when its Do Not Disturb is not
// there (`focusRestored`), "restore" when it is, and "end" when it is but
// the session ran out while the shell was away (`sessionEnded`, the overdue
// countdown TimerService rang at its start): Focus comes back only to end,
// so its Do Not Disturb goes the way an end on time takes it.
function restartStep(by, active, sessionEnded) {
    if (!focusRestored(by, active)) return "off"
    return sessionEnded === true ? "end" : "restore"
}

// A session's countdown that outlived its Focus - Focus did not come back
// after the restart, because the user had changed its Do Not Disturb - goes:
// it would ring for a session that is not there. "keep" or "drop".
function sessionAfterRestart(focusActive, hasRun) {
    return hasRun === true && focusActive !== true ? "drop" : "keep"
}
