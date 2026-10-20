import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/brightness/DdcLogic.js" as Ddc

// The brightness of external monitors over DDC/CI (DdcLogic): what ddcutil
// says, which monitor it means, what runs next. Invented monitors and serial
// numbers throughout.
ShellRoot {
    // `ddcutil detect --brief` as ddcutil 3.0 writes it: two monitors that
    // answered behind a dock, the laptop panel (never DDC), and an older
    // build's spelling of the connector.
    readonly property string detectText: [
        "Display 1",
        "   I2C bus:          /dev/i2c-10",
        "   DRM connector:    card1-DP-8",
        "   drm_connector_id: 401",
        "   Monitor:          SMP:Sample 4K A:SN0001",
        "",
        "Display 2",
        "   I2C bus:          /dev/i2c-11",
        "   DRM_connector:    card1-DP-10",
        "   Monitor:          SMP:Sample 4K B:SN0002",
        "",
        "Invalid display",
        "   I2C bus:          /dev/i2c-2",
        "   DRM connector:    card1-eDP-1",
        "   drm_connector_id: 393",
        "   Monitor:          LEN::",
        ""
    ].join("\n")

    readonly property var monitors: [
        { name: "eDP-1", description: "Sample Panel 14", model: "0x41B5", disabled: false },
        { name: "DP-8", description: "Sample Inc. Sample 4K A SN0001", model: "Sample 4K A", disabled: false },
        { name: "DP-10", description: "Sample Inc. Sample 4K B SN0002", model: "Sample 4K B", disabled: false },
        { name: "DP-13", description: "Sample Inc. Sample Portrait SN0003", model: "Sample Portrait", disabled: false }
    ]

    Component.onCompleted: {
        const found = Ddc.parseDetect(detectText)
        T.eq(found.map(d => [d.valid, d.bus, d.connector]), [[true, 10, "DP-8"], [true, 11, "DP-10"], [false, 2, "eDP-1"]],
             "displays, buses and connectors, the card prefix gone")
        T.eq([found[0].mfg, found[0].model, found[0].serial], ["SMP", "Sample 4K A", "SN0001"], "the monitor line in its parts")
        T.eq([found[2].mfg, found[2].model, found[2].serial], ["LEN", "", ""], "an empty model and serial")
        T.eq(Ddc.parseDetect("No displays found.\n"), [{ valid: false, bus: -1, connector: "", mfg: "", model: "", serial: "" }],
             "nothing found is nothing usable")
        T.eq(Ddc.parseDetect(""), [], "no output")
        T.eq(Ddc.parseDetect("Phantom display\n   I2C bus: /dev/i2c-12\n")[0].valid, false, "a phantom display did not answer")
        T.eq(Ddc.parseDetect("Display 1\n   I2C bus:  /dev/i2c-4\n   Monitor:  SMP:Model:With:Colons:SN9\n")[0].model, "Model:With:Colons",
             "a model with colons in it")

        T.eq(Ddc.parseVcp("VCP 10 C 60 100\n"), { value: 60, max: 100 }, "getvcp's brief answer")
        T.eq(Ddc.parseVcp("VCP 10 C 120 100"), { value: 100, max: 100 }, "a value past the maximum is the maximum")
        T.eq(Ddc.parseVcp("VCP 10 C 0 0"), null, "a maximum of 0 is no brightness")
        T.eq(Ddc.parseVcp("VCP 10 ERR"), null, "an error")
        T.eq(Ddc.parseVcp("Display not found"), null, "anything else")

        // Which of Hyprland's monitors each answer belongs to.
        T.eq(Ddc.match(found, monitors, "eDP-1"), [
            { name: "DP-8", description: "Sample Inc. Sample 4K A SN0001", bus: 10 },
            { name: "DP-10", description: "Sample Inc. Sample 4K B SN0002", bus: 11 }],
             "by connector; the panel and the screen that did not answer have none")
        const unnamed = Ddc.parseDetect("Display 1\n   I2C bus: /dev/i2c-14\n   Monitor: SMP:Sample Portrait:SN0003\n")
        T.eq(Ddc.match(unnamed, monitors, "eDP-1").map(d => [d.name, d.bus]), [["DP-13", 14]],
             "without a connector: by model and serial")
        const twins = Ddc.parseDetect("Display 1\n   I2C bus: /dev/i2c-14\n   Monitor: SMP:Sample 4K A:\n\nDisplay 2\n   I2C bus: /dev/i2c-15\n   Monitor: SMP:Sample 4K A:\n")
        const twinScreens = [{ name: "DP-1", description: "Sample 4K A", model: "Sample 4K A" },
                             { name: "DP-2", description: "Sample 4K A", model: "Sample 4K A" }]
        T.eq(Ddc.match(twins, twinScreens, ""), [], "two that fit equally: neither is guessed")
        T.eq(Ddc.match(found, monitors.map(m => m.name === "DP-8" ? Object.assign({}, m, { disabled: true }) : m), "eDP-1").map(d => d.name),
             ["DP-10"], "a monitor that is off has no level")
        const doubled = Ddc.parseDetect("Display 1\n   I2C bus: /dev/i2c-10\n   DRM connector: card1-DP-8\n")
        T.eq(Ddc.match(doubled.concat(doubled), monitors, "eDP-1").length, 1, "one display, one monitor")
        T.eq(Ddc.match(found, [], "eDP-1"), [], "no monitors")

        // When detection has to run again.
        const key = Ddc.externalKey(monitors, "eDP-1")
        T.ok(key.length > 0 && key.indexOf("eDP-1") < 0, "the external monitors, never the panel")
        T.eq(Ddc.externalKey([monitors[0]], "eDP-1"), "", "the laptop alone: nothing, and nothing runs")
        T.eq(Ddc.externalKey(monitors, "eDP-1"), Ddc.externalKey(monitors.slice().reverse(), "eDP-1"), "in any order")
        T.ok(Ddc.externalKey(monitors, "eDP-1") !== Ddc.externalKey(monitors.slice(0, 3), "eDP-1"), "a monitor unplugged is a change")
        T.eq(Ddc.externalKey([{ name: "eDP-1", description: "x" }], ""), "", "a panel by its connector name even unnamed")

        // What detection found, kept while a monitor stays connected: asked
        // once per hotplug, in the background, never again for a screen
        // switched off and on.
        const keyOf = name => Ddc.monitorKey(monitors.find(m => m.name === name))
        T.eq(Ddc.monitorKey(monitors[1]), "DP-8\u0001Sample Inc. Sample 4K A SN0001", "a monitor by connector and description")
        T.eq(Ddc.connectedExternals(monitors.map(m => m.name === "DP-8" ? Object.assign({}, m, { disabled: true }) : m), "eDP-1").map(m => m.name),
             ["DP-8", "DP-10", "DP-13"], "connected: on or off, never the panel")
        T.eq(Ddc.unasked({}, monitors, "eDP-1"), ["DP-8", "DP-10", "DP-13"], "plugged in: every external screen on is to be asked")
        T.eq(Ddc.unasked({}, [monitors[0]], "eDP-1"), [], "the laptop alone: nothing to ask")
        const asked = [keyOf("DP-8"), keyOf("DP-10"), keyOf("DP-13")]
        const seen = Ddc.remember({}, asked, Ddc.match(found, monitors, "eDP-1"), monitors, "eDP-1")
        T.eq(seen, { [keyOf("DP-8")]: 10, [keyOf("DP-10")]: 11, [keyOf("DP-13")]: -1 }, "each asked: its bus, or -1 for no answer")
        T.eq(Ddc.unasked(seen, monitors, "eDP-1"), [], "then nothing is asked again")
        T.eq(Ddc.usable(seen, monitors, "eDP-1"), [
            { name: "DP-8", description: "Sample Inc. Sample 4K A SN0001", bus: 10 },
            { name: "DP-10", description: "Sample Inc. Sample 4K B SN0002", bus: 11 }], "the displays: the ones that answered")
        const dp8Off = monitors.map(m => m.name === "DP-8" ? Object.assign({}, m, { disabled: true }) : m)
        T.ok(Ddc.keepConnected(seen, dp8Off, "eDP-1") === seen, "a screen switched off is still connected: the same answers")
        T.eq(Ddc.usable(seen, dp8Off, "eDP-1").map(d => d.name), ["DP-10"], "and has no level while off")
        T.eq(Ddc.unasked(seen, monitors, "eDP-1"), [], "switched on again: nothing to ask")
        const unplugged = Ddc.keepConnected(seen, monitors.filter(m => m.name !== "DP-8"), "eDP-1")
        T.eq(Object.keys(unplugged).length, 2, "unplugged: its answer is gone")
        T.eq(Ddc.unasked(unplugged, monitors, "eDP-1"), ["DP-8"], "plugged in again: asked again, its bus may be another")
        const swapped = monitors.map(m => m.name === "DP-8" ? Object.assign({}, m, { description: "Sample Other" }) : m)
        T.eq(Ddc.unasked(Ddc.keepConnected(seen, swapped, "eDP-1"), swapped, "eDP-1"), ["DP-8"], "another screen on the same connector is asked")
        T.eq(Ddc.remember(seen, [keyOf("DP-8")], [], dp8Off, "eDP-1"), seen, "one that went off while it ran is not marked")
        T.eq(Ddc.remember({}, [keyOf("DP-8")], Ddc.match(found, monitors, "eDP-1"), monitors, "eDP-1"), { [keyOf("DP-8")]: 10 },
             "only the monitors it asked: one that came on meanwhile is asked next")
        T.eq(Ddc.usable({ [keyOf("DP-8")]: -1 }, monitors, "eDP-1"), [], "one marked as not answering has no level")
        T.eq([Ddc.unasked(null, null, ""), Ddc.usable(null, null, ""), Ddc.keepConnected(null, [], "")], [[], [], {}], "nothing known")

        // The commands: bounded, the bus by number.
        T.eq(Ddc.detectCommand("ddcutil"), ["timeout", "30", "ddcutil", "detect", "--brief"], "detect")
        T.eq(Ddc.readCommand("ddcutil", 10), ["timeout", "8", "ddcutil", "getvcp", "10", "--brief", "--bus", "10"], "read")
        T.eq(Ddc.writeCommand("ddcutil", 11, 42.4), ["timeout", "8", "ddcutil", "setvcp", "10", "42", "--bus", "11", "--noverify"], "write")

        // Levels and steps.
        T.eq([Ddc.fromRatio(0.5, 100), Ddc.fromRatio(2, 100), Ddc.fromRatio(-1, 100), Ddc.fromRatio(0.5, 0)], [50, 100, 0, 0],
             "a slider's 0-1 in the monitor's range")
        T.eq([Ddc.toRatio(25, 50), Ddc.toRatio(80, 0)], [0.5, 0], "and back")
        T.eq(Ddc.stepped(50, 100, 1), 55, "one key: five percent")
        T.eq(Ddc.stepped(50, 100, -3), 35, "three down")
        T.eq(Ddc.stepped(98, 100, 1), 100, "not past the top")
        T.eq(Ddc.stepped(2, 100, -1), 0, "nor below 0")
        T.eq(Ddc.stepped(5, 10, 1), 6, "a short range moves one at least")
        T.eq(Ddc.stepped(5, 0, 1), 0, "no range, no level")

        // What runs next.
        const ready = { name: "DP-8", bus: 10, value: 50, max: 100, pending: -1, read: true, failed: false }
        T.eq(Ddc.nextJob(true, [Object.assign({}, ready, { pending: 60 })]), { kind: "detect" }, "detection first")
        T.eq(Ddc.nextJob(false, [Object.assign({}, ready, { read: false }), Object.assign({}, ready, { name: "DP-10", bus: 11, pending: 70 })]),
             { kind: "write", name: "DP-10", bus: 11, value: 70 }, "a write before a read")
        T.eq(Ddc.nextJob(false, [Object.assign({}, ready, { read: false })]), { kind: "read", name: "DP-8", bus: 10 }, "then the read")
        T.eq(Ddc.nextJob(false, [Object.assign({}, ready, { max: 0, read: false, pending: 30 })]), { kind: "read", name: "DP-8", bus: 10 },
             "a level not known yet is read before anything is written")
        T.eq(Ddc.nextJob(false, [Object.assign({}, ready, { failed: true, pending: 60, read: false })]), null, "a display that stopped answering is left alone")
        T.eq(Ddc.nextJob(false, [ready]), null, "nothing to do")
        T.eq(Ddc.nextJob(false, null), null, "nothing known")

        T.finish("DdcTest")
    }
}
