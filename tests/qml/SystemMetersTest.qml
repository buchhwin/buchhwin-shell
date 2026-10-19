import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.shell.components
import "Harness.js" as T

// The CPU, memory and disk rows of the system popup and the dashboard's card
// stay the rows they were when a sample comes in: they were built anew every
// two seconds, and a bar that is built anew starts at its new width, so the
// glide between samples never ran. SystemStatsService only reads /proc here.
ShellRoot {
    id: root

    SystemMeters { id: meters; width: 300 }

    function rows() {
        const found = []
        for (const child of meters.children)
            if (child instanceof ColumnLayout && child.entry !== undefined) found.push(child)
        return found
    }

    Component.onCompleted: {
        SystemStatsService.cpu = 0.2
        const before = rows()
        T.eq(before.map(row => row.entry.label), ["CPU", "Memory", "Disk"], "three rows, in their order")
        T.near(before[0].entry.usage, 0.2, "the CPU row reads the service")
        SystemStatsService.cpu = 0.3
        const after = rows()
        T.eq(after.length, 3, "still three rows after a sample")
        T.ok(after[0] === before[0] && after[1] === before[1] && after[2] === before[2],
             "and the same three: nothing is built anew")
        T.near(after[0].entry.usage, 0.3, "the row reads the new figure")
        meters.maxRows = 2
        T.eq(rows().map(row => row.visible), [true, true, false], "a cell with room for two hides the third")
        T.finish("SystemMetersTest")
    }
}
