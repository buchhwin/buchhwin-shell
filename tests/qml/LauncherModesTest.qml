import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"

// Settings > Launcher > Modes: Later moves a mode one on, and the row - with
// the keyboard on its button - moves with it. The rows were built anew on
// every step and the focus went with them (the pins below kept theirs).
// Each step waits for what it needs (T.waitUntil), not a fixed time: after
// 200 + 300 + 100 ms it failed once while a build ran beside it.
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
    function order() { return LauncherService.modes.map(mode => mode.id) }
    // The second mode's row and its Later button, once the page has both.
    function second() {
        const id = order()[1]
        const row = rows().find(row => row.modeId === id)
        const later = row ? walk(row, item => item.toolTip === "Later in the switch", [])[0] : null
        return later && later.enabledState ? { id: id, row: row, later: later } : null
    }
    Component.onCompleted: T.waitUntil(root, () => SettingsService.loaded, 3000, () => {
        loader.active = true
        T.waitUntil(root, () => root.second() !== null, 3000, () => {
            const found = root.second()
            T.ok(found !== null, "the second mode's Later")
            if (!found) { T.finish("LauncherModesTest"); return }
            found.later.forceActiveFocus()
            found.later.activate()
            T.waitUntil(root, () => root.order()[2] === found.id, 3000, () => {
                T.eq(root.order()[2], found.id, "Later moved it one on")
                T.ok(root.rows().indexOf(found.row) >= 0, "its row is the same one")
                const focused = root.walk(found.row, item => item.activeFocus === true, [])
                T.ok(focused.length === 1 && /in the switch$/.test(focused[0].toolTip || ""), "and keeps the keyboard")
                SettingsService.set("launcher.modeOrder", "")
                T.finish("LauncherModesTest")
            })
        })
    })
}
