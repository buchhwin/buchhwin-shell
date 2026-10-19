import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/profile/AutoModeLogic.js" as A

// "Choose the mode automatically" with targets the user picks: at the desk,
// on the road, on battery. Shipped as before: Docked, Laptop, nothing.
ShellRoot {
    Component.onCompleted: {
        const modes = ["minimal", "work", "gaming", "laptop", "docked"]
        const read = values => path => values[path]

        // ---- the stored targets ------------------------------------------------
        T.eq(A.targets(read({}), modes), { desk: "docked", road: "laptop", battery: "" }, "nothing stored: as before")
        T.eq(A.targets(read({ "desktop.autoModeDesk": "minimal", "desktop.autoModeRoad": "minimal",
                              "desktop.autoModeBattery": "gaming" }), modes),
             { desk: "minimal", road: "minimal", battery: "gaming" }, "the user's own")
        T.eq(A.targets(read({ "desktop.autoModeDesk": "cinema", "desktop.autoModeRoad": 3 }), modes),
             { desk: "docked", road: "laptop", battery: "" }, "a mode that is not there, or no string, is the default")
        T.eq(A.target("", "battery", modes), "", "no battery target is a choice")
        T.eq(A.target("", "desk", modes), "docked", "no desk target is not")
        T.eq(A.target("work", "desk", []), "work", "no mode list: the five")
        T.eq(A.targets(null, modes), { desk: "docked", road: "laptop", battery: "" }, "no reader at all")

        // ---- which mode to be in -------------------------------------------------
        const shipped = { desk: "docked", road: "laptop", battery: "" }
        T.eq([A.suggested("docked", false, shipped), A.suggested("laptop", false, shipped),
              A.suggested("laptop", true, shipped), A.suggested("", true, shipped)],
             ["docked", "laptop", "laptop", ""], "shipped: as the switching always did")
        const own = { desk: "minimal", road: "minimal", battery: "gaming" }
        T.eq(A.suggested("docked", false, own), "minimal", "at the desk: the desk's target")
        T.eq(A.suggested("laptop", false, own), "minimal", "on the road, plugged in")
        T.eq(A.suggested("laptop", true, own), "gaming", "on the road on battery")
        T.eq(A.suggested("docked", true, own), "minimal", "at the desk the battery does not count")
        T.eq(A.suggested("", false, own), "", "a machine without a panel keeps its mode")
        T.eq(A.suggested("laptop", true, null), "laptop", "no targets: the defaults")

        // ---- the mode key's rule ---------------------------------------------------
        T.eq(A.owned(shipped), ["docked", "laptop"], "shipped: the two it always owned")
        T.eq(A.owned(own), ["minimal", "gaming"], "each target once")
        T.eq(A.owned({ desk: "work", road: "work", battery: "" }), ["work"], "one mode for both")
        T.eq([A.watchesBattery(shipped), A.watchesBattery(own), A.watchesBattery(null)], [false, true, false],
             "the power state is read only with a battery target")

        // ---- Settings' choices -------------------------------------------------------
        const templates = { docked: { label: "Desk" }, laptop: { label: "Laptop" } }
        T.eq(A.options("desk", ["laptop", "docked"], templates), [{ value: "laptop", label: "Laptop" }, { value: "docked", label: "Desk" }],
             "the modes with their labels")
        T.eq(A.options("battery", ["laptop"], {}).map(option => option.value), ["", "laptop"], "battery leads with as on the road")
        T.eq(A.options("battery", ["laptop"], {})[0].label, "As on the road", "and says so")

        T.finish("AutoModeTest")
    }
}
