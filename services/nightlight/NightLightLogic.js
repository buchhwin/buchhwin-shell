.pragma library

// Night light scheduling helpers. Unit tested.

function minutesOf(text) {
    const match = /^(\d{1,2}):(\d{2})$/.exec(String(text || ""))
    if (!match) return -1
    const hours = Number(match[1]), minutes = Number(match[2])
    return hours < 24 && minutes < 60 ? hours * 60 + minutes : -1
}

// Whether a fixed schedule is active at `date`; the range may cross midnight.
function scheduleActive(start, end, date) {
    const from = minutesOf(start), to = minutesOf(end)
    if (from < 0 || to < 0 || from === to) return false
    const now = date.getHours() * 60 + date.getMinutes()
    return from < to ? now >= from && now < to : now >= from || now < to
}

function clampTemperature(value) {
    return Math.round(Math.max(2500, Math.min(6000, Number(value) || 4000)) / 100) * 100
}

// gammastep arguments for a mode; [] means no process.
function command(mode, temperature, lat, lon, scheduled) {
    const temp = clampTemperature(temperature)
    if (mode === "manual" || (mode === "schedule" && scheduled))
        return ["gammastep", "-m", "wayland", "-P", "-O", String(temp)]
    if (mode === "sun" && typeof lat === "number" && typeof lon === "number" && !(lat === 0 && lon === 0))
        return ["gammastep", "-m", "wayland", "-P", "-l", lat.toFixed(2) + ":" + lon.toFixed(2), "-t", "6500:" + temp]
    return []
}
