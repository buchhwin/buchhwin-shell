pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "switcher/SwitcherLogic.js" as Logic
import "overview/OverviewLogic.js" as Overview

// Alt+Tab window switcher state. Hyprland calls `next`/`previous` on Alt+Tab
// and `confirm` when Alt is released (hypr/keybinds.conf); the overlay
// (shell/switcher/Switcher.qml) sends the same calls for keys it receives
// itself. Every call is safe to repeat: a confirm without an open switcher
// only remembers the time, because a quick Alt+Tab may deliver the release
// before the press (separate `quickshell ipc` processes).
//
// Minimized windows (services/MinimizeService.qml) are listed after the rest
// (SwitcherLogic.build), and choosing one brings it back to its workspace:
// focused where it is, Hyprland would open its special workspace instead.
Singleton {
    id: root

    property bool active: false
    property bool loading: false
    property var windows: []
    property int selected: -1
    property string activeAddress: ""
    property int direction: 1
    property int extraSteps: 0
    property bool pendingConfirm: false
    property real strayConfirmAt: 0
    readonly property var selectedWindow: selected >= 0 && selected < windows.length ? windows[selected] : null
    // Focus dispatches wait until the overlay released keyboard focus;
    // otherwise Hyprland hands focus back to the previous window.
    property string pendingFocus: ""
    readonly property int strayConfirmWindow: 300
    readonly property int focusDelay: 120

    function next() { step(1) }
    function previous() { step(-1) }

    function step(delta) {
        if (!active) {
            direction = delta
            extraSteps = 0
            selected = -1
            windows = []
            pendingConfirm = Date.now() - strayConfirmAt < strayConfirmWindow
            strayConfirmAt = 0
            active = true
            loading = true
            loadProc.running = true
            PanelService.open("switcher")
            return
        }
        extraSteps += delta
        updateSelection()
    }

    function updateSelection() {
        if (!loading) selected = Logic.selection(windows, activeAddress, direction, extraSteps)
    }

    function select(index) {
        if (!active || loading || index < 0 || index >= windows.length) return
        // Later steps continue from the chosen card.
        extraSteps += index - selected
        selected = index
    }

    function activate(index) {
        select(index)
        confirm()
    }

    function confirm() {
        if (!active) {
            strayConfirmAt = Date.now()
            return
        }
        if (loading) {
            pendingConfirm = true
            return
        }
        const target = selectedWindow
        close()
        if (target && target.minimized === true) {
            MinimizeService.restore(target.address, true, focusDelay)
        } else if (target && target.address !== activeAddress) {
            pendingFocus = target.address
            focusTimer.restart()
        }
    }

    function cancel() {
        if (active) close()
    }

    function close() {
        active = false
        loading = false
        pendingConfirm = false
        PanelService.close("switcher")
    }

    function describe() {
        return JSON.stringify({ active: active, loading: loading, count: windows.length, selected: selected,
                                address: selectedWindow ? selectedWindow.address : "",
                                appClass: selectedWindow ? selectedWindow.appClass : "",
                                minimized: windows.filter(window => window.minimized === true).length,
                                selectedMinimized: selectedWindow ? selectedWindow.minimized === true : false })
    }

    // Another panel replaced the switcher (e.g. a hotkey while Alt is held).
    Connections {
        target: PanelService
        function onActiveChanged() { if (root.active && PanelService.active !== "switcher") root.close() }
    }

    // The shell's answer for the Alt+Tab whose batch was refused, once the
    // refused process has ended (its output can come before its exit).
    Timer {
        id: retry
        interval: 10
        repeat: true
        onTriggered: {
            if (loadProc.running) return
            stop()
            if (root.active && root.loading) loadProc.running = true
        }
    }

    Timer {
        id: focusTimer
        interval: root.focusDelay
        onTriggered: {
            if (root.pendingFocus.length) HyprCompat.dispatch(HyprCompat.commands.focusWindow(root.pendingFocus))
            root.pendingFocus = ""
        }
    }

    // One `hyprctl --batch` for both answers rather than a shell and two
    // hyprctl, at every Alt+Tab (OverviewLogic.parseBatch). A Hyprland whose
    // batch answer is not two JSON documents gets the shell from then on, at
    // once for this Alt+Tab too.
    property bool batchRefused: false
    Process {
        id: loadProc
        stderr: ErrorLog { label: "SwitcherService.loadProc" }
        command: root.batchRefused
            ? ["sh", "-c", "printf '{\"clients\":'; hyprctl -j clients; printf ',\"active\":'; hyprctl -j activewindow; printf '}'"]
            : ["hyprctl", "-j", "--batch", "clients; activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null
                if (root.batchRefused) {
                    try { data = JSON.parse(text) } catch (error) { data = null }
                } else {
                    data = Overview.parseBatch(text, ["clients", "active"])
                    if (!data) {
                        root.batchRefused = true
                        if (root.active) retry.start()
                        return
                    }
                }
                if (!root.active) return
                root.windows = data ? Logic.build(data.clients, HyprlandService.blockOrder, HyprlandService.workspaceMonitors()) : []
                root.activeAddress = data && data.active && data.active.address ? String(data.active.address) : ""
                root.loading = false
                root.updateSelection()
                if (root.pendingConfirm) root.confirm()
            }
        }
    }
}
