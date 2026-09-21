import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/Usage.js" as U

ShellRoot {
    Component.onCompleted: {
        const day = 86400000
        const now = 1800000000000
        T.eq(U.parse("{bad"), {}, "broken file")
        T.eq(U.parse(JSON.stringify({ version: 1, apps: { "kitty": { count: 3, last: now }, "bad id": { count: 1, last: now }, "zero": { count: 0, last: now } } })),
             { "kitty": { count: 3, last: now } }, "invalid entries dropped")
        let usage = U.record(U.record({}, "kitty", now - day), "kitty", now)
        T.eq(usage.kitty, { count: 2, last: now }, "launches counted")
        T.near(U.frecency(usage, "kitty", now + 14 * day), 1, "half-life after 14 days", 1e-9)
        T.eq(U.frecency(usage, "missing", now), 0, "unknown app")
        usage = U.record(usage, "brave", now)
        T.ok(U.frecency(usage, "kitty", now) > U.frecency(usage, "brave", now), "more launches rank higher")
        T.ok(U.boost(usage, "kitty", now) > 0 && U.boost(usage, "kitty", now) <= 15, "boost bounded")
        let many = {}
        for (let i = 0; i < 210; ++i) many = U.record(many, "app" + i, now + i)
        T.eq(Object.keys(many).length, U.MAX_ENTRIES, "history capped")
        T.ok(many["app0"] === undefined && many["app209"] !== undefined, "oldest entries dropped first")
        T.eq(U.parse(U.serialize(usage)), usage, "round trip")
        T.finish("UsageTest")
    }
}
