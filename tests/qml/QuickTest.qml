import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/quick/QuickLogic.js" as Q

// The control center's tiles: the model behind them and the catalogue the
// picker offers. The tiles sit on the same zone -> pill -> item shape as the
// bar, with one zone and one tile per pill.
ShellRoot {
    function types(quick) { return L.quickTypes(quick) }

    Component.onCompleted: {
        // ---- defaults ------------------------------------------------------
        const fresh = L.defaultQuick()
        T.eq(types(fresh).length, 12, "every tile is on a fresh panel")
        T.eq(types(fresh)[0], "wifi", "Wi-Fi comes first")
        T.ok(types(fresh).every(type => Q.isKnown(type)), "every default tile is in the catalogue")
        T.eq(fresh.quick.map(pill => pill.items.length), types(fresh).map(() => 1), "one tile per pill")

        // ---- reading a file back --------------------------------------------
        T.eq(types(L.sanitizeQuick(null)), types(fresh), "no list at all falls back to the defaults")
        T.eq(types(L.sanitizeQuick({ quick: [] })), types(fresh), "an empty list falls back too")
        const two = L.sanitizeQuick({ quick: [
            { id: "a", items: [{ type: "wifi" }] },
            { id: "b", items: [{ type: "media" }] }
        ] })
        T.eq(types(two), ["wifi", "media"], "a short list is kept as it is")
        const smuggled = L.sanitizeQuick({ quick: [{ id: "a", items: [{ type: "wifi" }, { type: "media" }] }] })
        T.eq(types(smuggled), ["wifi"], "a pill with two tiles keeps the first, not both")
        const clash = L.sanitizeQuick({ quick: [
            { id: "same", items: [{ type: "wifi" }] },
            { id: "same", items: [{ type: "media" }] }
        ] })
        T.ok(clash.quick[0].id !== clash.quick[1].id, "two tiles never share an id")
        T.eq(types(L.sanitizeQuick({ quick: [{ id: "a", items: [] }, { id: "b", items: [{ type: "dnd" }] }] })),
             ["dnd"], "a pill without a tile is dropped")

        // ---- moving ---------------------------------------------------------
        T.eq(types(L.moveQuickTile(two, "b", -1)), ["media", "wifi"], "a tile moves one place up")
        T.eq(types(L.moveQuickTile(two, "a", -1)), ["wifi", "media"], "the first tile cannot move further up")
        T.eq(types(L.moveQuickTile(two, "b", 1)), ["wifi", "media"], "the last cannot move further down")
        T.eq(types(L.moveQuickTile(two, "nope", 1)), ["wifi", "media"], "an unknown tile changes nothing")
        const three = L.addQuickTile(two, "battery")
        T.eq(types(L.moveQuickTileTo(three, "a", 2)), ["media", "battery", "wifi"], "dropped on the last place")
        T.eq(types(L.moveQuickTileTo(three, "a", 99)), ["media", "battery", "wifi"], "an index past the end is the end")
        T.eq(types(L.moveQuickTileTo(three, "a", -5)), ["wifi", "media", "battery"], "an index before the start is the start")

        // ---- adding and removing --------------------------------------------
        T.eq(types(L.addQuickTile(two, "battery")), ["wifi", "media", "battery"], "a tile is added at the end")
        T.eq(types(L.addQuickTile(two, "wifi")), ["wifi", "media"], "a tile that is already there is not added twice")
        T.eq(types(L.addQuickTile(two, "")), ["wifi", "media"], "nothing to add")
        T.eq(types(L.removeQuickTile(two, "a")), ["media"], "a tile is removed")
        T.eq(types(L.removeQuickTile(two, "nope")), ["wifi", "media"], "removing an unknown tile changes nothing")
        // Removing the last one falls back to the defaults on the next read,
        // so the panel is never empty.
        T.eq(types(L.sanitizeQuick(L.removeQuickTile(L.removeQuickTile(two, "a"), "b"))), types(fresh),
             "an empty panel comes back with the defaults")

        // Operations never touch what they were given.
        L.addQuickTile(two, "battery")
        L.removeQuickTile(two, "a")
        L.moveQuickTile(two, "b", -1)
        T.eq(types(two), ["wifi", "media"], "the original list is never changed")

        // ---- the catalogue ---------------------------------------------------
        T.eq(Q.label("wifi"), "Wi-Fi", "a tile has a name")
        T.eq(Q.label("nonsense"), "nonsense", "an unknown type is its own name")
        T.eq(Q.isKnown("phone"), true, "the phone tile is known")
        T.eq(Q.isKnown("nonsense"), false, "and nonsense is not")
        T.eq([Q.size("fingerprint"), Q.size("wifi")], [{ w: 2, h: 2 }, { w: 1, h: 2 }],
             "where a tile starts in the grid: the whole row or half of it")
        T.eq(Q.size("media").h, 5, "a card that draws more starts taller")
        T.eq(Q.size("nothing"), { w: 1, h: 2 }, "an unknown type starts as a plain tile")
        // The stored tiles carry it, and a corner drag changes it.
        const q = L.defaultQuick()
        const first = L.quickItems(q)[0]
        T.eq([first.w, first.h], [1, 2], "a default tile is stored with its size")
        T.eq(L.quickItems(L.setQuickTileSize(q, first.id, 2, 4))[0].w, 2, "a corner dragged out")
        T.eq(L.quickItems(L.setQuickTileSize(q, first.id, 99, 99))[0].h, 6, "never past the grid")
        T.eq(L.quickItems(L.setQuickTileSize(q, "nothing", 2, 2))[0], first, "an unknown id changes nothing")
        T.eq(Q.missing(["wifi", "bluetooth"]).length, Q.catalogue.length - 2, "the picker offers what is not shown")
        T.eq(Q.missing([]).length, Q.catalogue.length, "an empty panel can have everything back")
        T.eq(Q.missing(Q.catalogue.map(tile => tile.type)).length, 0, "a full panel offers nothing")
        T.ok(Q.catalogue.every(tile => tile.icon.length > 0), "every tile has an icon for the picker")

        // ---- the one-shot markers -------------------------------------------
        // They live in the layout file, with the data they guard. The tiles'
        // marker used to live in settings.json while the sizes lived here, so
        // restoring one file without the other reset every hand-set size.
        const plain = L.sanitize(null)
        T.eq(plain.adopted, [], "a fresh file has run nothing")
        T.ok(!L.hasAdopted(plain, "quickSizes"), "and says so")
        const marked = L.sanitize(Object.assign({}, plain, { adopted: L.withAdopted(plain, "quickSizes") }))
        T.ok(L.hasAdopted(marked, "quickSizes"), "a marker survives being written and read back")
        T.eq(L.withAdopted(marked, "quickSizes"), ["quickSizes"], "marking twice marks once")
        T.eq(L.sanitize({ adopted: ["quickSizes", 7, ""] }).adopted, ["quickSizes"],
             "anything that is not a name is dropped")
        // The reset itself: every tile back to the size its type starts at.
        const hand = L.setQuickTileSize(L.defaultQuick(), L.quickItems(L.defaultQuick())[0].id, 2, 4)
        T.eq(L.quickItems(L.adoptQuickSizes(hand))[0].w, 1, "adopting puts a tile back to its own start size")

        // A surface takes a desktop widget beside its own tiles, but only one
        // the caller vouches for: the widget registry is a QML singleton and
        // the layout library cannot see it, so the guard is a callback.
        const knows = type => type === "cpu" || type === "clock"
        const withWidget = L.addQuickTile(fresh, "cpu", knows)
        T.eq(types(withWidget).slice(-1), ["cpu"], "a widget the caller knows is taken")
        T.eq(types(L.addQuickTile(fresh, "cpu")), types(fresh), "and refused without the callback")
        T.eq(types(L.addQuickTile(fresh, "not a widget", knows)), types(fresh), "as is one it does not know")
        T.eq(types(L.addQuickTile(withWidget, "cpu", knows)), types(withWidget), "and never twice")

        T.finish("QuickTest")
    }
}
