import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/model/KeyedLogic.js" as Keyed

// What the dashboard and the launcher rely on to keep their slots across a
// layout write: a ScriptModel over the ids themselves keeps every delegate
// whose id is still there - taken out of the middle, put in between, moved -
// and never hands one delegate another id.
//
// Not `objectProp: "id"` over fresh objects: Quickshell 0.3.2 updates the
// first entry whose key matches in place and then goes on replacing by
// position, without comparing keys, until it meets the very same object. A
// list built anew on every write never has one, so every row after the
// first match was handed its neighbour's entry (DashboardPanel, Launcher).
ShellRoot {
    id: root
    property var ids: []
    // The other way: objects keyed by `objectProp`, as the overview, the
    // notch strip, the bar and the workspace dots hand them - fresh objects
    // on every change, passed through Keyed.keep so the unchanged ones are
    // the very same objects again.
    property var entries: []

    Item {
        Repeater {
            id: slots
            model: ScriptModel { values: root.ids }
            Item {
                required property string modelData
                required property int index
                // Set once, not bound: the id the delegate was made for.
                property string born: ""
                Component.onCompleted: born = modelData
            }
        }
    }

    Item {
        Repeater {
            id: keyed
            model: ScriptModel { values: root.entries; objectProp: "id" }
            Item {
                required property var modelData
                property string born: ""
                Component.onCompleted: born = modelData.id
            }
        }
    }
    function keyedDelegates() {
        const out = []
        for (let i = 0; i < keyed.count; ++i) out.push(keyed.itemAt(i))
        return out
    }
    function keyedById() {
        const table = {}
        for (const item of keyedDelegates()) table[item.modelData.id] = item
        return table
    }
    function fresh(list) {
        return list.map(entry => typeof entry === "string" ? { id: entry, v: 1 } : Object.assign({}, entry))
    }
    function hand(list) { entries = Keyed.keep(entries, fresh(list), "id") }
    function checkKeyed(label, expected, before) {
        const now = keyedDelegates()
        T.eq(now.map(item => item.modelData.id), expected, label + ": the order")
        T.eq(now.filter(item => item.born !== item.modelData.id).map(item => item.born + "->" + item.modelData.id), [],
             label + ": no delegate carries another entry")
        const kept = expected.filter(id => before[id] !== undefined)
        T.eq(kept.filter(id => keyedById()[id] !== before[id]), [], label + ": the ones still there are kept")
    }

    function delegates() {
        const out = []
        for (let i = 0; i < slots.count; ++i) out.push(slots.itemAt(i))
        return out
    }
    function byId() {
        const table = {}
        for (const item of delegates()) table[item.modelData] = item
        return table
    }
    // Every delegate still carries the id it was made for, in the list's order,
    // and the ones that were there before are the same objects.
    function check(label, expected, before) {
        const now = delegates()
        T.eq(now.map(item => item.modelData), expected, label + ": the order")
        T.eq(now.filter(item => item.born !== item.modelData).map(item => item.born + "->" + item.modelData), [],
             label + ": no delegate carries another id")
        const kept = expected.filter(id => before[id] !== undefined)
        T.eq(kept.filter(id => byId()[id] !== before[id]), [], label + ": the ones still there are kept")
    }

    Component.onCompleted: {
        // A new array each time, as a layout write hands over.
        ids = ["a", "b", "c", "d", "e"]
        T.eq(slots.count, 5, "five delegates")
        let before = byId()
        ids = ["a", "b", "d", "e"]
        check("taken out of the middle", ["a", "b", "d", "e"], before)
        before = byId()
        ids = ["a", "x", "b", "d", "e"]
        check("put in between", ["a", "x", "b", "d", "e"], before)
        before = byId()
        ids = ["e", "a", "x", "b", "d"]
        check("moved to the front", ["e", "a", "x", "b", "d"], before)
        before = byId()
        ids = ["e", "a", "x", "b", "d"].slice()
        check("the same list again", ["e", "a", "x", "b", "d"], before)

        // Keyed.keep itself: unchanged entries come back as the old objects,
        // a changed one as the new one, children kept by their own key.
        const first = [{ id: 1, windows: [{ address: "0xa" }, { address: "0xb" }] }, { id: 2, windows: [] }]
        const second = Keyed.keep(first, [{ id: 1, windows: [{ address: "0xa" }] }, { id: 2, windows: [] }, { id: 3 }],
                                  "id", { windows: "address" })
        T.ok(second[1] === first[1], "keep: an unchanged entry is the old object")
        T.ok(second[0] !== first[0], "keep: a changed entry is a new object")
        T.ok(second[0].windows[0] === first[0].windows[0], "keep: its unchanged child is the old object")
        T.eq(second[0].windows.length, 1, "keep: the child that went is gone")
        T.eq(second[2], { id: 3 }, "keep: a new entry is taken as it is")
        T.eq(Keyed.keep(null, [{ id: 1 }], "id"), [{ id: 1 }], "keep: nothing before")
        T.eq(Keyed.keep([{ id: 1 }], null, "id"), [], "keep: nothing now")

        // And the model, handed kept lists. Without keep, taking "c" out
        // gave c's delegate d and d's e, and destroyed e's.
        hand(["a", "b", "c", "d", "e"])
        T.eq(keyed.count, 5, "objects: five delegates")
        before = keyedById()
        hand(["a", "b", "d", "e"])
        checkKeyed("objects: taken out of the middle", ["a", "b", "d", "e"], before)
        before = keyedById()
        hand(["b", "d", "e"])
        checkKeyed("objects: the first taken out", ["b", "d", "e"], before)
        before = keyedById()
        hand(["b", "x", "d", "e"])
        checkKeyed("objects: put in between", ["b", "x", "d", "e"], before)
        before = keyedById()
        hand(["b", { id: "x", v: 2 }, "d", "e"])
        checkKeyed("objects: one changed", ["b", "x", "d", "e"], before)
        T.eq(keyedById()["x"].modelData.v, 2, "objects: the changed one has its new data")
        before = keyedById()
        hand(["e", "b", { id: "x", v: 2 }, "d"])
        checkKeyed("objects: moved to the front", ["e", "b", "x", "d"], before)
        before = keyedById()
        hand(["e", { id: "x", v: 2 }, { id: "d", v: 3 }])
        checkKeyed("objects: one out and one changed", ["e", "x", "d"], before)
        T.finish("KeyedModel")
    }
}
