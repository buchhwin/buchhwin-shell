import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../config/migrations/Migrations.js" as Migrations
import "../../services/LayoutLogic.js" as Logic

ShellRoot {
    // A layout file has two levels since v3: profile, then mode. The v2 to v3
    // step and the acceptance test that it changes nothing are in
    // ProfileLevelTest.
    function mode(config, name) { return Logic.modeConfig(config, "default", name) }

    FileView { id: legacy; path: Qt.resolvedUrl("../fixtures/layout-v1-legacy-clock.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: future; path: Qt.resolvedUrl("../fixtures/layout-v4-future.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: broken; path: Qt.resolvedUrl("../fixtures/layout-broken.json").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        const empty = Migrations.migrate("")
        T.ok(empty.ok && !empty.readOnly && !empty.changed, "empty file uses defaults without writing")

        const result = Migrations.migrate(legacy.text())
        T.ok(result.ok && result.changed, "v1 migrates")
        T.eq(result.from, 1, "source version")
        // v1 knew one layout; v3 has two levels, so it lands in the Default
        // profile's `minimal` mode. Both migration steps run in one pass.
        T.eq(result.to, 3, "and lands on the current version")
        const profile = mode(result.config, "minimal")
        const clock = profile.widgets.find(widget => widget.type === "clock")
        T.eq(clock.id, "clock-eDP-1", "clock id")
        T.eq([clock.x, clock.y, clock.scale, clock.anchorX], [0.9, 0.05, 1.2, "right"], "legacy clock fields keep position")
        T.eq(profile.widgets.find(widget => widget.type === "date").visible, true, "date visibility kept")
        T.eq(profile.widgets.find(widget => widget.type === "battery").visible, false, "battery visibility kept")
        T.eq(profile.screens, ["eDP-1"], "migrated screen is materialized")

        const plain = Migrations.migrate({ configVersion: 1, monitors: { "HDMI-A-1": { widgets: {} } } })
        T.eq(mode(plain.config, "minimal").widgets.length, 1, "v1 screen without entries keeps default clock")

        const newer = Migrations.migrate(future.text())
        T.ok(!newer.ok && newer.readOnly, "future version is read-only")
        const bad = Migrations.migrate(broken.text())
        T.ok(!bad.ok && bad.readOnly, "broken JSON is read-only")

        const sane = Logic.sanitize({ activeMode: "work", profiles: { default: { modes: { work: {
            widgets: [{ id: "a", type: "clock", screen: "X", x: 4, y: -1, scale: 9, style: "neon", extra: {}, options: { a: 1, b: {} } },
                      { id: "b", type: "date", screen: "X", group: "missing" }],
            groups: [{ id: "g", screen: "X", members: ["a", "ghost"] }, { id: "empty", screen: "X", members: [] }] } } } } })
        const saneMode = mode(sane, "work")
        const saneWidget = saneMode.widgets[0]
        T.eq([saneWidget.x, saneWidget.y, saneWidget.scale, saneWidget.style], [1, 0, 2, "minimal"], "sanitize clamps values")
        T.eq(saneWidget.options, { a: 1 }, "sanitize keeps primitive options only")
        T.ok(saneWidget.extra === undefined, "sanitize drops unknown fields")
        T.eq(saneMode.groups.map(group => group.id), ["g"], "empty groups removed")
        T.eq(saneMode.groups[0].members, ["a"], "unknown members removed")
        T.eq(saneMode.widgets[1].group, "", "dangling group reference cleared")

        const made = Logic.materialize({ widgets: [
            { key: "c", type: "clock", screen: "*", anchorX: "right", x: 0.98, y: 0.02 },
            { key: "b", type: "battery", screen: "*", x: 0.9, y: 0.02 },
            { key: "w", type: "weather", screen: "*" }],
            groups: [{ members: ["b", "c"], x: 0.98, y: 0.02 }] }, "DP-1", ["clock-DP-1"], type => type !== "weather")
        T.eq(made.widgets.map(widget => widget.id), ["clock-DP-1-2", "battery-DP-1"], "materialize avoids id clashes and unknown types")
        T.eq(made.groups[0].members, ["battery-DP-1", "clock-DP-1-2"], "template groups map keys")
        T.eq(made.widgets[0].group, made.groups[0].id, "grouped widget references group")

        const profileState = { widgets: made.widgets, groups: made.groups }
        T.eq(Logic.placements(profileState, "DP-1", false), [made.groups[0].id], "grouped widgets are placed through the group")

        T.eq(Logic.pixelPosition({ anchorX: "right", x: 1, y: 0 }, 100, 40, 1000, 500), { x: 900, y: 0 }, "right anchor")
        T.eq(Logic.pixelPosition({ anchorX: "center", x: 0.5, y: 0.5 }, 100, 40, 1000, 500), { x: 450, y: 250 }, "center anchor")
        T.eq(Logic.relativePosition(10, 50, 100, 40, 1000, 500), { anchorX: "left", x: 0.01, y: 0.1 }, "left third")
        T.eq(Logic.relativePosition(880, 0, 100, 40, 1000, 500), { anchorX: "right", x: 0.98, y: 0 }, "right third")

        T.finish("MigrationTest")
    }
}
