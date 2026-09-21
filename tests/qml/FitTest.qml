import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/arrange/FitLogic.js" as F

ShellRoot {
    Component.onCompleted: {
        // Every cell the grid can grant gets exactly one class, and the class
        // is one of the five. GRID_MAX_W is 4 and GRID_MAX_H is 6, so this
        // walks the whole space rather than a few examples.
        let unknown = 0
        for (let w = 1; w <= 4; ++w)
            for (let h = 1; h <= 6; ++h)
                if (F.CLASSES.indexOf(F.fitClass(w, h)) < 0) unknown += 1
        T.eq(unknown, 0, "every cell of the 4x6 grid has a known class")

        T.eq(F.fitClass(1, 1), "icon", "one step each way is an icon")
        T.eq(F.fitClass(1, 2), "small", "a short single column is small")
        T.eq(F.fitClass(1, 3), "small", "three rows are still small")
        T.eq(F.fitClass(1, 4), "tall", "four rows in one column is tall")
        T.eq(F.fitClass(1, 6), "tall", "the tallest single column is tall")
        T.eq(F.fitClass(2, 1), "wide", "two columns and one row is wide")
        T.eq(F.fitClass(4, 2), "wide", "two rows across the grid is still wide")
        T.eq(F.fitClass(2, 3), "large", "width and height together is large")
        T.eq(F.fitClass(4, 6), "large", "the whole grid is large")

        // A shape is about the cell, not about the surface: the same steps
        // answer the same way for the notch and for the dashboard. How much
        // fits inside is the other question, and rowsFor has it.
        T.eq(F.fitClass(1, 2), F.fitClass("1", "2"), "numeric strings read as steps")
        T.eq(F.fitClass(0, 3), "small", "a cell with no width falls back to small")
        T.eq(F.fitClass(2, 0), "small", "a cell with no height falls back to small")
        T.eq(F.fitClass(undefined, undefined), "small", "nothing at all falls back to small")
        T.eq(F.fitClass(NaN, 2), "small", "an unreadable width falls back to small")
        T.eq(F.fitClass(1.4, 2.4), "small", "steps round rather than truncate")
        T.eq(F.fitClass(1.4, 3.6), "tall", "and rounding up can change the class")

        // A widget's ladder is a width ladder, and it is measured in pixels
        // rather than in steps: one column is 175 px on the notch, 210 in the
        // control center and 420 on the dashboard, so a step is not a width.
        T.eq(F.widgetSize(90, 40), "icon", "too narrow for a value is the glyph alone")
        T.eq(F.widgetSize(400, 20), "icon", "and so is too short for a line of text")
        T.eq(F.widgetSize(175, 40), "small", "a notch column is the glyph and the value")
        T.eq(F.widgetSize(210, 40), "small", "and so is a control center column")
        T.eq(F.widgetSize(300, 40), "medium", "wider takes the name in front of it")
        T.eq(F.widgetSize(420, 40), "large", "a dashboard column takes the detail line too")
        T.eq(F.widgetSize(0, 40), "small", "a cell of no width is not known yet")
        T.eq(F.widgetSize(undefined, undefined), "small", "nor is nothing at all")
        // "expanded" is the bar's pill display and never a grid shape.
        let expanded = 0
        for (let w = 0; w <= 900; w += 10)
            for (let h = 10; h <= 400; h += 10)
                if (F.widgetSize(w, h) === "expanded") expanded += 1
        T.eq(expanded, 0, "no cell ever asks a widget for the expanded display")

        // The counting half. Twelve pixels of room for a ten pixel row with a
        // two pixel gap is one row; twenty-two is two.
        T.eq(F.rowsFor(10, 10, 2), 1, "exactly one row fits")
        T.eq(F.rowsFor(21, 10, 2), 1, "one pixel short of two rows is one")
        T.eq(F.rowsFor(22, 10, 2), 2, "two rows and the gap between them")
        T.eq(F.rowsFor(34, 10, 2), 3, "three rows")
        T.eq(F.rowsFor(0, 10, 2), 1, "no room at all still shows one row")
        T.eq(F.rowsFor(100, 0, 2), 1, "a row with no height cannot be counted")
        T.eq(F.rowsFor(100, 10, undefined), 10, "no gap means no gap")

        T.eq(F.roomFor(40, 40), true, "exactly enough room is room")
        T.eq(F.roomFor(39, 40), false, "one pixel short is not")
        T.eq(F.roomFor(undefined, 40), false, "an unknown height has no room")

        T.eq(F.minSize({ minW: 2, minH: 3 }), { w: 2, h: 3 }, "a declared minimum is used")
        T.eq(F.minSize({}), { w: 1, h: 1 }, "without one a tile may go to a single step")
        T.eq(F.minSize(null), { w: 1, h: 1 }, "and so may an unknown type")
        T.eq(F.minSize({ minW: 0, minH: -2 }), { w: 1, h: 1 }, "a minimum below one step is one step")

        T.finish("FitTest")
    }
}
