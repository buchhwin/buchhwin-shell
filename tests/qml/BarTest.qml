import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/bar/BarLogic.js" as B

ShellRoot {
    function shape(bar) {
        const describe = zone => bar[zone].map(pill => pill.items.map(item => item.type + (item.display === "icon" ? "*" : "")).join("+"))
        return { left: describe("left"), center: describe("center"), right: describe("right") }
    }

    Component.onCompleted: {
        // Defaults and sanitizing
        const initial = L.sanitizeBar(undefined)
        T.eq(shape(initial), { left: ["nowPlaying*"], center: ["clock"], right: ["network*"] }, "default bar like the mockup")
        T.eq([initial.reserve, initial.fullscreen, initial.scale], [true, "hide", 1], "default options")
        T.eq([initial.style, initial.position, initial.edge], ["pills", "floating", "top"], "default style pills, floating, at the top")
        T.eq([L.defaultBar().style, L.defaultBar().position, L.defaultBar().edge], ["pills", "floating", "top"], "default bar template style")
        const dirty = L.sanitizeBar({ reserve: 0, fullscreen: "sometimes", scale: 9,
            left: [{ id: "a", items: [{ type: "clock", display: "huge", options: { x: 1, bad: {} } }, { type: "" }] }, { id: "a", items: [{ type: "date" }] }, { items: [] }, null],
            center: "nope" })
        T.eq([dirty.reserve, dirty.fullscreen, dirty.scale], [false, "hide", 1.5], "options sanitized")
        T.eq(shape(dirty), { left: ["clock", "date"], center: [], right: [] }, "invalid pills and items dropped")
        T.ok(dirty.left[0].id !== dirty.left[1].id, "duplicate pill ids renamed")
        T.eq(dirty.left[0].items[0], { type: "clock", display: "full", size: "small", w: 1, h: 1, options: { x: 1 } }, "item sanitized")
        T.eq([L.sanitizeBar({ left: [{ id: "a", items: [{ type: "clock", w: 2, h: 3 }] }] }).left[0].items[0].w,
              L.sanitizeBar({ left: [{ id: "a", items: [{ type: "clock", w: 2, h: 3 }] }] }).left[0].items[0].h], [2, 3],
             "a stored grid size survives")
        T.eq([L.sanitizeBar({ left: [{ id: "a", items: [{ type: "clock", w: 99, h: 99 }] }] }).left[0].items[0].w,
              L.sanitizeBar({ left: [{ id: "a", items: [{ type: "clock", w: 99, h: 99 }] }] }).left[0].items[0].h], [4, 6],
             "and a size no grid has room for is clamped")
        const oldBar = L.sanitizeBar({ reserve: false, left: [{ id: "a", items: [{ type: "clock" }] }], center: [], right: [] })
        T.eq([oldBar.style, oldBar.position, oldBar.reserve], ["pills", "floating", false], "a bar without style migrates to pills")
        // Sanitizing is total, so the edge needs no migration: a file written
        // before it existed is read as a bar at the top.
        T.eq(oldBar.edge, "top", "a bar written before edges existed is a top bar")
        T.eq(L.sanitizeBar({ edge: "bottom" }).edge, "bottom", "a stored edge is kept")
        T.eq(L.sanitizeBar({ edge: "left" }).edge, "left", "and so is a vertical one")
        T.eq(L.sanitizeBar({ edge: "right" }).edge, "right", "either way round")
        T.eq(L.sanitizeBar({ edge: "sideways" }).edge, "top", "an edge nobody knows is the top")
        T.eq(L.copyBar(L.sanitizeBar({ edge: "bottom" })).edge, "bottom", "operations keep the edge")
        T.eq(L.addPill(L.sanitizeBar({ edge: "bottom" }), "left", "clock").edge, "bottom", "editing pills keeps it too")
        T.eq(L.sanitize({ profiles: { work: { bar: { edge: "bottom", left: [], center: [], right: [] } } } })
             .profiles.work.bar.edge, "bottom", "and a profile carries it")
        T.eq([L.sanitizeBar({ style: "bar", position: "attached" }).style, L.sanitizeBar({ style: "bar", position: "attached" }).position], ["bar", "attached"], "style and position kept")
        T.eq([L.sanitizeBar({ style: "island", position: 3 }).style, L.sanitizeBar({ style: "island", position: 3 }).position], ["pills", "floating"], "unknown style and position fall back")
        T.eq(L.copyBar(L.sanitizeBar({ style: "bar", position: "attached" })).position, "attached", "operations keep the style")
        T.eq(L.addPill(L.sanitizeBar({ style: "bar" }), "left", "clock").style, "bar", "editing pills keeps the bar style")
        T.eq(L.sanitize({ profiles: { work: { mode: "pills", bar: { style: "bar", position: "attached", left: [], center: [], right: [] } } } }).profiles.work.bar.position, "attached", "profile keeps the bar position")
        T.eq(L.sanitizeBar({ left: [{ id: "m", items: [{ type: "nowPlaying", display: "expanded" }] }] }).left[0].items[0].display, "expanded", "expanded display kept")
        T.eq(shape(L.sanitizeBar({ left: [], center: [], right: [] })), { left: [], center: [], right: [] }, "an emptied bar stays empty")

        // Profile integration
        const config = L.sanitize({ activeProfile: "work", profiles: { work: { widgets: [], groups: [], mode: "pills" }, minimal: { mode: "weird" } } })
        T.eq(config.profiles.work.mode, "pills", "mode kept")
        T.eq(config.profiles.minimal.mode, "widgets", "unknown mode falls back to widgets")
        T.eq(shape(config.profiles.minimal.bar), shape(L.defaultBar()), "missing bar gets defaults")
        const notchConfig = L.sanitize({ profiles: { work: { mode: "notch", bar: { left: [{ id: "x", items: [{ type: "battery" }] }], center: [], right: [] } } } })
        T.eq(notchConfig.profiles.work.mode, "notch", "notch mode kept")
        T.eq(shape(notchConfig.profiles.work.bar).left, ["battery"], "custom pills kept in notch mode")

        // Exactly one surface per mode
        T.eq(L.MODES, ["widgets", "pills", "notch"], "three exclusive modes, no \"both\"")
        T.eq(L.modeShows("widgets"), { widgets: true, bar: false, notch: false }, "widgets mode")
        T.eq(L.modeShows("pills"), { widgets: false, bar: true, notch: false }, "pills mode shows only the bar")
        T.eq(L.modeShows("notch"), { widgets: false, bar: false, notch: true }, "notch mode shows only the notch")
        T.eq(L.modeShows(undefined), { widgets: true, bar: false, notch: false }, "unknown mode like widgets")
        T.ok(L.MODES.every(mode => Object.keys(L.modeShows(mode)).filter(key => L.modeShows(mode)[key]).length === 1),
             "every mode shows exactly one surface")

        // Migration of the removed "both" mode
        T.eq(L.modeName("both"), "pills", "\"both\" migrates to the bar")
        T.eq([L.modeName("pills"), L.modeName("notch"), L.modeName("island"), L.modeName(undefined)],
             ["pills", "notch", "widgets", "widgets"], "known modes kept, unknown ones fall back")
        T.eq(L.modeShows("both"), L.modeShows("pills"), "an old \"both\" layout shows the bar")
        T.eq([L.modeLabel("widgets"), L.modeLabel("pills"), L.modeLabel("notch"), L.modeLabel("both")],
             ["Widgets", "Bar", "Notch", "Bar"], "mode labels")
        const legacy = L.sanitize({ profiles: { work: { mode: "both", widgets: [{ id: "w", type: "clock", screen: "S" }],
                                                        bar: { left: [{ id: "p", items: [{ type: "battery" }] }], center: [], right: [] } } } })
        T.eq(legacy.profiles.work.mode, "pills", "stored \"both\" migrates on load")
        T.eq(legacy.profiles.work.widgets.length, 1, "the widgets of a \"both\" layout survive")
        T.eq(shape(legacy.profiles.work.bar).left, ["battery"], "the pills of a \"both\" layout survive")

        // Operations never mutate their input
        let bar = L.defaultBar()
        const before = JSON.stringify(bar)
        bar = L.addPill(bar, "right", "battery", "full")
        T.eq(JSON.stringify(L.defaultBar()), before, "operations return copies")
        T.eq(shape(bar).right, ["network*", "battery"], "add pill")
        T.eq(shape(L.addPill(bar, "top", "clock")).right, ["network*", "battery"], "unknown zone ignored")
        const batteryPill = bar.right[1].id
        bar = L.addItem(bar, batteryPill, "volume", "icon")
        T.eq(shape(bar).right, ["network*", "battery+volume*"], "add item to pill")
        bar = L.moveItem(bar, batteryPill, 1, -1)
        T.eq(shape(bar).right, ["network*", "volume*+battery"], "move item")
        T.eq(shape(L.moveItem(bar, batteryPill, 0, -1)).right, ["network*", "volume*+battery"], "move beyond start ignored")
        bar = L.setItemDisplay(bar, batteryPill, 0, "full")
        T.eq(shape(bar).right, ["network*", "volume+battery"], "display changed")
        bar = L.splitItem(bar, batteryPill, 1)
        T.eq(shape(bar).right, ["network*", "volume", "battery"], "split item into own pill")
        const networkPill = bar.right[0].id
        bar = L.mergeWithNext(bar, networkPill)
        T.eq(shape(bar).right, ["network*+volume", "battery"], "merge with next pill")

        // Moving pills within and across zones
        bar = L.movePill(bar, networkPill, 1)
        T.eq(shape(bar).right, ["battery", "network*+volume"], "move pill right within zone")
        bar = L.movePill(bar, networkPill, 1)
        T.eq(shape(bar).right, ["battery", "network*+volume"], "rightmost pill stays")
        const clockPill = bar.center[0].id
        bar = L.movePill(bar, clockPill, 1)
        T.eq([shape(bar).center, shape(bar).right], [[], ["clock", "battery", "network*+volume"]], "move past zone end into next zone")
        bar = L.movePill(bar, clockPill, -1)
        T.eq([shape(bar).center, shape(bar).right[0]], [["clock"], "battery"], "move back into previous zone")
        const mediaPill = bar.left[0].id
        T.eq(shape(L.movePill(bar, mediaPill, -1)).left, ["nowPlaying*"], "leftmost zone start stays")

        // Dropping a pill on an exact place (editor drag and drop)
        T.eq(shape(L.movePillTo(bar, mediaPill, "right", 1)),
             { left: [], center: ["clock"], right: ["battery", "nowPlaying*", "network*+volume"] }, "drop into another zone at an index")
        T.eq(shape(L.movePillTo(bar, mediaPill, "left", 0)).left, ["nowPlaying*"], "dropping on its own place keeps the order")
        T.eq(shape(L.movePillTo(bar, mediaPill, "center", 99)).center, ["clock", "nowPlaying*"], "an index past the end appends")
        T.eq(shape(L.movePillTo(bar, mediaPill, "center", -3)).center, ["nowPlaying*", "clock"], "a negative index prepends")
        T.eq(shape(L.movePillTo(bar, mediaPill, "top", 0)), shape(bar), "unknown zone ignored")
        T.eq(shape(L.movePillTo(bar, "missing", "right", 0)), shape(bar), "unknown pill ignored")
        T.eq(shape(L.movePillTo(bar, bar.right[0].id, "right", 1)).right, ["network*+volume", "battery"], "reorder inside a zone")
        const beforeDrop = JSON.stringify(bar)
        L.movePillTo(bar, mediaPill, "right", 0)
        T.eq(JSON.stringify(bar), beforeDrop, "movePillTo returns a copy")

        // Removing
        bar = L.removeItem(bar, bar.left[0].id, 0)
        T.eq(shape(bar).left, [], "pill without items disappears")
        bar = L.removePill(bar, clockPill)
        T.eq(shape(bar).center, [], "remove pill")
        T.eq(L.findPill(bar, "missing"), null, "unknown pill")
        T.eq(L.findPill(bar, networkPill).zone, "right", "find pill")
        T.ok(L.barPillIds(L.addPill(L.addPill(bar, "left", "clock"), "left", "date")).every((id, index, all) => all.indexOf(id) === index), "new pill ids are unique")

        // Bar style geometry (BarLogic)
        T.eq([B.style("bar"), B.style("x"), B.position("attached"), B.position(undefined)], ["bar", "pills", "attached", "floating"], "style and position names")
        T.eq([B.edge("bottom"), B.edge("left"), B.edge("right"), B.edge(undefined)],
             ["bottom", "left", "right", "top"], "all four edges, and an absent one is the top")
        T.eq([B.vertical("top"), B.vertical("bottom"), B.vertical("left"), B.vertical("right")],
             [false, false, true, true], "left and right run down the screen")
        T.eq([B.farEdge("top"), B.farEdge("bottom"), B.farEdge("left"), B.farEdge("right")],
             [false, true, false, true], "the bottom and the right hang from the far edge")
        const metrics = { height: 32, margin: 6, radius: 12, border: 1 }
        const pills = B.geometry("pills", "attached", "top", 1280, metrics, true)
        T.eq([pills.thickness, pills.exclusiveZone, pills.inset, pills.background], [38, 38, 38, null], "pills: margin plus height, no bar background")
        T.eq(pills.content, { x: 6, y: 6, width: 1268, height: 32 }, "pills: zones inside the margin (position ignored)")
        const floating = B.geometry("bar", "floating", "top", 1280, metrics, true)
        T.eq([floating.thickness, floating.exclusiveZone, floating.inset], [38, 38, 38], "floating bar reserves margin plus height")
        T.eq(floating.background, { x: 6, y: 6, width: 1268, height: 32 }, "floating bar inset by the margin")
        T.eq(floating.radii, { topLeft: 12, topRight: 12, bottomLeft: 12, bottomRight: 12 }, "floating bar rounds every corner")
        T.eq(B.geometry("bar", "floating", "top", 1280, metrics, false).exclusiveZone, 0, "no reserve, no zone")
        const attached = B.geometry("bar", "attached", "top", 1280, metrics, true)
        T.eq([attached.exclusiveZone, attached.inset], [32, 32], "attached bar reserves its height and no more")
        T.eq(attached.thickness, 44, "and reaches below it far enough to draw the corners")
        T.eq(attached.content, { x: 0, y: 0, width: 1280, height: 32 }, "attached bar spans the screen")
        T.eq(attached.background, { x: -2, y: -2, width: 1284, height: 34 }, "attached border hidden past the top and sides")
        T.eq(attached.radii, { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 },
             "attached bar is square: it fills through to its own bottom edge")
        T.eq(attached.corners, 12, "and hangs the rounding under itself instead")
        const square = B.geometry("bar", "attached", "top", 1280, Object.assign({}, metrics, { radius: 0 }), true)
        T.eq([square.corners, square.thickness], [0, 32], "shell radius 0: no corners and nothing hanging below")
        T.eq(B.geometry("bar", "attached", "top", 1280, metrics, false).exclusiveZone, 0, "an attached bar that does not reserve takes nothing")
        T.eq(B.geometry("bar", "floating", "top", 1280, metrics, true).corners, 0, "only an attached bar has them")
        T.eq(B.geometry("bar", "floating", "top", 1280, Object.assign({}, metrics, { radius: 40 }), true).radii.topLeft, 16, "radius capped at a round end")
        T.eq(B.geometry("bar", "floating", "top", 1280, Object.assign({}, metrics, { height: 36.8, margin: 6 }), true).exclusiveZone, 42.8, "scaled height")
        T.eq(B.geometry("bar", "floating", "top", 8, metrics, true).background.width, 0, "tiny screen never negative")
        T.eq([B.cornerRadius(32, 12), B.cornerRadius(32, 20), B.cornerRadius(32, -3), B.cornerRadius(32, NaN)], [12, 16, 0, 0], "corner radius")

        // The same bar at the bottom edge. Everything measured from the bar's
        // own edge is unchanged; what mirrors is which side the margin is on
        // and which way the attached bar's rounding hangs.
        const lowPills = B.geometry("pills", "floating", "bottom", 1280, metrics, true)
        T.eq([lowPills.thickness, lowPills.exclusiveZone, lowPills.inset], [38, 38, 38],
             "a bottom bar reaches as far into the screen as a top one")
        T.eq(lowPills.content, { x: 6, y: 0, width: 1268, height: 32 },
             "and puts its margin below itself, not above")
        T.eq(lowPills.edge, "bottom", "the geometry says which edge it is on")
        T.eq(B.geometry("pills", "floating", "top", 1280, metrics, true).edge, "top", "and so does a top one")
        const lowFloating = B.geometry("bar", "floating", "bottom", 1280, metrics, true)
        T.eq(lowFloating.background, { x: 6, y: 0, width: 1268, height: 32 }, "a floating bottom bar sits on its own edge")
        T.eq(lowFloating.radii, { topLeft: 12, topRight: 12, bottomLeft: 12, bottomRight: 12 }, "and still rounds every corner")
        const lowAttached = B.geometry("bar", "attached", "bottom", 1280, metrics, true)
        T.eq([lowAttached.exclusiveZone, lowAttached.inset], [32, 32], "an attached bottom bar reserves its height and no more")
        T.eq(lowAttached.thickness, 44, "and reaches the same 12 past itself to draw the corners")
        T.eq(lowAttached.corners, 12, "which are the same corners")
        T.eq(lowAttached.content, { x: 0, y: 12, width: 1280, height: 32 },
             "the bar itself sits past them, against the screen's bottom edge")
        T.eq(lowAttached.background, { x: -2, y: 12, width: 1284, height: 34 },
             "and its border hides past the bottom and the sides, never over the corners")
        T.eq(B.geometry("bar", "attached", "bottom", 1280, Object.assign({}, metrics, { radius: 0 }), true).content.y, 0,
             "shell radius 0: nothing hangs, so the bar starts at its own edge")
        // The same bar, turned on its side. The length it is given is the
        // screen's *height* now, and every rect comes back with its axes
        // swapped - which is the whole claim of writing the geometry in the
        // bar's own directions and mapping to x and y in one place.
        const sidePills = B.geometry("pills", "floating", "left", 800, metrics, true)
        T.eq([sidePills.thickness, sidePills.exclusiveZone, sidePills.inset], [38, 38, 38],
             "a left bar reaches as far into the screen as a top one")
        T.eq(sidePills.content, { x: 6, y: 6, width: 32, height: 788 },
             "its content runs down the screen, a pill wide")
        T.eq([sidePills.vertical, sidePills.edge], [true, "left"], "and it says so")
        T.eq(B.geometry("pills", "floating", "top", 800, metrics, true).vertical, false, "a top bar does not")

        // The far edge mirrors, exactly as the bottom one does: the margin
        // goes on the side away from the screen edge.
        const rightPills = B.geometry("pills", "floating", "right", 800, metrics, true)
        T.eq(rightPills.content, { x: 0, y: 6, width: 32, height: 788 },
             "a right bar puts its margin to its left, not its right")

        const sideAttached = B.geometry("bar", "attached", "left", 800, metrics, true)
        T.eq([sideAttached.exclusiveZone, sideAttached.inset], [32, 32],
             "an attached left bar reserves its width and no more")
        T.eq(sideAttached.thickness, 44, "and reaches the same 12 past itself to draw the corners")
        T.eq(sideAttached.corners, 12, "which are the same corners")
        T.eq(sideAttached.content, { x: 0, y: 0, width: 32, height: 800 },
             "the bar spans the whole edge it hangs from")
        T.eq(sideAttached.background, { x: -2, y: -2, width: 34, height: 804 },
             "its border hides past its own side and both ends")

        const rightAttached = B.geometry("bar", "attached", "right", 800, metrics, true)
        T.eq(rightAttached.content, { x: 12, y: 0, width: 32, height: 800 },
             "an attached right bar sits past its corners, against the screen's right edge")
        T.eq(rightAttached.background, { x: 12, y: -2, width: 34, height: 804 },
             "and its border never runs over them")
        T.eq(B.geometry("bar", "attached", "right", 800, Object.assign({}, metrics, { radius: 0 }), true).content.x, 0,
             "shell radius 0: nothing hangs, so the bar starts at its own edge")

        // A vertical bar is a transposed horizontal one and nothing more: the
        // numbers have to match across the swap or the two have drifted.
        const acrossTop = B.geometry("bar", "attached", "top", 800, metrics, true)
        T.eq([sideAttached.content.width, sideAttached.content.height],
             [acrossTop.content.height, acrossTop.content.width],
             "the left bar's content is the top bar's, with its axes swapped")
        T.eq(sideAttached.thickness, acrossTop.thickness, "and it is the same thickness")

        // How thick the bar is. The padding is an across-axis number, so a
        // horizontal bar never sees it however wide its widgets are, and a
        // vertical one gets it twice - once on each side, which is the half
        // that was missing: the room was made and then all of it was put
        // against the screen edge.
        T.eq([B.barThickness("top", 32, 3), B.barThickness("bottom", 32, 3)], [32, 32],
             "a horizontal bar is exactly a pill thick, padding or no padding")
        T.eq([B.barThickness("left", 32, 3), B.barThickness("right", 32, 3)], [38, 38],
             "a vertical bar is a pill plus the padding on each side")
        T.eq(B.barThickness("left", 32, 0), 32, "no padding, no difference")
        T.eq((B.barThickness("left", 32, 3) - 32) / 2, 3, "and half of the room belongs on each side")
        T.eq(B.barThickness("sideways", 32, 3), 32, "an edge nobody knows is the top, so no padding")
        T.eq(B.barThickness("left", 32, -5), 32, "a negative padding is no padding")

        // Where the bar's surface sits on the screen. Everything the bar
        // reports is mapped to its own window, and the window is only as thick
        // as the bar - so on a bottom or a right bar a reported rectangle is
        // most of a screen away from where it is. This is the correction, and
        // its absence is why an OSD came out of the top of the screen from a
        // widget on a bottom bar, and out of the left edge from one on a right
        // bar, while the editor drew every frame along the opposite edge.
        T.eq(B.surfaceOrigin("top", 38, 1920, 1080), { x: 0, y: 0 }, "a top bar's window starts where the screen does")
        T.eq(B.surfaceOrigin("left", 38, 1920, 1080), { x: 0, y: 0 }, "and so does a left bar's")
        T.eq(B.surfaceOrigin("bottom", 38, 1920, 1080), { x: 0, y: 1042 }, "a bottom bar's window is its own thickness up from the edge")
        T.eq(B.surfaceOrigin("right", 38, 1920, 1080), { x: 1882, y: 0 }, "a right bar's is its own thickness in from the side")
        T.eq(B.surfaceOrigin("right", 44, 1920, 1080), { x: 1876, y: 0 }, "an attached bar reaching further for its corners moves with it")
        T.eq(B.surfaceOrigin("bottom", 2000, 1920, 1080), { x: 0, y: 0 }, "a bar thicker than its screen never reports a negative origin")
        T.eq(B.surfaceOrigin("sideways", 38, 1920, 1080), { x: 0, y: 0 }, "an edge nobody knows is the top, here too")

        // An unknown edge is the top one, the way an unknown style is pills.
        T.eq(B.geometry("bar", "attached", "sideways", 1280, metrics, true).content,
             B.geometry("bar", "attached", "top", 1280, metrics, true).content,
             "an edge nobody knows is the top")
        T.eq([B.highlightRadius(12, 3, 26), B.highlightRadius(2, 3, 26), B.highlightRadius(40, 3, 26)], [9, 0, 13], "hover highlight concentric and capped")
        T.eq(B.highlightRadius(12, 3, 26, true), 13, "round cover: round highlight ends")
        T.eq([B.zoneInset("pills", "attached", 3, 4), B.zoneInset("bar", "floating", 3, 4), B.zoneInset("bar", "attached", 3, 4)], [0, 3, 4], "zone inset per style")

        // Separators between visible groups
        T.eq(B.separators([true, true, true]), [false, true, true], "between groups")
        T.eq(B.separators([false, true, false, true]), [false, false, false, true], "hidden groups skipped")
        T.eq(B.separators([false, false]), [false, false], "nothing visible")
        T.eq(B.separators(null), [], "no groups")

        // Segment padding and popup anchor
        const pads = { cover: 4, highlight: 3, icon: 8, text: 10 }
        T.eq(B.segmentPadding(false, false, false, pads), { start: 10, end: 10 }, "text item padding")
        T.eq(B.segmentPadding(false, false, true, pads), { start: 8, end: 8 }, "icon item padding")
        T.eq(B.segmentPadding(true, false, false, pads), { start: 1, end: 10 }, "cover at the start keeps the inset gap")
        T.eq(B.segmentPadding(true, true, true, pads), { start: 1, end: 1 }, "cover only")
        T.eq([B.anchorAlong(100, 40), B.anchorAlong(100.4, 41)], [120, 121], "popup centred on the item along the bar")
        T.finish("BarTest")
    }
}
