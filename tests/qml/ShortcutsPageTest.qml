import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/shortcuts/ShortcutLogic.js" as S

// Settings > Shortcuts' list of every bind as the search narrows it. The real
// page, in a window that is never shown (PageActivity starts no read of the
// binds), over the nested session's `hyprctl -j binds`. A letter typed only
// takes rows away: the rows still shown are the same objects as before, and
// a fresh read of the same binds (every open of the page) builds none again.
ShellRoot {
    id: root
    FileView { id: legacy; path: Qt.resolvedUrl("../fixtures/hypr-binds-legacy.json").toString().replace("file://", ""); blockLoading: true }

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 1400
        visible: false
        Loader { id: loader; width: 860; active: false; sourceComponent: ShortcutsPage {} }
    }

    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }
    function rows() { return walk(loader.item, item => item.entry !== undefined && item.defaultCombo !== undefined, []) }
    function byTitle(list) {
        const table = {}
        for (const row of list) table[row.entry.group + " " + row.entry.combo + " " + row.entry.title] = row
        return table
    }

    // The service reads its store at the start and then the binds, which in
    // the sandbox answer nothing; the fixture goes in once that read is over,
    // or it would be replaced by it.
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (!ShortcutService.storeLoaded || ShortcutService.loading) return
            stop()
            ShortcutService.binds = S.parseBinds(legacy.text())
            loader.active = true
            check.start()
        }
    }
    Timer {
        id: check; interval: 100
        onTriggered: {
            const all = root.rows()
            const expected = [].concat(...S.grouped(ShortcutService.rows, "").map(group => group.rows))
            T.eq(all.length, expected.length, "a row for every condensed bind")
            const before = root.byTitle(all)

            loader.item.query = "screen"
            const narrowed = root.rows()
            T.ok(narrowed.length > 0 && narrowed.length < all.length, "a letter narrows the list")
            T.ok(narrowed.every(row => before[row.entry.group + " " + row.entry.combo + " " + row.entry.title] === row),
                 "every row still shown is the row it was")

            loader.item.query = "screenshot of the screen"
            const one = root.rows()
            T.eq(one.map(row => row.entry.combo), ["Super+Shift+S"], "a whole title leaves its row")
            T.ok(one[0] === before["screenshots Super+Shift+S Screenshot of the screen"], "and it is still the same one")

            loader.item.query = ""
            const back = root.rows()
            T.eq(back.length, all.length, "an empty search brings every row back")
            const again = root.byTitle(back)
            ShortcutService.binds = S.parseBinds(legacy.text())
            const reread = root.rows()
            T.ok(reread.length === back.length && reread.every(row => again[row.entry.group + " " + row.entry.combo + " " + row.entry.title] === row),
                 "a fresh read of the same binds builds no row again")

            T.finish("ShortcutsPageTest")
        }
    }
}
