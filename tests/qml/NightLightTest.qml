import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/nightlight/NightLightLogic.js" as N

ShellRoot {
    Component.onCompleted: {
        T.eq([N.minutesOf("07:30"), N.minutesOf("24:00"), N.minutesOf("7")], [450, -1, -1], "time parsing")
        T.ok(N.scheduleActive("20:00", "07:00", new Date(2026, 0, 1, 23, 0)), "overnight schedule before midnight")
        T.ok(N.scheduleActive("20:00", "07:00", new Date(2026, 0, 1, 6, 59)), "overnight schedule after midnight")
        T.ok(!N.scheduleActive("20:00", "07:00", new Date(2026, 0, 1, 7, 0)), "schedule end is exclusive")
        T.ok(N.scheduleActive("13:00", "15:00", new Date(2026, 0, 1, 14, 0)) && !N.scheduleActive("13:00", "15:00", new Date(2026, 0, 1, 16, 0)), "same-day schedule")
        T.ok(!N.scheduleActive("10:00", "10:00", new Date()), "empty range is never active")
        T.eq([N.clampTemperature(1000), N.clampTemperature(4321), N.clampTemperature("x")], [2500, 4300, 4000], "temperature clamped")
        T.eq(N.command("manual", 3800, 0, 0, false), ["gammastep", "-m", "wayland", "-P", "-O", "3800"], "manual command")
        T.eq(N.command("schedule", 4000, 0, 0, false), [], "schedule outside its time")
        T.eq(N.command("sun", 4000, 52.5, 13.4, false).slice(-4), ["-l", "52.50:13.40", "-t", "6500:4000"], "sun mode uses the location")
        T.eq(N.command("sun", 4000, 0, 0, false), [], "sun mode without a location")
        T.eq(N.command("off", 4000, 52.5, 13.4, true), [], "off")

        // Crashes and restarts: the exit of a run the service stopped for a new
        // command (gammastep fades for ~4 s at night) is no crash.
        T.eq(N.exitIsFailure(true, false, false), true, "an exit while night light should be on is a failure")
        T.eq(N.exitIsFailure(true, false, true), false, "the late exit of a replaced run is not")
        T.eq(N.exitIsFailure(true, true, false), false, "nor one inside the restart gap")
        T.eq(N.exitIsFailure(false, false, false), false, "nor one after night light went off")
        T.eq([N.crashBackoff(1), N.crashBackoff(2), N.crashBackoff(5)], [10000, 20000, 160000], "the pause doubles")
        T.eq([N.crashBackoff(6), N.crashBackoff(0), N.crashBackoff("x")], [0, 0, 0], "and stops after five")
        T.finish("NightLightTest")
    }
}
