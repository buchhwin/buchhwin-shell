.pragma library

// A countdown in the notch (Tide-island's timer, built here): what a typed
// duration means and how the time left reads, the runs TimerService keeps and
// what an end does. Unit tested in TimerTest.qml and TimerRunsTest.qml.

// The longest timer there is: a day. Anything longer is a reminder, which is
// the calendar's job.
var MAX_SECONDS = 24 * 3600

// "5m", "90s", "1h30m", "1:30" (minutes:seconds), "25" (minutes) -> seconds,
// or 0 for anything that is not a duration.
function parseDuration(text) {
    const value = String(text === undefined || text === null ? "" : text).trim().toLowerCase().replace(/\s+/g, "")
    if (!value.length) return 0
    let seconds = 0
    if (/^\d+$/.test(value)) seconds = Number(value) * 60
    else if (/^\d+:\d{1,2}$/.test(value)) {
        const parts = value.split(":")
        if (Number(parts[1]) >= 60) return 0
        seconds = Number(parts[0]) * 60 + Number(parts[1])
    } else {
        const match = /^(?:(\d+)h)?(?:(\d+)m(?:in)?)?(?:(\d+)s)?$/.exec(value)
        if (!match || (!match[1] && !match[2] && !match[3])) return 0
        seconds = Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0)
    }
    return seconds > 0 && seconds <= MAX_SECONDS ? seconds : 0
}

// The time left as the strip shows it: m:ss under an hour, h:mm:ss above.
function remainingText(ms) {
    const total = Math.max(0, Math.ceil(Number(ms) / 1000) || 0)
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const seconds = total % 60
    const pad = n => (n < 10 ? "0" : "") + n
    return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(seconds) : minutes + ":" + pad(seconds)
}

// How much of it is still to run, 1 at the start and 0 at the end.
function fraction(remainingMs, totalSeconds) {
    const total = Number(totalSeconds) * 1000
    if (!(total > 0)) return 0
    return Math.max(0, Math.min(1, Number(remainingMs) / total))
}

// A duration in words, for the notification at the end ("5 minutes").
function label(seconds) {
    const s = Math.max(0, Math.round(Number(seconds) || 0))
    if (s % 3600 === 0 && s >= 3600) return (s / 3600) + (s === 3600 ? " hour" : " hours")
    if (s % 60 === 0 && s >= 60) return (s / 60) + (s === 60 ? " minute" : " minutes")
    return s + (s === 1 ? " second" : " seconds")
}

// ---- the countdowns that run --------------------------------------------------
// Two at most, one of each kind: a timer ("timer", the launcher's "Timer: 5
// minutes", `buchhwin timer start`) and a Focus session ("focus",
// AdaptiveService.focusFor), each with an end of its own. One countdown for
// both made a tea timer started during a Focus session end that session's
// countdown, and Focus then never ended. A run is { kind, endsAt (ms since
// the epoch), total (seconds) }; a list of runs is ordered by its ends, the
// first to end first.
var KINDS = ["timer", "focus"]

function kindOf(kind) {
    return kind === "focus" ? "focus" : "timer"
}

// A run, or null for one that is no run (no end, a length past MAX_SECONDS).
function run(kind, endsAt, total) {
    const ends = Number(endsAt)
    const seconds = Math.round(Number(total))
    if (!isFinite(ends) || ends <= 0 || !(seconds > 0) || seconds > MAX_SECONDS) return null
    return { kind: kindOf(kind), endsAt: ends, total: seconds }
}

// The list with `next` in place of the run of its kind there was.
function withRun(runs, next) {
    const list = (Array.isArray(runs) ? runs : []).filter(item => item && (!next || item.kind !== next.kind))
    if (next) list.push(next)
    return list.sort((a, b) => a.endsAt - b.endsAt)
}

// The list without the run of `kind`; the very same list when there is none,
// so a binding on it does not run again for nothing.
function withoutRun(runs, kind) {
    const list = Array.isArray(runs) ? runs : []
    const which = kindOf(kind)
    return list.some(item => item && item.kind === which) ? list.filter(item => item && item.kind !== which) : list
}

function find(runs, kind) {
    const which = kindOf(kind)
    return (Array.isArray(runs) ? runs : []).find(item => item && item.kind === which) || null
}

// The run the notch, the bar and `timer get` show: the one to end first.
function shown(runs) {
    return Array.isArray(runs) && runs.length ? runs[0] : null
}

// The runs that have ended by `now`.
function due(runs, now) {
    return (Array.isArray(runs) ? runs : []).filter(item => item && item.endsAt <= Number(now))
}

// ---- across a shell restart ----------------------------------------------------
// The runs are kept in the state directory (timer.json), so a deploy, a crash
// restart or Super+Ctrl+R no longer drops a running timer - or a Focus session
// halfway through, whose Focus came back from state.json without the end that
// was to turn it off. Kept with the boot they were started in: a reboot ends
// them, as it ends a manual Do Not Disturb.
//
// One that ran out while the shell was away rings at the next start, unless
// that start is more than STALE_MS after its end: a timer from before an
// evening in Plasma is no news.
var STALE_MS = 15 * 60 * 1000

function stateText(runs, boot) {
    const list = (Array.isArray(runs) ? runs : []).filter(item => item)
        .map(item => ({ kind: item.kind, endsAt: item.endsAt, total: item.total }))
    return JSON.stringify({ boot: String(boot || ""), runs: list }) + "\n"
}

// The runs of `text` (timer.json) still worth keeping at `now` in boot `boot`.
function restored(text, boot, now) {
    let parsed = null
    try {
        parsed = JSON.parse(String(text || ""))
    } catch (error) {
        parsed = null
    }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.runs)) return []
    if (!String(boot || "").length || String(parsed.boot || "") !== String(boot)) return []
    let list = []
    for (const entry of parsed.runs) {
        if (!entry || typeof entry !== "object" || KINDS.indexOf(entry.kind) < 0) continue
        const item = run(entry.kind, entry.endsAt, entry.total)
        if (item && Number(now) - item.endsAt <= STALE_MS) list = withRun(list, item)
    }
    return list
}

// ---- the end ------------------------------------------------------------------
// The name the end's notification carries (`notify-send --app-name`), and so
// the app Settings > Notifications keeps a rule for.
var APP_NAME = "Timer"
var ALARM_SOUND = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

// What the end says, by kind.
function endTexts(kind, total) {
    if (kindOf(kind) === "focus")
        return { summary: "Focus session done", body: "The Focus session of " + label(total) + " has ended" }
    // "Your timer of 25 minutes", as the Focus line has it: "The 25
    // minutes timer" took the unit's plural for an adjective.
    return { summary: "Timer done", body: "Your timer of " + label(total) + " has run out" }
}

// What the end of a run does. The notification goes to the history as it
// always did (`send`, in a session shell). A timer the user started must be
// seen and heard in Do Not Disturb too: a manual Do Not Disturb - the user's,
// or before it was owned gaming's and Focus's - held even an urgent one back,
// and the notch's chip had gone with the end, so the timer turned up in the
// history later. When the notification will not pop up (`popsUp`, what
// NotificationService decides for an urgent one from APP_NAME), the shell's
// own notice says it instead, through any Do Not Disturb (`notice`; a nested
// shell sends nothing, and the notice stands in). The alarm (`sound`, the
// setting) plays in either case, only in a session shell - a nested one would
// play on the host's speakers. An app rule of "mute" for the timer is the
// user's word against all of it but the history.
// `state`: real, popsUp, rule, sound, canNotice.
function endActions(state) {
    const it = state || {}
    const muted = it.rule === "mute"
    const real = it.real === true
    return {
        send: real,
        notice: !muted && it.canNotice === true && (!real || it.popsUp !== true),
        sound: real && !muted && it.sound === true
    }
}

// When an end is announced: "none" in the lock screen's process, which keeps
// and announces nothing (`sessionSide`); "wait" while NotificationService has
// not read its state back (`stateLoaded`); "now" otherwise. A run that ran
// out while the shell was away rings as the shell starts, and judged against
// the Do Not Disturb of before the read, the user's own did not count: no
// notice came, and the notification was held back.
function announceStep(sessionSide, stateLoaded) {
    if (sessionSide !== true) return "none"
    return stateLoaded === true ? "now" : "wait"
}

// The notification the end sends (`texts`: endTexts). With the alarm playing
// (`alarm`) it asks for no sound of its own: with Settings > Notifications'
// sounds on, the urgent one's sound came on top of the alarm clock.
function notifyCommand(texts, alarm) {
    const it = texts || {}
    return ["notify-send", "--app-name=" + APP_NAME, "--icon=alarm-symbolic", "--urgency=critical"]
        .concat(alarm === true ? ["--hint=boolean:suppress-sound:true"] : [])
        .concat(["--", String(it.summary || ""), String(it.body || "")])
}

// The command that plays the alarm, bounded so a stuck output never leaves it
// waiting (the sound is six seconds). Played as a notification's sound, which
// a policy that lowers music for notifications treats as one.
function soundCommand(file) {
    return ["timeout", "15", "pw-play", "--media-role", "Notification", String(file || ALARM_SOUND)]
}

// The runs as `timer get` lists them: the kind and the seconds left.
function describe(runs, now) {
    return (Array.isArray(runs) ? runs : []).filter(item => item).map(item => ({
        kind: item.kind, remaining: Math.max(0, Math.ceil((item.endsAt - Number(now)) / 1000))
    }))
}
