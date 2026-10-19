import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/display/DisplayLogic.js" as D

// Settings pages whose lists come anew from a service keep their rows - and
// the row the keyboard is on - when the list changes: a Repeater over the
// list itself built every row again, and the focus went with the row.
// Loaded for real, offscreen, one after the other: Displays (a key step on
// Scale), Default apps (a new list after a read), Bar & notch (a pill moved
// along its zone and into the next one).
ShellRoot {
    id: root
    readonly property var sample: [
        { name: "eDP-1", description: "", make: "Sample", model: "Panel", width: 1920, height: 1200, refreshRate: 60, x: 0, y: 0, scale: 1,
          transform: 0, vrr: false, disabled: false, focused: true, availableModes: ["1920x1200@60.00Hz", "1920x1080@60.00Hz"] },
        { name: "DP-1", description: "", make: "Sample", model: "27", width: 2560, height: 1440, refreshRate: 60, x: 1920, y: 0, scale: 1,
          transform: 0, vrr: false, disabled: false, focused: false, availableModes: ["2560x1440@60.00Hz"] }
    ]
    function category(id, label, current, source) {
        return { id: id, label: label, current: current, source: source, session: source === "session",
                 candidates: [{ id: "a.desktop", name: "App A" }, { id: "b.desktop", name: "App B" }] }
    }

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 1600
        visible: true
        Component { id: displaysPage; DisplaysPage {} }
        Component { id: defaultAppsPage; DefaultAppsPage {} }
        Component { id: barPage; BarPage {} }
        Loader { id: loader; width: 860; active: false }
    }

    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }
    function find(pred) { return walk(loader.item, pred, [])[0] || null }
    function load(component) {
        loader.active = false
        loader.sourceComponent = component
        loader.active = true
    }

    // Displays: Right on the chosen monitor's Scale control changes the
    // draft and leaves the section, the control and its focus where they are.
    function displaysSection() {
        return find(item => typeof item.title === "string" && item.title.indexOf("Display 1") === 0 && item.visible)
    }
    function scaleControl(section) {
        return walk(section, item => Array.isArray(item.options) && item.options.length && typeof item.step === "function"
                    && String(item.options[0].label).indexOf("%") > 0, [])[0] || null
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            const parsed = D.parseMonitors(JSON.stringify(root.sample))
            DisplayService.monitors = parsed
            DisplayService.draft = parsed.slice()
            root.load(displaysPage)
            displaysStep.start()
        }
    }
    Timer {
        id: displaysStep; interval: 200
        onTriggered: {
            const section = root.displaysSection()
            const scale = root.scaleControl(section)
            T.ok(section !== null && scale !== null, "the chosen display's section and its Scale control")
            if (!scale) { root.done(); return }
            scale.forceActiveFocus()
            T.ok(scale.activeFocus, "the keyboard is on Scale")
            scale.Keys.rightPressed(null)
            T.eq(DisplayService.draft.find(monitor => monitor.name === "eDP-1").scale, 1.25, "Right took the next scale into the draft")
            T.ok(root.displaysSection() === section, "the section is the same one")
            T.ok(root.scaleControl(section) === scale && scale.activeFocus, "and Scale still has the keyboard")
            scale.Keys.rightPressed(null)
            T.eq(DisplayService.draft.find(monitor => monitor.name === "eDP-1").scale, 1.5, "so the next press goes on from there")
            DisplayService.draft = DisplayService.monitors.slice()
            root.load(defaultAppsPage)
            defaultAppsWait.start()
        }
    }

    // Default apps: the page reads its own list as it opens; once that is in,
    // a list of new objects with one row changed keeps every row.
    property int waits: 0
    Timer {
        id: defaultAppsWait; interval: 50; repeat: true
        onTriggered: {
            root.waits += 1
            if (DefaultAppsService.loading && root.waits < 100) return
            stop()
            DefaultAppsService.categories = [root.category("browser", "Web browser", "a.desktop", "system"),
                                              root.category("files", "File manager", "a.desktop", "system")]
            const rows = root.walk(loader.item, item => item.category !== undefined && item.modelData !== undefined, [])
            T.eq(rows.map(row => row.modelData), ["browser", "files"], "a row per category, keyed by its id")
            const select = rows.length ? root.walk(rows[1], item => item.objectName !== "shellTextField" && item.options !== undefined
                                                   && item.placeholder !== undefined, [])[0] : null
            if (select) select.focusInput()
            const focused = item => root.walk(item, inner => inner.activeFocus === true, []).length > 0
            T.ok(select !== null && focused(select), "the keyboard is on the second row's select")
            DefaultAppsService.categories = [root.category("browser", "Web browser", "a.desktop", "system"),
                                              root.category("files", "File manager", "b.desktop", "session")]
            const after = root.walk(loader.item, item => item.category !== undefined && item.modelData !== undefined, [])
            T.ok(after.length === 2 && after[0] === rows[0] && after[1] === rows[1], "a new list keeps the rows")
            T.eq([after[1].category.current, after[1].category.source], ["b.desktop", "session"], "and the changed row reads its new values")
            T.ok(select !== null && after.length === 2 && root.walk(after[1], item => item === select, []).length === 1 && focused(select),
                 "the select stays in its row and keeps the keyboard")
            root.load(barPage)
            barWait.start()
        }
    }

    // Bar & notch: a pill moved by its own button keeps its card and the
    // keyboard; moved into the next zone, the focus follows it there.
    Timer {
        id: barWait; interval: 50; repeat: true
        onTriggered: {
            root.waits += 1
            const settled = LayoutService.loaded && LayoutService.stateSettled && !LayoutService.builtinApplying.length
            if (!settled && root.waits < 400) return
            stop()
            LayoutService.setDesktopMode("pills")
            LayoutService.resetBar()
            // The shipped bar has one pill on the left: a second one to move past.
            LayoutService.barAddPill("left", "clock", "")
            barStep.start()
        }
    }
    // A pill's card by the pill it shows, which every card has, keyed or not.
    function pillCards() {
        return walk(loader.item, item => item.pill !== undefined && item.pill !== null && typeof item.pill.id === "string"
                    && item.selected !== undefined, [])
    }
    function button(card, tip) {
        return walk(card, item => item.toolTip === tip && typeof item.activate === "function", [])[0] || null
    }
    Timer {
        id: barStep; interval: 200
        onTriggered: {
            const zone = LayoutService.zones.find(name => (LayoutService.bar[name] || []).length >= 2)
            T.ok(zone !== undefined, "a zone of the default bar holds two pills or more")
            if (zone === undefined) { root.done(); return }
            const id = LayoutService.bar[zone][0].id
            const card = root.pillCards().find(item => item.pill.id === id)
            const right = card ? root.button(card, "Move right") : null
            T.ok(right !== null, "the first pill's card and its Move right")
            if (!right) { root.done(); return }
            right.forceActiveFocus()
            right.activate()
            T.eq(LayoutService.bar[zone][1].id, id, "Move right moved the pill along its zone")
            T.ok(root.pillCards().indexOf(card) >= 0 && right.activeFocus, "its card and the button stay, the keyboard on it")
            barCross.zone = zone
            barCross.id = id
            barCross.start()
        }
    }
    Timer {
        id: barCross; interval: 100
        property string zone
        property string id
        onTriggered: {
            const zones = LayoutService.zones
            if (zones.indexOf(zone) === zones.length - 1) { root.done(); return }
            const card = root.pillCards().find(item => item.pill.id === id)
            const right = card ? root.button(card, "Move right") : null
            T.ok(right !== null, "the pill's card and its Move right, further along the zone")
            if (!right) { root.done(); return }
            right.forceActiveFocus()
            const steps = LayoutService.bar[zone].length - 1 - LayoutService.bar[zone].findIndex(pill => pill.id === id)
            for (let i = 0; i < steps; ++i) right.activate()
            right.activate()
            const next = zones[zones.indexOf(zone) + 1]
            T.eq(LayoutService.bar[next][0].id, id, "past the end of its zone it goes to the next one")
            barFocus.id = id
            barFocus.start()
        }
    }
    Timer {
        id: barFocus; interval: 100
        property string id
        onTriggered: {
            const card = root.pillCards().find(item => item.pill.id === id)
            const focused = (card ? root.walk(card, item => item.activeFocus === true && typeof item.activate === "function", [])[0] : null) || null
            T.ok(focused !== null && (focused.toolTip === "Move right" || focused.toolTip === "Move left"),
                 "and the keyboard follows it onto its new card")
            root.done()
        }
    }

    function done() {
        loader.active = false
        T.finish("SettingsKeyedTest")
    }
}
