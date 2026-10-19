import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/components/PanelPlaceLogic.js" as P

// What a panel and a notification popup keep clear of (PanelPlaceLogic,
// ShellPanel's bottom/left/right offsets and the popup stack): the bar and the
// dock beyond it. Round 12: the notification center ran down over the
// taskbar, bar-pill panels and popups stood where the dock is beyond a
// bottom bar, the corner popups covered a right dock, and a key
// opened its panel under a desktop clock a screen away from the taskbar's
// bell. Pure logic: no service, no window.
ShellRoot {
    Component.onCompleted: {
        // ---- the dock's reach -----------------------------------------------
        const bottom = { position: "bottom", shown: true, reach: 56 }
        T.eq(P.dockReach(bottom, "bottom"), 56, "a shown bottom dock reaches in by its reach")
        T.eq(P.dockReach(bottom, "left"), 0, "and not from another edge")
        T.eq(P.dockReach({ position: "bottom", shown: false, reach: 56 }, "bottom"), 0, "a hidden dock keeps nothing clear")
        T.eq(P.dockReach(null, "bottom"), 0, "the dock off: nothing (DockService never asked)")
        T.eq(P.dockReach({ position: "right", shown: true, reach: "x" }, "right"), 0, "no number is no reach")
        // Where the body runs: a floating dock in the middle of a second
        // screen at x 1920 (DockService.bodies are global).
        const span = P.dockSpan({ x: 2720, y: 1130, width: 320, height: 62 }, "bottom", 1920, 0)
        T.eq(span, { from: 800, to: 1120 }, "the body's run along the bottom, on its own screen")
        T.eq(P.dockSpan({ x: 0, y: 400, width: 62, height: 300 }, "left", 0, 0), { from: 400, to: 700 }, "down a side")
        T.eq(P.dockSpan(null, "bottom", 0, 0), null, "no body: no span")
        const floating = Object.assign({ position: "bottom", shown: true, reach: 64 }, span)
        T.eq(P.dockReach(floating, "bottom", 1500, 1880), 0, "a corner beside a floating dock is not under it")
        T.eq(P.dockReach(floating, "bottom", 1000, 1400), 64, "one that comes over it is")
        T.eq(P.dockReach(floating, "bottom"), 64, "without a place along the edge, the whole edge counts")

        // ---- one edge ---------------------------------------------------------
        T.eq(P.edgeClear(-1, 0, 8, 16), 16, "no bar, no dock: the screen margin")
        T.eq(P.edgeClear(40, 0, 8, 16), 48, "a bar alone: its inset and the gap, as before")
        T.eq(P.edgeClear(0, 0, 8, 16), 8, "a bar of nothing still says the gap, as before")
        T.eq(P.edgeClear(-1, 56, 8, 16), 64, "the taskbar alone: above it by the gap (the notification center ended at 1184 of 1200)")
        T.eq(P.edgeClear(-1, 4, 8, 16), 16, "a dock thinner than the margin leaves the margin")
        T.eq(P.edgeClear(40, 56, 8, 16), 104, "a bottom bar with the dock beyond it: both and the gap")

        // ---- popups -----------------------------------------------------------
        // A 1920x1200 screen, a 380 x 300 stack, a gap of 8.
        const above = { x: 1524, y: 852 }       // above a 40 px bottom bar
        T.eq(P.clearOfDock(above, 380, 300, 1920, 1200, null, "bottom", 40, 8), above, "dock off: where the bar put it")
        T.eq(P.clearOfDock(above, 380, 300, 1920, 1200, bottom, "bottom", 40, 8), { x: 1524, y: 796 },
             "a bottom bar with the dock beyond: the stack stands above the dock")
        const corner = { x: 1524, y: 16 }
        T.eq(P.clearOfDock(corner, 380, 300, 1920, 1200, bottom, "top", 40, 8), corner,
             "a stack hanging from the top is not pushed by a bottom dock")
        const tall = { x: 1524, y: 860 }
        T.eq(P.clearOfDock(tall, 380, 300, 1920, 1200, bottom, "top", 40, 8), tall,
             "not even one that reaches it: it would be pushed into the bar")
        const right = { position: "right", shown: true, reach: 64 }
        T.eq(P.clearOfDock(corner, 380, 300, 1920, 1200, right, "top", 40, 8), { x: 1468, y: 16 },
             "the corner stack keeps off a right dock")
        T.eq(P.clearOfDock({ x: 1492, y: 400 }, 380, 300, 1920, 1200, right, "right", 40, 8), { x: 1428, y: 400 },
             "beside a right bar it keeps off the dock beyond the bar")
        const left = { position: "left", shown: true, reach: 64 }
        T.eq(P.clearOfDock({ x: 48, y: 400 }, 380, 300, 1920, 1200, left, "left", 40, 8), { x: 112, y: 400 },
             "beside a left bar too")
        T.eq(P.clearOfDock({ x: 700, y: 60 }, 380, 300, 1920, 1200, left, "top", 40, 8), { x: 700, y: 60 },
             "a stack clear of the dock stays where it is")
        T.eq(P.clearOfDock(null, 380, 300, 1920, 1200, bottom, "bottom", 40, 8), null, "nowhere stays nowhere")
        T.eq(P.clearOfDock(above, 380, 300, 1920, 1200, floating, "bottom", 40, 8), above,
             "the bell's popups at the bar's end stay where they are beside a floating dock in the middle")
        T.eq(P.clearOfDock({ x: 760, y: 852 }, 380, 300, 1920, 1200, floating, "bottom", 40, 8), { x: 760, y: 788 },
             "popups that would come down over it stand above it")

        // ---- opened by a key ----------------------------------------------------
        T.eq(P.dockItems("notifications"), ["notificationIndicator"], "Super+N comes out of the bell")
        T.eq(P.dockItems("controlCenter")[0], "quickPanel", "Super+O out of the control center's own widget first")
        T.ok(P.dockItems("controlCenter").indexOf("volume") > 0, "or out of the status group")
        T.eq(P.dockItems("dashboard"), ["clock", "date"], "Super+K out of the clock")
        T.eq(P.dockItems("settings"), [], "a panel with no widget stays where it opens")

        T.eq(P.placed({}), false, "a key says nothing about the place")
        T.eq(P.placed({ page: "updates", onScreen: "eDP-1" }), false, "nor do a page and a screen")
        T.eq(P.placed({ anchorX: 900 }), true, "a pill does")
        T.eq(P.placed({ anchorBottom: 1100, fromDock: true }), true, "the dock does")
        T.eq(P.placed({ fromNotch: true }), true, "the notch does")
        T.eq(P.placed({ anchorX: -1 }), false, "a negative anchor is no anchor")
        T.eq(P.placed(null), false, "no arguments at all")

        const rects = { volume: { x: 1700, y: 1148, width: 40, height: 52 }, network: { x: 1650, y: 1148, width: 40, height: 52 } }
        const lookup = type => rects[type] || null
        T.eq(P.firstRect(P.dockItems("controlCenter"), lookup), rects.volume, "the volume stands for the control center")
        T.eq(P.firstRect(["clock"], lookup), null, "no clock on the dock: nothing")
        T.eq(P.firstRect(["volume"], () => ({ x: 0, y: 0, width: 0, height: 0 })), null, "an empty rect is no rect")

        const bell = { x: 1760, y: 1148, width: 44, height: 52 }
        // What DockLogic.panelAnchor answers for it (its own tests cover that).
        const anchor = { anchorX: 1782, anchorBottom: 1140, fromDock: true }
        const opened = P.withDockItem({ page: "x" }, bell, anchor)
        T.eq([opened.fromDock, opened.anchorBottom, opened.anchorX, opened.page], [true, 1140, 1782, "x"],
             "a key's panel takes the click's anchor above the bell and keeps its own arguments")
        T.eq([opened.originX, opened.originY, opened.originWidth, opened.originHeight], [1760, 1148, 44, 52],
             "and grows out of the bell")
        const clicked = { anchorX: 300, originX: 280, originWidth: 40 }
        T.eq(P.withDockItem(clicked, bell, anchor), clicked, "a panel a click placed stays where the click put it")
        T.eq(P.withDockItem({}, null, anchor), {}, "no bell: as it was")
        T.eq(P.withDockItem({}, bell, {}), {}, "no anchor: as it was")

        // ---- the surface ------------------------------------------------------
        // Settings, the one panel that can be dragged, mapped the whole screen
        // for its 980 x 680 card on every open; it needs it only for a drag.
        T.eq(P.fullSurface(true, false, false), false, "a panel with a card, at rest: the card's surface, dragged or not")
        T.eq(P.fullSurface(true, false, true), true, "dragged by its title: the screen, so it can go anywhere")
        T.eq(P.fullSurface(true, true, false), true, "resized by its grip: the screen")
        T.eq(P.fullSurface(false, false, false), true, "no card (the overview): the screen")
        // Settings centred on 1920 x 1200 and moved by (100, -50), the pad 56.
        const settings = { x: (1920 - 980) / 2 + 100, y: (1200 - 680) / 2 - 50, width: 980, height: 680 }
        const surface = P.cardSurface(settings, null, 56, 1920, 1200, false)
        T.eq(surface, { x: 514, y: 154, width: 1092, height: 792 }, "the moved card and its pad, where it was moved to")
        T.ok(surface.width * surface.height < 0.4 * 1920 * 1200, "under two fifths of the screen's pixels")
        T.eq(P.cardSurface({ x: 10, y: 1000, width: 300, height: 180 }, null, 56, 1920, 1200, false),
             { x: 0, y: 944, width: 366, height: 256 }, "kept inside the screen")
        T.eq(P.cardSurface({ x: 1500, y: 60, width: 400, height: 500 }, { x: 860, y: 0, width: 200, height: 34 }, 56, 1920, 1200, false),
             { x: 804, y: 0, width: 1116, height: 616 }, "with what it grows out of")
        T.eq(P.cardSurface({ x: 1500, y: 60, width: 400, height: 500 }, null, 56, 1920, 1200, true),
             { x: 1444, y: 0, width: 476, height: 1200 }, "or the screen's whole height for a card that changes height")
        T.eq(P.cardSurface({ x: 5.5, y: 7.25, width: 100.2, height: 50 }, null, 0, 1920, 1200, false),
             { x: 5, y: 7, width: 101, height: 51 }, "whole pixels, outwards")

        // ---- out of a pill at the edge ----------------------------------------
        // The bar's last pill ends 6 px from the screen edge, a panel kept
        // 16 px: their right edges did not line up.
        T.eq(P.outerClear(16, 16, 6), 6, "out of a pill nearer the edge: as far out as the pill")
        T.eq(P.outerClear(16, 16, 400), 16, "out of one further in: the screen margin, as before")
        T.eq(P.outerClear(16, 16, -1), 16, "out of nothing: as before")
        T.eq(P.outerClear(64, 16, 6), 64, "a dock on that side stays clear, whatever opened the panel")
        T.eq(P.outerClear(16, 16, -0.5), 16, "a negative distance is no origin")

        T.finish("PanelPlaceTest")
    }
}
