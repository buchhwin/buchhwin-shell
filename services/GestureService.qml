pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "input/GestureLogic.js" as Logic

// Touchpad gestures from Settings > Input. They are runtime Hyprland gestures
// (HyprCompat gestures: the Hyprland config files define none), applied at
// startup, on every settings change and after config reloads, which drop them.
// Swipes that open shell panels call `gestures run NAME` over IPC.
Singleton {
    id: root

    readonly property var slots: Logic.slots
    readonly property var actions: Logic.actions
    readonly property var horizontalActions: Logic.horizontalActions
    readonly property var plan: Logic.plan(path => SettingsService.value(path), Quickshell.shellPath(""))
    readonly property var rows: Logic.rows(path => SettingsService.value(path))

    property bool hasTouchpad: false
    // Shows the settings section without a touchpad (nested test sessions).
    property bool preview: false
    readonly property bool touchpadShown: hasTouchpad || preview

    property string applied: ""

    function apply() {
        if (!SettingsService.loaded) return
        const key = JSON.stringify(plan)
        if (key === applied) return
        let command = null
        try {
            command = HyprCompat.commands.combine([HyprCompat.commands.options(plan.options),
                                                   HyprCompat.commands.gestures(plan.gestures, plan.slots)])
        } catch (error) {
            console.warn("buchhwin-shell: gestures rejected:", error)
            return
        }
        applied = key
        HyprCompat.configure(command)
    }

    // A panel action from a swipe; false for unknown names.
    function run(name) {
        const action = Logic.shellAction(name)
        if (!action) return false
        if (action.closePanel) PanelService.close()
        else PanelService.toggle(action.panel)
        return true
    }

    function refreshDevices() {
        if (!devicesProc.running) devicesProc.running = true
    }

    // IPC `gestures get`: settings plan and touchpad state, no private data.
    function describe() {
        return JSON.stringify({ touchpad: hasTouchpad, preview: preview, enabled: plan.enabled, gestures: plan.gestures, options: plan.options })
    }

    onPlanChanged: applyTimer.restart()
    Component.onCompleted: refreshDevices()

    Connections {
        target: SettingsService
        function onLoadedChanged() { applyTimer.restart() }
    }
    // A reload applies the config files first; the gestures follow.
    Connections {
        target: HyprlandService
        function onConfigReloaded() {
            root.applied = ""
            reloadDelay.restart()
        }
    }
    Timer { id: applyTimer; interval: 150; onTriggered: root.apply() }
    Timer { id: reloadDelay; interval: 400; onTriggered: root.apply() }

    Process {
        id: devicesProc
        stderr: ErrorLog { label: "GestureService.devicesProc" }
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: root.hasTouchpad = Logic.hasTouchpad(text)
        }
    }
}
