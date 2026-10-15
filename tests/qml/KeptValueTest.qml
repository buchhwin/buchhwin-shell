import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/CalendarLogic.js" as Calendar
import "../../services/terminal/TerminalLogic.js" as Terminal

// What CalendarService.hiddenIds and TerminalService.options rely on: a `var`
// binding that hands back the very object it returned before is not announced
// as a change, so its dependants do not run again. Both are re-read on every
// settings write, whatever its key; an equal result keeps the previous object
// (held outside the binding's dependencies), a different one replaces it. The
// services themselves are not made here: they pull in AppearanceService,
// which talks to the compositor the test runs under.
ShellRoot {
    id: root
    // A stand-in for SettingsService.data: replaced whole on every write.
    property var data: ({ hidden: "3,1", terminal: {} })
    function value(path) {
        if (path === "calendar.hiddenCalendars") return data.hidden
        const key = path.slice("terminal.".length)
        return key in data.terminal ? data.terminal[key] : 1
    }

    property var lastHiddenIds: ({ list: [] })
    readonly property var hiddenIds: {
        const next = Calendar.parseIdList(root.value("calendar.hiddenCalendars"))
        if (JSON.stringify(next) === JSON.stringify(lastHiddenIds.list)) return lastHiddenIds.list
        lastHiddenIds.list = next
        return next
    }
    property var lastOptions: ({ value: null })
    readonly property var options: {
        const next = Terminal.options(path => root.value(path))
        if (JSON.stringify(next) === JSON.stringify(lastOptions.value)) return lastOptions.value
        lastOptions.value = next
        return next
    }
    property int hiddenChanges: 0
    property int optionChanges: 0
    onHiddenIdsChanged: hiddenChanges += 1
    onOptionsChanged: optionChanges += 1

    function write(change) { data = Object.assign({}, data, change) }

    Component.onCompleted: {
        const hidden = hiddenIds
        const options = root.options
        hiddenChanges = 0
        optionChanges = 0
        write({ unrelated: true })
        T.eq([hiddenChanges, optionChanges], [0, 0], "a write of another key announces neither")
        T.ok(hiddenIds === hidden && root.options === options, "and both are the previous objects")
        write({ hidden: " 3, 1,x" })
        T.eq(hiddenChanges, 0, "the same calendars written differently are no change")
        write({ hidden: "3,1,7" })
        T.eq([hiddenChanges, hiddenIds], [1, [3, 1, 7]], "another calendar hidden is one")
        write({ terminal: { fontSize: 14 } })
        T.eq([optionChanges, root.options.fontSize], [1, 14], "a terminal option changed is one")
        write({ terminal: { fontSize: 14 } })
        T.eq(optionChanges, 1, "and written again with the same value, none")
        T.eq(hiddenChanges, 1, "nor do terminal writes touch the calendars")
        T.finish("KeptValue")
    }
}
