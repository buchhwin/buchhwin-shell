//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"

// Settings > Profiles, "Do Not Disturb in this mode": the real page in a
// window that is never shown (PageActivity never runs its openers), over
// LayoutService in the runner's sandbox. The switch reads the mode in use as
// it ships - off in Default's minimal - and toggling it is the mode's own
// choice (LayoutService.setModeDnd; ModeEntryTest has what that does to Do
// Not Disturb). Under the lock screen's shell id: NotificationService runs no
// notification server there (pitfall 82).
ShellRoot {
    id: root
    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 1400
        visible: false
        Loader { id: page; width: 860; active: false; sourceComponent: ProfilesPage {} }
    }
    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }

    property int waits: 0
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            const there = LayoutService.loaded && LayoutService.stateSettled && !LayoutService.builtinApplying.length
                && LayoutService.templates[LayoutService.activeMode] !== undefined
            if (!there && root.waits < 300) return
            stop()
            T.ok(there, "the layout and the mode's template are in")
            page.active = true
            const rows = root.walk(page.item, item => item.label === "Do Not Disturb in this mode", [])
            T.eq(rows.length, 1, "the page has the switch")
            const toggle = rows.length ? root.walk(rows[0], item => item.checked !== undefined && item.toggled !== undefined, [])[0] : null
            T.ok(!!toggle, "with a toggle in it")
            if (toggle) {
                const mode = LayoutService.activeMode
                T.eq([mode, toggle.checked], ["minimal", false], "as the mode ships: Default's minimal leaves Do Not Disturb alone")
                toggle.toggled(true)
                T.eq([LayoutService.modeDnd(mode), toggle.checked], [true, true], "switched on, the mode's choice and the switch")
                T.eq(LayoutService.modeConfig().dnd, true, "kept in the mode")
                toggle.toggled(false)
                T.eq([LayoutService.modeDnd(mode), toggle.checked], [false, false], "and off again")
            }
            T.finish("ProfilesPageTest")
        }
    }
}
