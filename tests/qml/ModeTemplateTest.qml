import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// The five mode templates (config/profiles/<mode>.json): what Default's modes
// and every new profile's start from. Each names its surface (`desktopMode`,
// the word a mode in the layout file uses) - they had all been widgets with
// the default bar, and minimal's one clock vanished under the first window.
ShellRoot {
    id: root
    function read(name) {
        const view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', root)
        view.path = Qt.resolvedUrl("../../config/profiles/" + name + ".json").toString().replace("file://", "")
        const data = JSON.parse(view.text())
        view.destroy()
        return data
    }
    function itemCount(bar) {
        return ["left", "center", "right"].reduce((sum, zone) => sum + bar[zone].reduce((n, pill) => n + pill.items.length, 0), 0)
    }

    Component.onCompleted: {
        const names = ["minimal", "work", "gaming", "laptop", "docked"]
        const t = {}
        for (const name of names) t[name] = root.read(name)

        T.eq(names.map(name => t[name].name), names, "each file names its mode")
        T.eq(names.map(name => t[name].desktopMode), ["notch", "pills", "notch", "pills", "pills"],
             "minimal and gaming the notch; work, laptop and docked a bar")
        T.eq(names.filter(name => t[name].mode !== undefined), [],
             "under the layout file's word for it: a mode's `mode` was the old name of its desktop mode")
        T.eq(names.map(name => t[name].configVersion), [3, 3, 3, 3, 3], "the vocabulary of layout.json v3")
        T.eq(names.map(name => L.freshMode(t[name]).desktopMode), ["notch", "pills", "notch", "pills", "pills"],
             "and a mode made from one takes it")
        T.eq([t.minimal.bar, t.minimal.effects], [undefined, undefined], "minimal brings no bar and no effects: the notch and a clock")

        // Every bar survives the sanitizer whole: no pill or item dropped.
        for (const name of ["work", "gaming", "laptop", "docked"]) {
            const clean = L.sanitizeBar(t[name].bar)
            T.eq(root.itemCount(clean), root.itemCount(t[name].bar), name + "'s bar keeps every item")
            T.eq(L.barPillIds(clean).length, new Set(L.barPillIds(clean)).size, name + "'s pill ids are unique")
        }
        T.eq([t.work.bar.style, t.laptop.bar.style, t.laptop.bar.position, L.sanitizeBar(t.laptop.bar).scale],
             ["pills", "bar", "attached", 0.9], "laptop's bar is the slim attached one")
        T.eq(t.work.bar.right.map(pill => pill.items.map(item => item.type)),
             [["nowPlaying"], ["network", "volume", "battery"], ["notificationIndicator", "quickPanel"]],
             "work's right side: media, status, notifications and the control center")
        // One order for the status readouts on every bar, the taskbar's: the
        // battery at the outer end, where its percent is.
        for (const name of ["work", "laptop", "docked"]) {
            const status = t[name].bar.right.map(pill => pill.items.map(item => item.type))
                .find(types => types.indexOf("battery") >= 0)
            T.eq(status, ["network", "volume", "battery"], name + "'s status: network, volume, battery")
        }
        T.eq(t.laptop.bar.right[t.laptop.bar.right.length - 1].items.map(item => item.type),
             ["notificationIndicator", "quickPanel"], "laptop's bar shows unread notifications beside the control center")

        T.eq(t.gaming.effects, { dnd: "manual", animationMode: "reduced", blurStrength: 0 }, "gaming: quiet, reduced motion, no blur")
        T.eq(t.laptop.effects, { gapsIn: 4, gapsOut: 8 }, "laptop: tighter gaps")

        T.eq(t.docked.label, "Desk", "docked is called Desk: \"Docked\" read as the dock")
        T.eq(t.docked.bar.center[0].items.map(item => item.type), ["clock", "date"], "docked: the date beside the time")
        T.eq(t.docked.bar.right[0].items[0].type, "weather", "and the weather")
        // Docked's widgets (Super+Alt+D) build on a screen: a status group and the rest.
        const built = L.materialize(t.docked, "DP-1", [], () => true)
        T.eq(built.widgets.map(widget => widget.type),
             ["workspace", "activeWindow", "network", "volume", "battery", "notificationIndicator", "quickPanel", "clock"],
             "docked's widgets on a screen")
        T.eq(built.groups.length, 1, "with one status group")
        T.eq(built.widgets.filter(widget => widget.group === built.groups[0].id).length, 5, "of five members")

        T.finish("ModeTemplateTest")
    }
}
