pragma Singleton
import Quickshell
import QtQuick
import "hypr/ScreenEffectsLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// The screen zoom (Super and + / - / 0) and the color filters (Super+Ctrl+C,
// Settings > Appearance): two compositor options set at run time, Hyprland's
// cursor:zoom_factor and decoration:screen_shader, through HyprCompat in the
// dialect of the session. The zoom is not stored, as a magnifier's is not: a
// shell starts at 100 % (a compositor still zoomed from before a restart
// comes back with Super+0 or a step out); the filter is a setting of the
// machine (display.colorFilter, display.colorFilterOn) and comes back at
// login.
//
// Nothing here runs until it is used: shell.qml only makes this service at
// the start when a filter is on, and the compositor renders scaled or
// through the shader only while one of them is.
Singleton {
    id: root

    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell)
    // Read by shell.qml at the start: `filterOn` alone brings the service up
    // when there is a filter to put back.
    readonly property bool ready: true

    property real zoom: 1
    readonly property bool zoomed: Logic.zoomActive(zoom)
    readonly property string zoomLabel: Logic.zoomLabel(zoom)

    readonly property string filter: Logic.normalizeFilter(SettingsService.value("display.colorFilter"))
    readonly property bool filterOn: SettingsService.value("display.colorFilterOn") === true
    readonly property string filterLabel: Logic.filterLabel(filter)
    readonly property var filters: Logic.filterOptionsList()

    // ---- Zoom ---------------------------------------------------------------
    // One step in (`direction` > 0) or out, and the factor it lands on.
    function zoomBy(direction) {
        setZoom(Logic.zoomStep(zoom, direction))
        return zoom
    }
    function setZoom(factor) {
        const next = Logic.clampZoom(factor)
        if (!Logic.zoomNeedsSend(zoom, next)) return
        zoom = next
        sendZoom()
    }
    function resetZoom() { setZoom(1) }
    function sendZoom() {
        if (!lockProcess) HyprCompat.setOptions(Logic.zoomOptions(zoom))
    }

    // ---- Color filters ------------------------------------------------------
    function toggleFilter() { SettingsService.set("display.colorFilterOn", !filterOn) }
    function setFilterOn(on) { SettingsService.set("display.colorFilterOn", on === true) }
    // A filter chosen is a filter on: picking one in a list and seeing
    // nothing change was the other way to read it.
    function setFilter(id) {
        if (!Logic.knownFilter(id)) return false
        SettingsService.setAll({ "display.colorFilter": String(id), "display.colorFilterOn": true })
        return true
    }
    // The next filter, or the chosen one when none is on.
    function cycleFilter() {
        if (!filterOn) setFilterOn(true)
        else setFilter(Logic.nextFilter(filter))
    }
    function sendFilter() {
        if (!lockProcess) HyprCompat.setOptions(Logic.filterOptions(filterOn, filter, Paths.shellFile("shaders")))
    }
    // Sent when it changes, from wherever it changes (Settings, IPC, a key, a
    // profile switch does not touch it: it is the machine's). At the start
    // only when there is one to put back; off is what the compositor starts
    // with.
    property bool sentFilter: false
    onFilterOnChanged: { sentFilter = true; sendFilter() }
    onFilterChanged: if (filterOn) sendFilter()
    Component.onCompleted: if (filterOn && !sentFilter) { sentFilter = true; sendFilter() }

    // A config reload (a save in Settings > Shortcuts, an edit under hypr/)
    // puts every option back to the files' values: no shader, no zoom. Both
    // are sent again, so what the shell says is on is on.
    Connections {
        target: HyprlandService
        function onConfigReloaded() {
            if (root.filterOn) root.sendFilter()
            if (root.zoomed) root.sendZoom()
        }
    }
}
