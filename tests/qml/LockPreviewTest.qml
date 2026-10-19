import Quickshell
import QtQuick
import qs.theme
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/appearance/ContrastLogic.js" as C

// Settings > Lock screen's sketch. Its cells lean only while the pointer is
// over it and Settings is on screen: leaning all the time, three Wiggles
// redrew the whole Settings surface on every frame while the page was open
// and ticked on for the minute a closed page is kept. And the remove badge
// wears the lock screen's inks in either theme, on the always-dark tile.
ShellRoot {
    id: root
    property int waits: 0

    FloatingWindow {
        id: win
        implicitWidth: 700
        implicitHeight: 700
        visible: false
        // Away from the window's corner, where an offscreen pointer rests.
        LockPreview { id: preview; x: 20; y: 120; width: 660 }
    }

    function find(under, pred) {
        const found = []
        function walk(item) {
            if (pred(item)) found.push(item)
            for (const child of item.children) walk(child)
        }
        walk(under)
        return found
    }
    function wiggles() { return root.find(preview, item => item.lean !== undefined && item.active !== undefined) }
    function hex(color) { return String(Qt.rgba(color.r, color.g, color.b, 1)) }
    // Each remove badge with the trash glyph it shows (the button's own icon
    // slot included, which is how the theme's danger glyph got there).
    function badges() {
        return root.find(preview, item => item.toolTip === "Take off the lock screen").map(badge => ({
            badge: badge,
            glyphs: root.find(badge, item => item.glyph === Icons.remove && item.visible)
        }))
    }
    function badgesInLockInks() {
        const list = root.badges()
        return list.length > 0 && list.every(entry => Qt.colorEqual(entry.badge.color, Colors.lockField)
            && entry.glyphs.length === 1 && Qt.colorEqual(entry.glyphs[0].color, Colors.lockError))
    }

    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            // The default lock screen's items, once the layout has loaded.
            root.waits += 1
            if (!LayoutService.lockItems.length && root.waits < 60) return
            stop()
            const cells = root.wiggles()
            T.ok(cells.length > 0, "the sketch has cells")
            T.ok(Animations.motionEnabled, "motion is on in the sandbox, so a lean would run")
            T.ok(!preview.leaning && cells.every(cell => !cell.active), "a page that is not shown does not lean")
            win.visible = true
            shown.start()
        }
    }
    Timer {
        id: shown; interval: 100
        onTriggered: {
            T.ok(win.visible, "the window is up")
            T.ok(!preview.leaning && root.wiggles().every(cell => !cell.active), "shown, it leans only under the pointer")

            // The badge's glyph on its fills, both laid over the tile, which
            // is the lock field over the lock screen's base.
            const tile = C.over("#ffffff", Colors.lockField.a, root.hex(Colors.lockBase))
            const rest = C.over("#ffffff", Colors.lockField.a, tile)
            const hover = C.over("#ffffff", Colors.lockButton.a, tile)
            T.ok(C.contrast(root.hex(Colors.lockError), rest) >= C.LARGE_RATIO,
                 "the remove glyph reads on its badge: " + C.contrast(root.hex(Colors.lockError), rest).toFixed(2))
            T.ok(C.contrast(root.hex(Colors.lockError), hover) >= C.LARGE_RATIO,
                 "and under the pointer: " + C.contrast(root.hex(Colors.lockError), hover).toFixed(2))
            // And the badges wear them, in both themes: the danger wash and
            // glyph they had followed the theme onto the always-dark tile.
            for (const theme of ["dark", "light"]) {
                SettingsService.set("appearance.theme", theme)
                T.ok(root.badgesInLockInks(), "the remove badges wear the lock face's inks (" + theme + ")")
            }

            // The offscreen pointer rests at the window's corner, so the
            // sketch goes there to be under it.
            preview.x = 0
            preview.y = 0
            root.waits = 0
            hovered.start()
        }
    }
    Timer {
        id: hovered; interval: 50; repeat: true
        onTriggered: {
            root.waits += 1
            if (!preview.leaning && root.waits < 40) return
            stop()
            T.ok(preview.leaning && root.wiggles().every(cell => cell.active), "under the pointer every cell leans")
            win.visible = false
            closed.start()
        }
    }
    Timer {
        id: closed; interval: 100
        onTriggered: {
            T.ok(!preview.leaning && root.wiggles().every(cell => !cell.active),
                 "Settings closed with the pointer still there, the lean stops")
            T.finish("LockPreviewTest")
        }
    }
}
