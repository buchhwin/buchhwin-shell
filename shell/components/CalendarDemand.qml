import QtQuick
import qs.services

// Says that something on screen needs the calendar while `active`: the
// backend (Akonadi) starts on the first such need and stops a while after
// the last one (CalendarService.trackers). The clock widget's event hint is
// one of them (ClockWidget's own demand).
QtObject {
    id: demand
    property bool active: true
    property bool counted: false
    function sync() {
        if (active && !counted) { CalendarService.track(); counted = true }
        else if (!active && counted) { CalendarService.untrack(); counted = false }
    }
    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (counted) CalendarService.untrack()
}
