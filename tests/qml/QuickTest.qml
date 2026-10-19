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
        T.eq(types(fresh).length, 13, "every tile is on a fresh panel")
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
        // The catalogue's floor holds for the file too, not only for a drag: a
        // drives tile written one column wide loads at its two.
        const flat = L.quickItems(L.sanitizeQuick({ quick: [{ id: "d", items: [{ type: "drives", w: 1, h: 1 }] },
                                                             { id: "m", items: [{ type: "media", w: 1, h: 1 }] }] }))
        T.eq(flat.map(item => [item.w, item.h]), [[2, 1], [1, 2]], "a file below the floor is raised to it on load")
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

        // ---- what the tiles ask of the services ------------------------------
        T.eq(Q.watches(["wifi", "phone"], true), { phone: true, fingerprint: false },
             "the phone tile has KDE Connect polled, and no reader is asked without its tile")
        T.eq(Q.watches(["fingerprint"], true), { phone: false, fingerprint: true }, "the fingerprint tile has the reader read")
        T.eq(Q.watches(["phone", "fingerprint"], false), { phone: false, fingerprint: false },
             "nothing while the overview is not shown")
        T.eq(Q.watches(undefined, true), { phone: false, fingerprint: false }, "no tiles known")

        // ---- what a tile draws at its size -----------------------------------
        // Rows decide, not the shape's name: one column of three rows is
        // "small" like one of two, and the brightness and battery tiles drew
        // their one-line form in it with 80 px of empty card around it.
        T.eq(Q.sliderCompact(3), false, "a slider tile of three rows has its title line")
        T.eq(Q.sliderCompact(2), true, "two rows hold one line: the slider comes up beside the glyph")
        T.eq(Q.sliderCompact(1), true, "and so does one")
        T.eq(Q.sliderCompact(5), false, "a tall tile is never compact")
        T.eq(Q.sliderCompact(undefined), true, "an unknown height is the smallest")
        T.eq([Q.size("brightness").h, Q.size("battery").h].map(Q.sliderCompact), [false, false],
             "where both start, they show their titles")
        T.eq(Q.audioParts("small", 3), { tabs: false, device: true }, "a one-column audio tile of three rows has its device")
        T.eq(Q.audioParts("small", 2), { tabs: false, device: false }, "two rows: the volume and the way to the page")
        T.eq(Q.audioParts("wide", 2), { tabs: false, device: false }, "wide and short: the same")
        T.eq(Q.audioParts("tall", 5), { tabs: true, device: true }, "tall: tabs, device and volume")
        T.eq(Q.audioParts("large", 3), { tabs: true, device: true }, "large: the same")

        // ---- the header's way to Settings and Escape --------------------------
        T.eq(["network", "bluetooth", "audio", "power", "dnd", "drives", "tray"].map(Q.settingsPage),
             ["network", "bluetooth", "audio", "power", "notifications", "desktop", "autostart"],
             "each detail page has the Settings page that belongs to it")
        T.eq(Q.settingsPage(""), "", "the overview leaves Settings where it was")
        T.eq(Q.settingsPage("constructor"), "", "an unknown page too, inherited names included")
        T.eq(Q.pageAfterEscape("network"), "", "Escape on a detail page goes back to the overview")
        T.eq(Q.pageAfterEscape(""), null, "and on the overview it is not the page's to take")

        // ---- chips sharing a row -----------------------------------------------
        // The control center's four at its default width: Power, Dark mode,
        // Displays and Focus need 160, 137, 160 and 106 of 600 px.
        T.eq(Q.chipWidths([160, 137, 160, 106], 600, 8), [160, 137, 160, 119],
             "the narrowest is raised first, nobody gets less than it needs")
        T.eq(Q.chipWidths([160, 137, 160, 106], 840, 8), [204, 204, 204, 204], "with room, one width for all")
        T.eq(Q.chipWidths([160, 137, 160, 106], 400, 8), [160, 137, 160, 106],
             "a row too short keeps the needs, and the layout shrinks them")
        T.eq(Q.chipWidths([100, 100], 208, 8), [100, 100], "exactly enough room")
        T.eq(Q.chipWidths([], 600, 8), [], "no chips")
        const shared = Q.chipWidths([160, 137, 160, 106], 600, 8)
        T.eq(shared.reduce((sum, value) => sum + value, 0) + 3 * 8, 600, "the shares fill the row")

        T.finish("QuickTest")
    }
}
