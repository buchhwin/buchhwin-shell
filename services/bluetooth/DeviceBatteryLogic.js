.pragma library

// Low batteries of Bluetooth devices - headphones, a mouse, a keyboard -
// warned about by the rules of the laptop's own (services/power/BatteryLogic):
// each threshold once, the most severe one newly crossed, and armed again
// once the level has climbed HYSTERESIS points above it, which for a device
// that says nothing about charging is the sign that it was charged. A device
// that drops off and comes back (Bluetooth does that) keeps what it was
// warned about, so a flapping headset is warned once, not on every return.

var HYSTERESIS = 3
// "Low" at 15 %, which is where most headsets start to announce it
// themselves, and once more at 5 %, shortly before they switch off.
var THRESHOLDS = [15, 5]
var LOW_LEVEL = THRESHOLDS[0]

function kindOf(threshold) {
    return threshold <= THRESHOLDS[THRESHOLDS.length - 1] ? "critical" : "low"
}

// Whether a level is low, for the device's line (BluetoothService.deviceStatus).
function low(percent) {
    const value = Number(percent)
    return isFinite(value) && value <= LOW_LEVEL
}

// state: { fired: { address: { "<threshold>": true } } }, kept for the session.
// devices: [{ address, name, percent, icon }] - the connected devices that
// report a battery (0-100). `enabled`: the setting.
// → { state, warnings: [{ address, name, percent, icon, threshold, kind }],
// cleared: [address] } - `cleared` the devices armed again (charged), whose
// notice can go.
function update(state, devices, enabled) {
    const before = state && state.fired ? state.fired : {}
    const fired = {}
    for (const address of Object.keys(before)) fired[address] = Object.assign({}, before[address])
    const warnings = []
    const cleared = []
    for (const device of devices || []) {
        const address = String(device && device.address || "")
        const percent = Number(device && device.percent)
        if (!address.length || !isFinite(percent)) continue
        const own = fired[address] || {}
        const hadAny = Object.keys(own).length > 0
        for (const key of Object.keys(own)) {
            if (THRESHOLDS.indexOf(Number(key)) < 0 || percent > Number(key) + HYSTERESIS) delete own[key]
        }
        if (hadAny && !Object.keys(own).length) cleared.push(address)
        if (enabled !== false) {
            const crossed = THRESHOLDS.filter(value => percent <= value)
            if (crossed.length) {
                const lowest = crossed[crossed.length - 1]
                if (!own[lowest])
                    warnings.push({ address: address, name: String(device.name || address), percent: Math.round(percent),
                                    icon: String(device.icon || ""), threshold: lowest, kind: kindOf(lowest) })
                for (const value of crossed) own[value] = true
            }
        }
        if (Object.keys(own).length) fired[address] = own
        else delete fired[address]
    }
    return { state: { fired: fired }, warnings: warnings, cleared: cleared }
}

// The notification for a warning. BlueZ's device icon is a freedesktop name
// already ("audio-headset", "input-mouse"); without one, Bluetooth's.
function message(warning) {
    const name = String(warning && warning.name || "Bluetooth device")
    const level = Math.round(Number(warning && warning.percent) || 0) + "%"
    const icon = String(warning && warning.icon || "").length ? warning.icon : "bluetooth"
    if (warning && warning.kind === "critical")
        return { title: titleFor(name), body: level + " left. It will switch off soon.", urgency: "critical", icon: icon }
    return { title: titleFor(name), body: level + " left. Charge it soon.", urgency: "normal", icon: icon }
}

function titleFor(name) {
    return String(name || "Bluetooth device") + " battery low"
}
