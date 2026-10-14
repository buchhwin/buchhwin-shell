pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "input/InputLogic.js" as Logic

// Keyboard layout, key repeat, pointer speed and touchpad behaviour from
// Settings > Input, applied to Hyprland at startup, on every change and
// after config reloads.
Singleton {
    id: root

    property var layouts: []
    property var variants: ({})
    readonly property var current: Logic.values(path => SettingsService.value(path))

    function variantsFor(layout) {
        loadLayouts()
        return [{ value: "", label: "Default" }].concat(variants[layout] || [])
    }

    // The layout list is read on first use, not at start: evdev.lst is a
    // thousand lines sorted with localeCompare, and only Settings > Input
    // shows it. Settings opening asks for it, so it is there by the time the
    // Input page is; the page asks too (`variantsFor`), for an open that goes
    // straight to it. Switching `preload` on is what reads a FileView that
    // never read (pitfall 34), and it is switched a turn later because the
    // page asks from a binding, which must not write what it has just read.
    function loadLayouts() {
        if (layoutFile.preload) return
        Qt.callLater(() => { layoutFile.preload = true })
    }
    Connections {
        target: PanelService
        function onActiveChanged() { if (PanelService.active === "settings") root.loadLayouts() }
    }

    property string applied: ""

    // Any settings change rebuilds `current`; only send Hyprland real changes.
    function apply() {
        if (!SettingsService.loaded) return
        const options = Logic.optionMap(current)
        const key = JSON.stringify(options)
        if (key === applied) return
        applied = key
        HyprCompat.setOptions(options)
    }

    onCurrentChanged: applyTimer.restart()
    Connections {
        target: HyprlandService
        function onConfigReloaded() {
            root.applied = ""
            applyTimer.restart()
        }
    }
    Timer { id: applyTimer; interval: 150; onTriggered: root.apply() }

    // VS Code multiplies the compositor's scroll steps again; scripts/
    // app-scroll.py can set its own sensitivity to the inverse factor. Real
    // session only, and it keeps a backup of the file it changes.
    readonly property bool realSession: AppearanceService.realSession
    property var appScroll: null
    property string appScrollError: ""
    readonly property bool appScrollBusy: appScrollProc.running
    readonly property bool appScrollMatched: appScroll && appScroll.current !== null
        && Math.abs(Number(appScroll.current) - Number(appScroll.wanted)) < 0.005

    property string appScrollAction: ""
    function appScrollRun(action) {
        if (appScrollProc.running) return
        appScrollAction = action
        appScrollProc.command = ["python3", Paths.script("app-scroll.py"), action,
                                 "--factor", String(current["touchpad:scroll_factor"])]
            .concat(root.realSession ? [] : ["--dry-run"])
        appScrollProc.running = true
    }
    function refreshAppScroll() { appScrollRun("status") }

    Process {
        id: appScrollProc
        stderr: ErrorLog { label: "InputService.appScrollProc" }
        // After a change the helper reports the values from before it; read
        // them again so the row shows the new state.
        onExited: if (root.appScrollAction !== "status") root.refreshAppScroll()
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.appScroll = JSON.parse(text)
                    root.appScrollError = root.appScroll.problem === "unreadable"
                        ? "The VS Code settings file could not be read."
                        : root.appScroll.problem === "missing" ? "VS Code has no settings file yet." : ""
                } catch (error) {
                    root.appScroll = null
                    root.appScrollError = "The helper did not answer."
                }
            }
        }
    }

    FileView {
        id: layoutFile
        path: "/usr/share/X11/xkb/rules/evdev.lst"
        preload: false
        printErrors: false
        onLoaded: {
            const parsed = Logic.parseXkbList(text())
            root.layouts = parsed.layouts
            root.variants = parsed.variants
        }
    }
}
