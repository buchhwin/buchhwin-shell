import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L

// The five mode templates (config/profiles/<mode>.json): what Default's modes
// and every new profile's start from. Round 13 gave the four besides minimal
// a surface each - they had all been widgets with the default bar.
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
        T.eq(names.map(name => t[name].mode), [undefined, "pills", "notch", "pills", "pills"],
             "minimal leaves the surface alone; work, laptop and docked a bar, gaming the notch")
        T.eq([t.minimal.bar, t.minimal.effects], [undefined, undefined], "minimal is as it was: just the clock")

        // Every bar survives the sanitizer whole: no pill or item dropped.
        for (const name of ["work", "gaming", "laptop", "docked"]) {
            const clean = L.sanitizeBar(t[name].bar)
            T.eq(root.itemCount(clean), root.itemCount(t[name].bar), name + "'s bar keeps every item")
            T.eq(L.barPillIds(clean).length, new Set(L.barPillIds(clean)).size, name + "'s pill ids are unique")
        }
        T.eq([t.work.bar.style, t.laptop.bar.style, t.laptop.bar.position, L.sanitizeBar(t.laptop.bar).scale],
             ["pills", "bar", "attached", 0.9], "laptop's bar is the slim attached one")
        T.eq(t.work.bar.right.map(pill => pill.items.map(item => item.type)),
             [["nowPlaying"], ["volume", "network", "battery"], ["notificationIndicator", "quickPanel"]],
             "work's right side: media, status, notifications and the control center")

        T.eq(t.gaming.effects, { dnd: "manual", animationMode: "reduced", blurStrength: 0 }, "gaming: quiet, reduced motion, no blur")
        T.eq(t.laptop.effects, { gapsIn: 4, gapsOut: 8 }, "laptop: tighter gaps")

        T.eq(t.docked.bar.center[0].items.map(item => item.type), ["clock", "date"], "docked: the date beside the time")
        T.eq(t.docked.bar.right[0].items[0].type, "weather", "and the weather")
        // Docked's widgets (Super+Alt+D) build on a screen: a status group and the rest.
        const built = L.materialize(t.docked, "DP-1", [], () => true)
        T.eq(built.widgets.map(widget => widget.type),
             ["workspace", "activeWindow", "volume", "network", "battery", "notificationIndicator", "quickPanel", "clock"],
             "docked's widgets on a screen")
        T.eq(built.groups.length, 1, "with one status group")
        T.eq(built.widgets.filter(widget => widget.group === built.groups[0].id).length, 5, "of five members")

        T.finish("ModeTemplateTest")
    }
}
