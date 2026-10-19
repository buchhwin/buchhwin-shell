import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"

// Settings > Launcher > Modes: Later moves a mode one on, and the row - with
// the keyboard on its button - moves with it. The rows were built anew on
// every step and the focus went with them (the pins below kept theirs).
ShellRoot {
    id: root
    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 1600
        visible: true
        Loader { id: loader; width: 860; active: false; sourceComponent: LauncherPage {} }
    }
    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        for (const kid of (item.children || [])) walk(kid, pred, out)
        return out
    }
    function rows() { return walk(loader.item, item => item.modeId !== undefined && typeof item.focusStep === "function", []) }
    Timer { interval: 200; running: true; onTriggered: { loader.active = true; step.start() } }
    Timer {
        id: step; interval: 300
        onTriggered: {
            const ids = LauncherService.modes.map(mode => mode.id)
            const second = root.rows().find(row => row.modeId === ids[1])
            const later = second ? root.walk(second, item => item.toolTip === "Later in the switch", [])[0] : null
            T.ok(later !== null && later.enabledState, "the second mode's Later")
            if (!later) { T.finish("LauncherModesTest"); return }
            later.forceActiveFocus()
            later.activate()
            check.row = second
            check.id = ids[1]
            check.start()
        }
    }
    Timer {
        id: check; interval: 100
        property var row
        property string id
        onTriggered: {
            T.eq(LauncherService.modes.map(mode => mode.id)[2], id, "Later moved it one on")
            T.ok(root.rows().indexOf(row) >= 0, "its row is the same one")
            const focused = root.walk(row, item => item.activeFocus === true, [])
            T.ok(focused.length === 1 && /in the switch$/.test(focused[0].toolTip || ""), "and keeps the keyboard")
            SettingsService.set("launcher.modeOrder", "")
            T.finish("LauncherModesTest")
        }
    }
}
