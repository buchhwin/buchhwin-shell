import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/audio/AudioRoutingLogic.js" as R

ShellRoot {
    Component.onCompleted: {
        // Synthetic `pw-metadata -n default` output (format of PipeWire 1.6).
        const dump = [
            "Found \"default\" metadata 39",
            "update: id:0 key:'default.audio.sink' value:'{\"name\":\"alsa_output.test.speaker\"}' type:'Spa:String:JSON'",
            "update: id:90 key:'target.object' value:'973' type:'Spa:Id'",
            "update: id:91 key:'target.object' value:'test_null_sink' type:'(null)'",
            "update: id:92 key:'target.node' value:'33' type:'Spa:Id'",
            "update: id:93 key:'target.object' value:'-1' type:'Spa:Id'",
            "update: id:94 key:'media.title' value:'it's got 'quotes'' type:''",
            ""
        ].join("\n")

        T.eq(R.parseLine("update: id:90 key:'target.object' value:'973' type:'Spa:Id'"),
             { action: "update", subject: 90, key: "target.object", value: "973", type: "Spa:Id" }, "update line")
        T.eq(R.parseLine("remove: id:90 key:'target.object'"), { action: "remove", subject: 90, key: "target.object" }, "remove key")
        T.eq(R.parseLine("remove: id:90 all keys"), { action: "removeAll", subject: 90 }, "remove all keys")
        T.eq([R.parseLine("Found \"default\" metadata 39"), R.parseLine("set property: id:90 key:target.object value:973 type:Spa:Id"),
              R.parseLine("delete property: id:90 key:target.object"), R.parseLine("")], [null, null, null, null], "other lines ignored")
        T.eq(R.parseLine("update: id:5 key:'k' value:'(null)' type:'(null)'").value, null, "null value")

        const entries = R.parseMetadata(dump)
        T.eq(Object.keys(entries).sort(), ["0", "90", "91", "92", "93", "94"], "subjects")
        T.eq(entries["94"]["media.title"].value, "it's got 'quotes'", "quotes inside values")
        T.eq(entries["91"]["target.object"].type, "", "(null) type")

        const sinks = [
            { id: 33, name: "test_null_sink", serial: 973 },
            { id: 57, name: "alsa_output.test.speaker", serial: 1200 }
        ]
        T.eq(R.streamTarget(entries, 90, sinks), "test_null_sink", "serial resolves to the sink name")
        T.eq(R.streamTarget(entries, "91", sinks), "test_null_sink", "node.name value")
        T.eq(R.streamTarget(entries, 92, sinks), "test_null_sink", "legacy target.node by id")
        T.eq(R.streamTarget(entries, 93, sinks), "", "-1 means default")
        T.eq(R.streamTarget(entries, 95, sinks), "", "no entry means default")
        T.eq(R.streamTarget(entries, 90, [sinks[1]]), "", "vanished sink falls back to default")
        T.eq(R.streamTarget(null, 90, sinks), "", "no metadata yet")

        // Monitor mode (`pw-metadata -m`) keeps the map current line by line.
        let live = R.applyLine({}, "update: id:90 key:'target.object' value:'1200' type:'Spa:Id'")
        T.eq(R.streamTarget(live, 90, sinks), "alsa_output.test.speaker", "live update")
        const same = R.applyLine(live, "Found \"default\" metadata 39")
        T.ok(same === live, "unrelated line keeps the object")
        live = R.applyLine(live, "update: id:90 key:'target.object' value:'973' type:'Spa:Id'")
        T.eq(R.streamTarget(live, 90, sinks), "test_null_sink", "moved again")
        live = R.applyLine(live, "remove: id:90 key:'target.object'")
        T.eq([R.streamTarget(live, 90, sinks), Object.keys(live)], ["", []], "removed key drops the empty subject")
        T.ok(R.applyLine(live, "remove: id:90 key:'target.object'") === live, "removing twice changes nothing")
        live = R.applyLine(entries, "remove: id:92 all keys")
        T.eq([("92" in live), ("92" in entries)], [false, true], "remove all keys without mutating the input")

        // Commands
        T.eq(R.moveCommand(90, sinks[0]), ["pw-metadata", "-n", "default", "90", "target.object", "973", "Spa:Id"], "move by serial")
        T.eq(R.moveCommand("90", { name: "test_null_sink", serial: undefined }),
             ["pw-metadata", "-n", "default", "90", "target.object", "test_null_sink"], "move by name without a serial")
        T.eq([R.moveCommand(0, sinks[0]), R.moveCommand(-3, sinks[0]), R.moveCommand("90; rm", sinks[0]), R.moveCommand(1.5, sinks[0]),
              R.moveCommand(90, null), R.moveCommand(90, { name: "-d", serial: "x" }), R.moveCommand(90, { name: "a b" })],
             [[], [], [], [], [], [], []], "invalid ids and names refused")
        T.eq(R.resetCommands(entries, 90), [["pw-metadata", "-n", "default", "-d", "90", "target.object"]], "reset")
        T.eq(R.resetCommands(entries, 92).length, 2, "reset also removes a legacy target.node")
        T.eq(R.resetCommands(entries, "x"), [], "reset refuses invalid ids")

        T.eq(R.outputOptions([{ name: "a", label: "Speaker" }, { name: "", label: "broken" }, { name: "b" }], "Default output"),
             [{ value: "", label: "Default output" }, { value: "a", label: "Speaker" }, { value: "b", label: "b" }], "selector options")
        T.ok(R.isMeterStream("buchhwin-shell-level-meter") && !R.isMeterStream("pw-record"), "level meter stream")
        T.finish("AudioRoutingTest")
    }
}
