.pragma library

// The battery's charge limit (PowerService): what holds it, how to change it
// and "charge to 100% once" for a trip. Unit tested (ChargeLimitTest).
//
// Two sources, and they can disagree. The kernel's thresholds
// (charge_control_start/end_threshold in sysfs, readable by anyone) are what
// the battery really does; UPower's ChargeThresholdEnabled is only whether
// UPower itself set them. A ThinkPad keeps its thresholds in the embedded
// controller, so 75/80 set once by another tool hold the battery at 80% while
// UPower says "disabled" - and the shell said "Not charging" with no word of
// why. What is shown comes from sysfs; what is changed goes through UPower's
// EnableChargeThreshold (polkit's org.freedesktop.UPower.enable-charging-limit,
// no password for the active session on Arch), which writes UPower's own
// thresholds when on and 0/100 when off.

var SERVICE = "org.freedesktop.UPower"
var DEVICE_INTERFACE = "org.freedesktop.UPower.Device"
var PROPERTIES = ["ChargeThresholdSupported", "ChargeThresholdEnabled", "ChargeStartThreshold", "ChargeEndThreshold"]

// A power supply's name as UPower and sysfs spell it ("BAT0"). UPower gives a
// full sysfs path on some systems; only the last part names the battery, and
// anything that is not a plain name is no battery the shell writes to.
function batteryName(nativePath) {
    const text = String(nativePath || "")
    const name = text.slice(text.lastIndexOf("/") + 1)
    return /^[A-Za-z0-9_.:@-]+$/.test(name) ? name : ""
}

// UPower's object for the battery: "battery_" and the name with what a D-Bus
// path may not hold replaced the way UPower replaces it (up-device.c:
// "-" and "@" to "_", "." to "x", ":" to "o" - the USB-C port
// "ucsi-source-psy-USBC000:001" is line_power_ucsi_source_psy_USBC000o001).
function upowerPath(nativePath) {
    const name = batteryName(nativePath)
    if (!name.length) return ""
    return "/org/freedesktop/UPower/devices/battery_"
        + name.replace(/[-@]/g, "_").replace(/\./g, "x").replace(/:/g, "o")
}

function sysfsFile(nativePath, which) {
    const name = batteryName(nativePath)
    if (!name.length || (which !== "start" && which !== "end")) return ""
    return "/sys/class/power_supply/" + name + "/charge_control_" + which + "_threshold"
}

// One busctl for the four properties. --auto-start=no: asking must never be
// what starts UPower (testing.md, pitfall 27).
function readCommand(path) {
    return ["busctl", "--system", "--auto-start=no", "--timeout=2", "get-property", SERVICE, path, DEVICE_INTERFACE]
        .concat(PROPERTIES)
}

// The change itself, on only for a real `true`. The timeout leaves room for
// a polkit agent that asks, as it may on a system where the action is not
// allowed outright.
function enableCommand(path, on) {
    return ["busctl", "--system", "--auto-start=no", "--timeout=30", "call", SERVICE, path, DEVICE_INTERFACE,
            "EnableChargeThreshold", "b", on === true ? "true" : "false"]
}

// busctl's answer to readCommand, one "TYPE VALUE" line per property in the
// order asked: { supported, enabled, start, end }, or null for anything else.
function parseProperties(text) {
    const lines = String(text || "").split("\n").map(line => line.trim()).filter(line => line.length)
    if (lines.length !== PROPERTIES.length) return null
    const flag = line => line === "b true" ? true : line === "b false" ? false : null
    const number = line => {
        const match = /^u (\d+)$/.exec(line)
        return match ? Number(match[1]) : null
    }
    const result = { supported: flag(lines[0]), enabled: flag(lines[1]), start: number(lines[2]), end: number(lines[3]) }
    if (result.supported === null || result.enabled === null || result.start === null || result.end === null) return null
    return result
}

// A sysfs threshold, -1 when the text is not one (missing, empty, garbled).
function parseThreshold(text) {
    const trimmed = String(text === undefined || text === null ? "" : text).trim()
    if (!/^\d+$/.test(trimmed)) return -1
    const value = Number(trimmed)
    return value >= 0 && value <= 100 ? value : -1
}

// What the battery's limit is now.
// upower: parseProperties' answer or null; sysStart/sysEnd: sysfs, -1 unknown.
// Returns { supported, active, start, end, upowerEnabled, upowerStart,
// upowerEnd }: `supported` is whether UPower can change it, `active` a limit
// below 100% in force, `start`/`end` the thresholds in force - sysfs when it
// was read (a limit another tool set is shown even where UPower cannot
// change it), else UPower's while it says it set them.
function state(upower, sysStart, sysEnd) {
    const u = upower || null
    const supported = u !== null && u.supported === true
    let end = Number(sysEnd)
    let start = Number(sysStart)
    if (!(end >= 0)) {
        end = supported && u.enabled ? Number(u.end) : -1
        start = supported && u.enabled ? Number(u.start) : -1
    }
    if (!(start >= 0)) start = -1
    return {
        supported: supported,
        active: end > 0 && end < 100,
        start: start,
        end: end,
        upowerEnabled: supported && u.enabled === true,
        upowerStart: supported ? Number(u.start) : -1,
        upowerEnd: supported ? Number(u.end) : -1
    }
}

// "Charge limit 80%" for the battery popup, "" without one.
function label(limit) {
    const l = limit || {}
    return l.active ? "Charge limit " + l.end + "%" : ""
}

// The Settings row's explanation: what turning the limit on does, in
// UPower's numbers, since those are the ones it writes.
function hint(limit) {
    const l = limit || {}
    const end = Number(l.upowerEnd) > 0 && Number(l.upowerEnd) < 100 ? Number(l.upowerEnd) : 0
    if (!end) return "Stops charging below full, which a battery that sits on the charger all day keeps longer"
    const start = Number(l.upowerStart) > 0 && Number(l.upowerStart) < end ? Number(l.upowerStart) : 0
    return "Stops charging at " + end + "%" + (start ? " and starts again below " + start + "%" : "")
        + ": a battery that sits on the charger all day keeps longer"
}

// The "Charge to 100% once" row's explanation. The limit comes back through
// UPower, with UPower's own numbers: where another tool had set a different
// limit, the row says which one follows the trip.
function onceHint(limit) {
    const l = limit || {}
    const text = "For a trip: the limit is lifted until the battery is full or the charger is unplugged, then it is set again"
    const end = Number(l.upowerEnd)
    return end > 0 && end < 100 && end !== Number(l.end) ? text + " at " + end + "%" : text
}

// "Charge to 100% once": the limit is lifted until the battery is full or
// the charger is unplugged after it, and then it is set again. `sawCharger`
// is what makes "unplugged" mean something: started on battery, the hold
// waits for a charger first rather than ending at once.
// state: { active, sawCharger }
// input: { hasBattery, onBattery, full, percent, charging }
// Returns { state, restore } - restore: set the limit again now.
function onceStep(state, input) {
    const s = state || {}
    const i = input || {}
    if (s.active !== true || i.hasBattery !== true) return { state: { active: s.active === true, sawCharger: s.sawCharger === true }, restore: false }
    const plugged = i.onBattery !== true
    const sawCharger = s.sawCharger === true || plugged
    // Full is UPower's FullyCharged near the top, or a battery at the top
    // that stopped charging: some report "not charging" at 99-100% rather
    // than "full". Some firmware calls a battery held at its limit "full"
    // too; at 80% that is the limit just lifted, not the trip's 100%.
    const percent = Number(i.percent)
    const full = (i.full === true && percent >= 95) || (plugged && i.charging !== true && percent >= 99)
    if (full || (sawCharger && !plugged)) return { state: { active: false, sawCharger: false }, restore: true }
    return { state: { active: true, sawCharger: sawCharger }, restore: false }
}

// busctl's complaint in a line: "Call failed: Access denied" says "Access
// denied" - the polkit refusal a user should read as such.
function errorText(text) {
    const line = String(text || "").split("\n").map(part => part.trim()).filter(part => part.length)[0] || ""
    const plain = line.replace(/^Call failed:\s*/i, "").replace(/^Failed to [^:]*:\s*/i, "")
    if (!plain.length) return "UPower did not answer"
    return plain.length > 120 ? plain.slice(0, 119) + "…" : plain
}
