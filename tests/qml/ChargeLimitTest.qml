import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/ChargeLimitLogic.js" as C
import "../../services/power/BatteryLogic.js" as B

ShellRoot {
    Component.onCompleted: {
        // Names and paths.
        T.eq([C.batteryName("BAT0"), C.batteryName("/sys/devices/LNXSYSTM:00/PNP0C0A:00/power_supply/BAT1")],
             ["BAT0", "BAT1"], "the battery's name, from a name or a sysfs path")
        T.eq([C.batteryName(""), C.batteryName(undefined), C.batteryName("BAT0/"), C.batteryName("BAT 0"),
              C.batteryName("../x;rm")], ["", "", "", "", ""], "nothing that is not a plain name")
        T.eq(C.upowerPath("BAT0"), "/org/freedesktop/UPower/devices/battery_BAT0", "UPower's object")
        T.eq(C.upowerPath("hid-a1:b2.c@d"), "/org/freedesktop/UPower/devices/battery_hid_a1ob2xc_d",
             "spelled as UPower spells a D-Bus path")
        T.eq(C.upowerPath(""), "", "no battery, no path")
        T.eq([C.sysfsFile("BAT0", "start"), C.sysfsFile("BAT0", "end")],
             ["/sys/class/power_supply/BAT0/charge_control_start_threshold",
              "/sys/class/power_supply/BAT0/charge_control_end_threshold"], "the kernel's thresholds")
        T.eq([C.sysfsFile("BAT0", "other"), C.sysfsFile("", "end")], ["", ""], "only those two, only for a battery")

        // Commands: reads never start UPower, the change is one call.
        const read = C.readCommand("/org/freedesktop/UPower/devices/battery_BAT0")
        T.eq(read.slice(0, 5), ["busctl", "--system", "--auto-start=no", "--timeout=2", "get-property"], "a read")
        T.eq(read.slice(-4), ["ChargeThresholdSupported", "ChargeThresholdEnabled", "ChargeStartThreshold", "ChargeEndThreshold"],
             "four properties in one call")
        T.eq(C.enableCommand("/p", true), ["busctl", "--system", "--auto-start=no", "--timeout=30", "call", "org.freedesktop.UPower",
                                           "/p", "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", "true"], "on")
        T.eq(C.enableCommand("/p", false).slice(-1), ["false"], "off")
        T.eq(C.enableCommand("/p", "yes").slice(-1), ["false"], "only true is on")

        // What busctl and sysfs say.
        const thinkpad = "b true\nb false\nu 75\nu 80\n"
        T.eq(C.parseProperties(thinkpad), { supported: true, enabled: false, start: 75, end: 80 }, "this ThinkPad's answer")
        T.eq([C.parseProperties(""), C.parseProperties("b true\nb false\nu 75"), C.parseProperties("s x\nb false\nu 1\nu 2"),
              C.parseProperties(undefined)], [null, null, null, null], "anything else is no answer")
        T.eq([C.parseThreshold("80\n"), C.parseThreshold(" 0 "), C.parseThreshold("100")], [80, 0, 100], "a threshold")
        T.eq([C.parseThreshold(""), C.parseThreshold("abc"), C.parseThreshold("101"), C.parseThreshold(null), C.parseThreshold("-5")],
             [-1, -1, -1, -1, -1], "no threshold")

        // The limit in force: sysfs over UPower.
        const upowerOff = C.parseProperties(thinkpad)
        let limit = C.state(upowerOff, 75, 80)
        T.eq(limit, { supported: true, active: true, start: 75, end: 80, upowerEnabled: false, upowerStart: 75, upowerEnd: 80 },
             "held at 80% while UPower says disabled: the kernel is right")
        T.eq(C.label(limit), "Charge limit 80%", "the popup's line")
        T.eq(C.state(upowerOff, 0, 100).active, false, "0/100 is no limit")
        T.eq(C.state({ supported: true, enabled: true, start: 60, end: 85 }, -1, -1),
             { supported: true, active: true, start: 60, end: 85, upowerEnabled: true, upowerStart: 60, upowerEnd: 85 },
             "sysfs not read: UPower's own thresholds while it set them")
        T.eq(C.state(upowerOff, -1, -1).active, false, "not read, UPower disabled: nothing known")
        T.eq(C.state(null, 75, 80), { supported: false, active: true, start: 75, end: 80, upowerEnabled: false,
                                       upowerStart: -1, upowerEnd: -1 }, "an older UPower: shown, not changeable")
        T.eq(C.state(null, -1, -1), { supported: false, active: false, start: -1, end: -1, upowerEnabled: false,
                                       upowerStart: -1, upowerEnd: -1 }, "no battery thresholds at all")
        T.eq(C.state(upowerOff, -1, 80).start, -1, "an end without a start")
        T.eq(C.label(C.state(null, -1, -1)), "", "no line without a limit")
        T.eq(C.hint(limit), "Stops charging at 80% and starts again below 75%: a battery that sits on the charger all day keeps longer",
             "the row says what turning it on writes")
        T.eq(C.hint({ upowerStart: 0, upowerEnd: 90 }), "Stops charging at 90%: a battery that sits on the charger all day keeps longer",
             "without a start threshold")
        T.ok(C.hint(undefined).indexOf("Stops charging below full") === 0, "without numbers")
        const once = "For a trip: the limit is lifted until the battery is full or the charger is unplugged, then it is set again"
        T.eq(C.onceHint(limit), once, "the same limit comes back: no number to name")
        T.eq(C.onceHint(C.state(upowerOff, 40, 60)), once + " at 80%",
             "another tool's 60%: the trip ends with UPower's own limit, and the row says which")
        T.eq(C.onceHint(C.state(upowerOff, 0, 100)), once + " at 80%", "during the trip: the limit that follows it")
        T.eq([C.onceHint(C.state(null, 75, 80)), C.onceHint(undefined)], [once, once], "no UPower numbers")

        // "Not charging" gets its reason.
        const label = extra => B.stateLabel(Object.assign({ hasBattery: true, full: false, charging: false, onBattery: false,
                                                            pendingCharge: true, percent: 80, limit: limit }, extra))
        T.eq(label({}), "Charge limit 80% reached", "at the limit")
        T.eq(label({ percent: 79 }), "Charge limit 80% reached", "a point under it is the limit, rounded")
        T.eq(label({ percent: 77 }), "Charges again below 75%", "between the two thresholds")
        // Short in the control center tile's header, beside "Battery" and the percentage.
        const brief = extra => B.stateLabel(Object.assign({ hasBattery: true, full: false, charging: false, onBattery: false,
                                                            pendingCharge: true, percent: 80, limit: limit }, extra), true)
        T.eq([brief({}), brief({ percent: 77 }), brief({ percent: 60 }), brief({ charging: true })],
             ["Held at 80%", "Charges below 75%", "Not charging", "Charging"], "the tile's short words")
        T.eq([B.limitHold({ hasBattery: true, pendingCharge: true, percent: 80, limit: limit }),
              B.limitHold({ hasBattery: true, pendingCharge: true, percent: 77, limit: limit }),
              B.limitHold({ hasBattery: true, pendingCharge: true, percent: 60, limit: limit }),
              B.limitHold({ hasBattery: true, pendingCharge: true, charging: true, percent: 80, limit: limit })],
             ["reached", "waiting", "", ""], "which threshold holds it, for the popup's own line")
        T.eq(label({ percent: 60 }), "Not charging", "below both: no reason the limit gives")
        T.eq(label({ limit: C.state(upowerOff, 0, 100) }), "Not charging", "no limit in force")
        T.eq(label({ limit: undefined }), "Not charging", "not read yet")
        T.eq(label({ limit: { active: true, start: 0, end: 90 }, percent: 85 }), "Not charging", "no start threshold to name")
        T.eq(label({ pendingCharge: false }), "Plugged in", "not waiting: as before")
        T.eq(label({ charging: true }), "Charging", "charging: as before")
        T.eq(label({ percent: undefined }), "Not charging", "no percentage to compare")

        // Charge to 100% once.
        const plugged = { hasBattery: true, onBattery: false, full: false, charging: true, percent: 85 }
        let step = C.onceStep({ active: true, sawCharger: true }, plugged)
        T.eq(step, { state: { active: true, sawCharger: true }, restore: false }, "charging on: keep going")
        step = C.onceStep(step.state, Object.assign({}, plugged, { full: true, percent: 100, charging: false }))
        T.eq(step, { state: { active: false, sawCharger: false }, restore: true }, "full: the limit is set again")
        step = C.onceStep({ active: true, sawCharger: true }, Object.assign({}, plugged, { charging: false, percent: 99 }))
        T.eq(step.restore, true, "a battery that stops at 99% on the charger counts as full")
        step = C.onceStep({ active: true, sawCharger: true }, Object.assign({}, plugged, { charging: false, percent: 80 }))
        T.eq(step.restore, false, "but not one still at the old limit, about to start charging")
        step = C.onceStep({ active: true, sawCharger: true }, Object.assign({}, plugged, { full: true, charging: false, percent: 80 }))
        T.eq(step.restore, false, "nor one its firmware calls full at the limit just lifted")
        step = C.onceStep({ active: true, sawCharger: true }, Object.assign({}, plugged, { full: true, charging: false, percent: 97 }))
        T.eq(step.restore, true, "UPower's full near the top is full")
        step = C.onceStep({ active: true, sawCharger: true }, Object.assign({}, plugged, { onBattery: true, charging: false, percent: 93 }))
        T.eq(step, { state: { active: false, sawCharger: false }, restore: true }, "unplugged for the trip before full")
        step = C.onceStep({ active: true, sawCharger: false }, Object.assign({}, plugged, { onBattery: true, charging: false, percent: 50 }))
        T.eq(step, { state: { active: true, sawCharger: false }, restore: false }, "asked for on battery: waits for a charger")
        step = C.onceStep(step.state, plugged)
        T.eq(step.state.sawCharger, true, "then the charger comes")
        T.eq(C.onceStep(step.state, Object.assign({}, plugged, { onBattery: true })).restore, true, "and its unplug ends it")
        T.eq(C.onceStep({ active: false, sawCharger: true }, Object.assign({}, plugged, { full: true })),
             { state: { active: false, sawCharger: true }, restore: false }, "nothing to do without a once")
        T.eq(C.onceStep({ active: true }, { hasBattery: false }).restore, false, "no battery, nothing to restore")
        T.eq(C.onceStep(undefined, undefined), { state: { active: false, sawCharger: false }, restore: false }, "no state")

        // A refusal in a line.
        T.eq(C.errorText("Call failed: Access denied\n"), "Access denied", "polkit's no")
        T.eq(C.errorText("Failed to connect to bus: No such file or directory"), "No such file or directory", "no bus")
        T.eq([C.errorText(""), C.errorText(undefined)], ["UPower did not answer", "UPower did not answer"], "nothing said")
        T.eq(C.errorText("x".repeat(300)).length, 120, "kept to a line")
        T.finish("ChargeLimitTest")
    }
}
