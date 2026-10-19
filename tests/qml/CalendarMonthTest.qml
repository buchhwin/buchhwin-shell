import Quickshell
import QtQuick
import qs.theme
import qs.shell.components
import "Harness.js" as T

// The month's seven columns are one width each, whatever the weekday names
// are as text. With no width of its own a day cell left the names to share
// the row out: "Wed" took more than "Fri" and "Sat", which were squeezed
// together, the column steps 63/62/64/51/45/55 px on the dashboard. Laid out in an offscreen window, because a layout places its children
// only there; nothing here starts a service with a side effect.
ShellRoot {
    id: root

    FloatingWindow {
        implicitWidth: 480
        implicitHeight: 480

        CalendarMonth {
            id: month
            width: 420
            today: new Date(2026, 9, 16)
        }
        CalendarMonth {
            id: narrow
            width: 230
            today: new Date(2026, 9, 16)
        }
    }

    function grid(of) {
        for (const child of of.children)
            if (child.columns === 7) return child
        return null
    }
    function centres(items) { return items.map(item => item.x + item.width / 2) }
    function steps(values) { return values.slice(1).map((value, index) => value - values[index]) }
    function even(values) { return Math.max(...values) - Math.min(...values) <= 1 }

    function check(of, label) {
        const cells = grid(of)
        T.ok(cells !== null, label + ": the month has its grid")
        if (!cells) return
        const heads = cells.children.filter(child => typeof child.text === "string" && child.role === "small")
        const days = cells.children.filter(child => child.modelData !== undefined && child.modelData !== null
                                                   && child.modelData.date !== undefined)
        T.eq([heads.length, days.length], [7, 42], label + ": seven weekdays over six weeks")
        const headSteps = steps(centres(heads))
        T.ok(even(headSteps), label + ": the weekday columns step evenly " + JSON.stringify(headSteps))
        T.ok(even(steps(centres(days.slice(0, 7)))), label + ": and so do the days")
        T.ok(even(days.slice(0, 7).map(day => day.width)), label + ": every day cell is one width")
        T.ok(Math.abs(centres(heads)[4] - centres(days.slice(0, 7))[4]) <= 1, label + ": a day sits under its weekday")
        T.ok(heads[6].x + heads[6].width <= of.width + 1, label + ": the last column ends inside the month")
    }

    Timer {
        interval: 200
        running: true
        onTriggered: {
            root.check(month, "420 px")
            root.check(narrow, "230 px")
            T.finish("CalendarMonthTest")
        }
    }
}
