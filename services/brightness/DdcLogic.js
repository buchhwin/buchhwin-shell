.pragma library
.import "../display/DisplayLogic.js" as Display

// The brightness of external monitors over DDC/CI, through ddcutil
// (BrightnessService). A monitor is asked once per hotplug whether it
// answers (`ddcutil detect`, which takes seconds), then once for its
// brightness (VCP feature 10), and written only when the user moves a slider
// or presses a brightness key with that screen focused - never polled. Only
// monitors that answered get a slider; a monitor that stops answering is
// dropped until the next hotplug. Unit tested (DdcTest).

// How long one ddcutil run may take before `timeout` ends it. Some monitors
// and docks hang a DDC request; a hung run must not hold every later one
// back for good. Detection walks every display bus and is the slow one.
var DETECT_SECONDS = 30
var VCP_SECONDS = 8
// One key press, as the backlight's (`brightnessctl … 5%+`): a twentieth of
// the monitor's range.
var STEP_PERCENT = 5

function list(value) {
    return Array.isArray(value) ? value : []
}

// `ddcutil detect --brief` (ddcutil 2 and 3):
//
//   Display 1
//      I2C bus:          /dev/i2c-10
//      DRM connector:    card1-DP-8
//      drm_connector_id: 393
//      Monitor:          DEL:DELL U2720Q:ABC1234
//
//   Invalid display
//      I2C bus:          /dev/i2c-2
//      DRM connector:    card1-eDP-1
//      Monitor:          LEN::
//
// as [{ valid, bus, connector, mfg, model, serial }]. "Display N" is a
// monitor that answered; "Invalid display" and "Phantom display" did not (a
// laptop panel never does) and are kept as invalid so a test can see them
// read. The connector without its card prefix is Hyprland's name for it
// ("card1-DP-8" is DP-8). Older builds wrote "DRM_connector".
function parseDetect(text) {
    const result = []
    let current = null
    for (const raw of String(text || "").split("\n")) {
        const line = raw.replace(/\s+$/, "")
        if (!line.length) continue
        if (!/^\s/.test(line)) {
            current = { valid: /^Display\s+\d+/.test(line), bus: -1, connector: "", mfg: "", model: "", serial: "" }
            result.push(current)
            continue
        }
        if (!current) continue
        const field = /^\s+([A-Za-z0-9_ ]+?):\s*(.*)$/.exec(line)
        if (!field) continue
        const key = field[1].toLowerCase().replace(/[_\s]+/g, " ")
        const value = field[2].trim()
        if (key === "i2c bus") {
            const bus = /i2c-(\d+)\s*$/.exec(value)
            if (bus) current.bus = Number(bus[1])
        } else if (key === "drm connector") {
            current.connector = value.replace(/^card\d+-/, "")
        } else if (key === "monitor") {
            const parts = value.split(":")
            current.mfg = parts.length ? parts[0].trim() : ""
            current.serial = parts.length > 2 ? parts[parts.length - 1].trim() : ""
            current.model = parts.length > 2 ? parts.slice(1, -1).join(":").trim() : parts.length > 1 ? parts[1].trim() : ""
        }
    }
    return result
}

// `ddcutil getvcp 10 --brief`: "VCP 10 C 60 100" - a continuous feature,
// current value, maximum - as { value, max }, or null for anything else (an
// error, a monitor without the feature, a maximum of 0).
function parseVcp(text) {
    const match = /^VCP\s+10\s+C\s+(\d+)\s+(\d+)\s*$/im.exec(String(text || ""))
    if (!match) return null
    const value = Number(match[1]), max = Number(match[2])
    if (!(max > 0)) return null
    return { value: Math.max(0, Math.min(max, value)), max: max }
}

// The external monitors that are on (or mirror another), the ones a
// brightness can belong to: never the laptop panel, which is the backlight's
// and has no DDC.
function externalMonitors(monitors, internalName) {
    return list(monitors).filter(monitor => monitor && !monitor.disabled && !Display.isPanel(monitor.name, internalName)
                                 && !Display.isInternal(monitor.name))
}

// The external monitors connected, as one string: detection runs again when
// it changes (a hotplug), and never while it stays the same. "" without an
// external monitor, and then nothing runs at all.
function externalKey(monitors, internalName) {
    return externalMonitors(monitors, internalName)
        .map(monitor => String(monitor.name) + "\u0001" + String(monitor.description || "")).sort().join("\n")
}

// The detected displays that answered, matched to Hyprland's monitors, as
// [{ name, description, bus }]: by connector first (ddcutil reads it from the
// DRM sysfs), then - for a display whose connector ddcutil could not name,
// as behind some docks - by model and serial against Hyprland's model and
// description, only where exactly one display fits. A display is matched to
// one monitor at most.
function match(detected, monitors, internalName) {
    const answered = list(detected).filter(item => item && item.valid && item.bus >= 0)
    const screens = externalMonitors(monitors, internalName)
    const used = []
    const result = []
    for (const monitor of screens) {
        let found = answered.find(item => used.indexOf(item) < 0 && item.connector.length && item.connector === monitor.name)
        if (!found) {
            const model = String(monitor.model || "")
            const description = String(monitor.description || "")
            const fits = answered.filter(item => used.indexOf(item) < 0 && !item.connector.length
                                         && item.model.length && item.model === model
                                         && (!item.serial.length || description.indexOf(item.serial) >= 0))
            if (fits.length === 1) found = fits[0]
        }
        if (!found) continue
        used.push(found)
        result.push({ name: monitor.name, description: String(monitor.description || ""), bus: found.bus })
    }
    return result
}

// The commands, each bounded by `timeout`. `program` is ddcutil (or a
// stand-in a nested session names). Writes skip ddcutil's read-back
// (`--noverify`): a slider drag is many writes, and the next one says what
// the monitor should be at anyway.
function detectCommand(program) {
    return ["timeout", String(DETECT_SECONDS), String(program), "detect", "--brief"]
}

function readCommand(program, bus) {
    return ["timeout", String(VCP_SECONDS), String(program), "getvcp", "10", "--brief", "--bus", String(Math.round(bus))]
}

function writeCommand(program, bus, value) {
    return ["timeout", String(VCP_SECONDS), String(program), "setvcp", "10", String(Math.round(value)),
            "--bus", String(Math.round(bus)), "--noverify"]
}

// A slider's 0-1 as the monitor's own number.
function fromRatio(ratio, max) {
    const top = Number(max) || 0
    if (top <= 0) return 0
    return Math.round(Math.max(0, Math.min(1, Number(ratio) || 0)) * top)
}

function toRatio(value, max) {
    const top = Number(max) || 0
    return top > 0 ? Math.max(0, Math.min(1, (Number(value) || 0) / top)) : 0
}

// `steps` key presses from `value` (negative is down), five percent of the
// range each and at least one, inside 0..max.
function stepped(value, max, steps) {
    const top = Number(max) || 0
    if (top <= 0) return 0
    const size = Math.max(1, Math.round(top * STEP_PERCENT / 100))
    return Math.max(0, Math.min(top, Math.round(Number(value) || 0) + Math.round(Number(steps) || 0) * size))
}

// What runs next, with one ddcutil at a time (the displays share the
// monitor's bus behind a dock, and ddcutil locks per display anyway):
// detection first, then the writes - the newest value of each display, so a
// drag sends where the slider is now and not every place it passed -, then
// the one read of each display after detection. `displays` are
// [{ name, bus, value, max, pending, read, failed }]: `pending` a value to
// write or -1, `max` 0 until known (a display seen before has it from the
// last time, so its slider is there at once and the read only corrects it),
// `read` whether it has been read since it was detected. Null when there is
// nothing to do.
function nextJob(detectWanted, displays) {
    if (detectWanted) return { kind: "detect" }
    const usable = list(displays).filter(item => item && !item.failed && item.bus >= 0)
    const write = usable.find(item => item.max > 0 && item.pending >= 0)
    if (write) return { kind: "write", name: write.name, bus: write.bus, value: write.pending }
    const read = usable.find(item => item.read !== true)
    if (read) return { kind: "read", name: read.name, bus: read.bus }
    return null
}
