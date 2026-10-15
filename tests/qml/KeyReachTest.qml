import Quickshell
import QtQuick
import qs.theme
import qs.shell.components
import qs.shell.notifications
import "Harness.js" as T
import "../../shell/components/NavLogic.js" as Nav

// What the pointer could click and the keys could not reach: a day in the
// month, the month's way back to today, the media card's click and a
// notification's default action. Each is a stop for the panel's keys
// (NavLogic) only where it does something, and Return does what the click does.
ShellRoot {
    id: root
    property var chosen: []
    property int opened: 0
    property int invoked: 0
    property int closedCount: 0

    function fakeNotification(withDefault) {
        return {
            appName: "Mail", summary: "New message", body: "From Alex", urgency: 1, image: "", appIcon: "",
            actions: withDefault ? [{ identifier: "default", text: "", invoke: () => root.invoked += 1 }] : [],
            dismiss: () => {}
        }
    }

    property Item box: Item {
        width: 400; height: 1200
        CalendarMonth {
            id: month
            width: 400
            today: new Date(2026, 9, 15)
            selectable: true
            onDaySelected: day => root.chosen = root.chosen.concat([day.getMonth() + "/" + day.getDate()])
        }
        MediaCard { id: media; y: 400; width: 400; shape: "large"; onClicked: root.opened += 1 }
        NotificationCard { id: acting; y: 700; width: 400; notification: root.fakeNotification(true); onClosed: root.closedCount += 1 }
        NotificationCard { id: plain; y: 900; width: 400; notification: root.fakeNotification(false) }
    }

    // The stops a control adds that are not ShellButtons, which have a
    // `toolTip` and are counted on their own.
    function ownStops(item) { return Nav.focusables(item).filter(stop => stop.toolTip === undefined) }
    // The day cells by walking the tree rather than through NavLogic: choosing
    // a day rebuilds the grid, and without a window the new cells are never
    // laid out, so NavLogic, which skips what has no size, would not see them.
    function days() {
        const found = []
        function walk(item) {
            if (item.modelData !== undefined && item.focusOnTab !== undefined) found.push(item)
            for (const child of item.children) walk(child)
        }
        walk(month)
        return found
    }
    function day(monthIndex, date) {
        return days().find(cell => cell.modelData.date.getMonth() === monthIndex && cell.modelData.date.getDate() === date)
    }

    Component.onCompleted: {
        // ---- the month ----------------------------------------------------
        const stops = ownStops(month)
        T.eq(stops.filter(stop => stop.modelData !== undefined).length, 42, "every day of the grid is a stop where a day can be chosen")
        const title = stops.filter(stop => stop.modelData === undefined)
        T.eq(title.length, 1, "and so is the month's title, the way back to today")

        day(9, 20).Keys.returnPressed(null)
        T.eq(root.chosen, ["9/20"], "Return chooses the day")
        T.eq(month.selectedDate.getDate(), 20, "and selects it")
        day(10, 2).Keys.spacePressed(null)
        T.eq([root.chosen[1], month.month], ["10/2", 10], "Space on a day of the next month goes to that month")

        title[0].Keys.returnPressed(null)
        T.eq([month.month, month.selectedDate.getDate(), root.chosen[2]], [9, 15, "9/15"], "Return on the title goes back to today")

        month.selectable = false
        T.eq([days().every(cell => cell.available === false && !cell.activeFocusOnTab), title[0].available],
             [true, false], "a month that chooses nothing has only its arrows")

        // ---- the media card -----------------------------------------------
        const before = ownStops(media).length
        media.clickOpens = true
        const added = ownStops(media).filter(stop => stop.available !== undefined)
        T.eq([added.length, ownStops(media).length - before], [1, 1], "a card that opens something is one stop more, beside its buttons")
        added[0].Keys.returnPressed(null)
        T.eq(root.opened, 1, "and Return opens it")

        // ---- notifications -----------------------------------------------
        const picture = ownStops(acting)
        T.eq(picture.length, 1, "a notification with a default action is a stop")
        picture[0].Keys.returnPressed(null)
        T.eq([root.invoked, root.closedCount], [1, 1], "Return invokes the default action and closes the card")
        T.eq(ownStops(plain).length, 0, "one without a default action is not")
        const dismiss = Nav.focusables(plain).filter(stop => stop.toolTip === "Dismiss")
        T.eq(dismiss.map(button => button.height), [Metrics.controlHeightSm],
             "its close is the compact size the notification centre's buttons have")

        T.finish("KeyReachTest")
    }
}
