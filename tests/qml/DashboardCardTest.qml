import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components
import "Harness.js" as T
import "../../services/dashboard/DashboardLogic.js" as D

// The month card against the cell it is given. A month is six weeks, always
// (CalendarMonth draws 42 days), and at the four rows Default ships it in the
// sixth week was cut off below the card's edge - 30 November 2026 was not on
// the dashboard in November. The card is built here the way DashboardPanel
// builds it, and measured, so the minimum follows the grid if either changes.
ShellRoot {
    id: root

    property Item box: Item {
        width: Metrics.dashboardGridCell
        height: 2000
        CardSection {
            id: card
            width: parent.width
            padding: Metrics.spaceMd
            CalendarMonth {
                Layout.fillWidth: true
                today: new Date(2026, 10, 18)
                selectable: true
            }
        }
    }

    function check() {
        const unit = Metrics.dashboardGridUnit
        const gap = Metrics.cardGridGap
        const least = D.minSize("calendar")
        T.ok(card.implicitHeight > 0, "the month card has a height")
        T.ok(D.cellHeight(least.h, unit, gap) >= card.implicitHeight,
             "the smallest month cell holds all six weeks: " + D.cellHeight(least.h, unit, gap)
             + " px for a card of " + card.implicitHeight)
        T.ok(least.h <= 6, "and fits the grid's ceiling of six rows")

        // The cell a stored card is drawn in.
        T.eq(D.shownSize("calendar", 1, 4), { w: 1, h: least.h },
             "a month stored at four rows (Default's) is drawn at the minimum")
        T.eq(D.shownSize("calendar", 2, 6), { w: 2, h: 6 }, "a larger one at its own size")
        T.eq(D.shownSize("weather", 1, 1), { w: 1, h: 2 }, "the forecast's minimum as well")
        T.eq(D.shownSize("cpu", 1, 1), { w: 1, h: 1 }, "a desktop widget has none")
        T.eq(D.shownSize("clock", 0, 0), { w: 1, h: 1 }, "nothing stored is one step")

        T.eq([D.cellHeight(1, 64, 12), D.cellHeight(5, 64, 12)], [64, 368], "a cell is its rows and the gaps between them")

        T.finish("DashboardCardTest")
    }

    // The layouts settle after creation; measured a moment later.
    Timer {
        interval: 200
        running: true
        onTriggered: root.check()
    }
}
