import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/EdgeShapeLogic.js" as E

// The outline of a body hanging from a screen edge, as the notch hangs from
// the top one (services/appearance/EdgeShapeLogic.js): the dock on the edge.
ShellRoot {
    Component.onCompleted: {
        const pick = shape => [shape.start].concat(shape.segments).map(p => [p.x, p.y])
        const turns = shape => shape.segments.filter(p => p.arc).map(p => p.clockwise)

        // The top edge is the notch's own path: ear, side, corner, bottom, corner, side, ear.
        const top = E.outline("top", 100, 300, 40, 7, 11, 1000, 60)
        T.eq(pick(top), [[93, 0], [100, 7], [100, 29], [111, 40], [289, 40], [300, 29], [300, 7], [307, 0]], "the notch's outline on the top edge")
        T.eq(turns(top), [true, false, false, true], "concave ears clockwise, convex corners counterclockwise, as Notch.qml draws them")

        // The bottom edge: the same, upside down from the surface's bottom.
        const bottom = E.outline("bottom", 100, 300, 64, 7, 14, 1000, 120)
        T.eq(pick(bottom), [[93, 120], [100, 113], [100, 70], [114, 56], [286, 56], [300, 70], [300, 113], [307, 120]],
             "from the bottom edge up")
        T.eq(turns(bottom), [false, true, true, false], "a mirror image turns every arc the other way")

        // The sides: the left one mirrored, the right one the top one turned.
        const left = E.outline("left", 200, 500, 64, 7, 14, 120, 900)
        T.eq([left.start, left.segments[2], left.segments[6]].map(p => [p.x, p.y]), [[0, 193], [64, 214], [0, 507]], "the left edge")
        T.eq(turns(left), [false, true, true, false], "mirrored")
        const right = E.outline("right", 200, 500, 64, 7, 14, 120, 900)
        T.eq([right.start, right.segments[2], right.segments[6]].map(p => [p.x, p.y]), [[120, 193], [56, 214], [120, 507]], "the right edge")
        T.eq(turns(right), [true, false, false, true], "turned, so the arcs keep their way")

        // What does not fit is made smaller.
        T.eq(E.fit(3, 300, 64, 7, 14, 1000), { ear: 3, radius: 14 }, "an ear no wider than the room beside the body")
        T.eq(E.fit(100, 120, 64, 7, 14, 1000), { ear: 7, radius: 10 }, "corners no rounder than half the body's length")
        T.eq(E.fit(100, 300, 10, 7, 14, 1000), { ear: 5, radius: 5 }, "nor than half its depth")
        T.eq(E.fit(0, 1000, 64, 7, 14, 1000).ear, 0, "along the whole edge: no ears")

        T.finish("EdgeShapeTest")
    }
}
