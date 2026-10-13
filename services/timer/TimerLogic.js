.pragma library

// A countdown in the notch (Tide-island's timer, built here): what a typed
// duration means and how the time left reads. Unit tested in TimerTest.qml.

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
