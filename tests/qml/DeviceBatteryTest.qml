import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/bluetooth/DeviceBatteryLogic.js" as B

// Low batteries of Bluetooth devices (services/bluetooth/DeviceBatteryLogic.js):
// once per threshold, by the laptop's rules, and never again for a device
// that only dropped off and came back.
ShellRoot {
    Component.onCompleted: {
        const headset = percent => ({ address: "00:11:22:33:44:55", name: "Headset", percent: percent, icon: "audio-headset" })
        const mouse = percent => ({ address: "66:77:88:99:AA:BB", name: "Mouse", percent: percent, icon: "" })

        let step = B.update({ fired: {} }, [headset(40), mouse(60)], true)
        T.eq(step.warnings, [], "nothing low")
        step = B.update(step.state, [headset(15), mouse(60)], true)
        T.eq(step.warnings.map(w => w.name + ":" + w.kind + ":" + w.percent), ["Headset:low:15"], "15 % warns")
        step = B.update(step.state, [headset(14), mouse(60)], true)
        T.eq(step.warnings, [], "and not again on the way down")
        step = B.update(step.state, [mouse(60)], true)
        step = B.update(step.state, [headset(14), mouse(60)], true)
        T.eq(step.warnings, [], "a headset that dropped off and came back is not warned again")
        step = B.update(step.state, [headset(5), mouse(60)], true)
        T.eq(step.warnings.map(w => w.kind + ":" + w.threshold), ["critical:5"], "5 %: once more, critical")
        step = B.update(step.state, [headset(4)], true)
        T.eq(step.warnings, [], "and only once")
        step = B.update(step.state, [headset(17)], true)
        T.eq([step.warnings.length, step.cleared], [0, []], "17 %: within the hysteresis above 15, still armed off")
        step = B.update(step.state, [headset(19)], true)
        T.eq(step.cleared, ["00:11:22:33:44:55"], "charged (more than 3 above): armed again, its notice can go")
        step = B.update(step.state, [headset(15)], true)
        T.eq(step.warnings.length, 1, "and warns again on the next discharge")

        // A device first seen at 3 % gets one warning, the most severe.
        const late = B.update({ fired: {} }, [mouse(3)], true)
        T.eq(late.warnings.map(w => w.threshold), [5], "one warning, not two")
        T.eq(Object.keys(late.state.fired["66:77:88:99:AA:BB"]).sort(), ["15", "5"], "both thresholds count as fired")

        // Switched off: nothing new, but what was warned stays warned, so
        // switching it on again does not warn about the same level.
        const off = B.update(late.state, [mouse(2)], false)
        T.eq(off.warnings, [], "switched off: no warnings")
        T.eq(B.update(off.state, [mouse(2)], true).warnings, [], "and on again: the same level is not news")
        T.eq(B.update({ fired: {} }, [mouse(10)], false).warnings, [], "off from the start")

        T.eq(B.update(null, [{ address: "", percent: 3 }, { address: "x", percent: NaN }, null], true).warnings, [],
             "devices without an address or a level")

        T.eq([B.low(15), B.low(16), B.low(undefined), B.low(0)], [true, false, false, true], "low for the device's line")

        T.eq(B.message({ name: "Headset", percent: 15, icon: "audio-headset", kind: "low" }),
             { title: "Headset battery low", body: "15% left. Charge it soon.", urgency: "normal", icon: "audio-headset" },
             "the notice")
        T.eq(B.message({ name: "Mouse", percent: 4.6, icon: "", kind: "critical" }),
             { title: "Mouse battery low", body: "5% left. It will switch off soon.", urgency: "critical", icon: "bluetooth" },
             "critical, and Bluetooth's icon for a device without one")
        T.eq(B.titleFor("Headset"), "Headset battery low", "the title the notice is found by")

        T.finish("DeviceBatteryTest")
    }
}
