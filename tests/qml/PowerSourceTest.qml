import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/PowerSourceLogic.js" as P

ShellRoot {
    Component.onCompleted: {
        T.eq([P.source(true, true), P.source(true, false), P.source(false, true), P.source(false, false)],
             ["battery", "ac", "ac", "ac"], "battery set only on a laptop battery")

        const legacy = {
            appearance: { theme: "light" },
            power: { screenOffMinutes: 15, lockMinutes: 5, suspendMinutes: 0, lockBeforeSleep: false,
                     lidAction: "screenOff", dimBeforeScreenOff: false, lowBatteryWarning: true, lowBatteryLevel: 15 }
        }
        const migrated = P.migrate(legacy)
        const expectedSource = { profile: "keep", screenOffMinutes: 15, lockMinutes: 5, suspendMinutes: 0,
                                 dimBeforeScreenOff: false, lidAction: "screenOff" }
        T.eq(migrated.power, { lockBeforeSleep: false, lowBatteryWarning: true, lowBatteryLevel: 15,
                               battery: expectedSource, ac: expectedSource }, "old values seed both sources")
        T.eq(migrated.appearance, { theme: "light" }, "other sections stay")
        T.eq(legacy.power.screenOffMinutes, 15, "input is not modified")
        T.ok(migrated.power.battery !== migrated.power.ac, "sources are separate objects")
        T.ok(P.migrate(migrated) === migrated, "migration runs once")

        const partial = P.migrate({ power: { lidAction: "lock" } })
        T.eq(partial.power, { battery: { profile: "keep", lidAction: "lock" }, ac: { profile: "keep", lidAction: "lock" } },
             "missing old values fall back to the defaults later")
        T.eq(P.migrate({ weather: {} }).power.ac, { profile: "keep" }, "file without a power section keeps the profile")
        const already = { power: { ac: { screenOffMinutes: 20 }, screenOffMinutes: 3 } }
        T.ok(P.migrate(already) === already, "one migrated source is enough")
        T.eq([P.migrate(null), P.migrate("x"), P.migrate([1])], [null, "x", [1]], "non-objects stay")

        // The state carries the choice as well as the source, because a changed
        // choice is the second thing that has to apply a profile.
        let result = P.profileChange({ source: "" }, { ready: false, source: "ac", choice: "balanced" })
        T.eq(result, { state: { source: "", choice: "" }, profile: "" }, "waits for UPower")
        result = P.profileChange(result.state, { ready: true, source: "battery", choice: "powerSaver" })
        T.eq(result, { state: { source: "battery", choice: "powerSaver" }, profile: "" },
             "first source after start is only remembered")
        result = P.profileChange(result.state, { ready: true, source: "battery", choice: "powerSaver" })
        T.eq(result.profile, "", "same source and same choice changes nothing")
        result = P.profileChange(result.state, { ready: true, source: "ac", choice: "performance" })
        T.eq(result, { state: { source: "ac", choice: "performance" }, profile: "performance" },
             "plugging in applies the charger profile")

        // The half that was missing: the user is already on the charger and
        // picks a different profile for it. This used to do nothing at all
        // until the next unplug and plug.
        result = P.profileChange(result.state, { ready: true, source: "ac", choice: "balanced" })
        T.eq(result, { state: { source: "ac", choice: "balanced" }, profile: "balanced" },
             "a changed choice applies without the source changing")
        T.eq(P.profileChange(result.state, { ready: true, source: "ac", choice: "balanced" }).profile, "",
             "and only once - the same choice again changes nothing")
        T.eq(P.profileChange(result.state, { ready: true, source: "ac", choice: "keep" }),
             { state: { source: "ac", choice: "keep" }, profile: "" },
             "changing the choice to Don't change touches no profile, but is remembered")

        T.eq(P.profileChange({ source: "ac", choice: "keep" }, { ready: true, source: "battery", choice: "keep" }),
             { state: { source: "battery", choice: "keep" }, profile: "" }, "Don't change")
        T.eq(P.profileChange({ source: "ac", choice: "keep" }, { ready: true, source: "battery", choice: "turbo" }).profile, "", "unknown choice")
        T.eq(P.profileChange({ source: "ac", choice: "keep" }, { ready: true, source: "usb", choice: "balanced" }).state.source, "ac", "unknown source")
        T.eq(P.profileChange(null, { ready: true, source: "ac", choice: "balanced" }).profile, "", "no state")
        T.finish("PowerSourceTest")
    }
}
