import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/dock/DockLogic.js" as D
import "../../services/model/KeyedLogic.js" as Keyed

// The dock's arithmetic (services/dock/DockLogic.js): which app a window
// belongs to, the order of the apps, what a click does, when a window covers
// the dock, when it shows, its geometry and its drag.
ShellRoot {
    function entry(id, name, startupClass, icon) { return { id: id, name: name || id, startupClass: startupClass || "", icon: icon || id } }
    function win(address, cls, seq, extra) {
        return Object.assign({ address: address, appClass: cls, seq: seq, workspace: 1, workspaceName: "1", monitor: "DP-1" }, extra || {})
    }

    Component.onCompleted: {
        // ---- settings ---------------------------------------------------------------
        T.eq(D.screensFor("", ["A", "B"]), ["A", "B"], "nothing stored: every screen")
        T.eq(D.screensFor("B", ["A", "B"]), ["B"], "one screen")
        T.eq(D.screensFor("C", ["A", "B"]), ["A", "B"], "a screen that is gone: every screen, never none")
        T.eq(D.screensFor("B, A", ["A", "B"]), ["A", "B"], "in the screens' order")
        T.eq(D.screensFor(" ,", ["A"]), ["A"], "blank parts are no screens")
        T.eq(D.toggleScreen("", "A", ["A", "B"]), "B", "unticking one of all")
        T.eq(D.toggleScreen("B", "B", ["A", "B"]), null, "the last one cannot go")
        T.eq(D.toggleScreen("B", "A", ["A", "B"]), "", "all ticked is stored as all")
        T.eq(D.toggleScreen("B", "A", ["A", "B", "C"]), "A,B", "ticking keeps the screens' order")
        T.eq(D.optionValue("visibility", "intellihide"), "intellihide", "visibility")
        T.eq(D.optionValue("visibility", "sometimes"), null, "an unknown visibility")
        T.eq(D.optionValue("position", "top"), null, "no top dock: the notch and the bar live there")
        T.eq(D.optionValue("iconSize", "48"), 48, "an icon size")
        T.eq(D.optionValue("iconSize", "50"), null, "a size that is not offered")
        T.eq(D.optionValue("iconSize", "48.0"), null, "only whole numbers")
        T.eq(D.optionValue("margin", "16"), 16, "a margin")
        T.eq(D.optionValue("enabled", "true"), true, "a switch on")
        T.eq(D.optionValue("magnification", "false"), false, "and off")
        T.eq(D.optionValue("showRunning", "yes"), null, "only true and false")
        T.eq(D.optionValue("screens", "DP-8,HDMI-A-1"), "DP-8,HDMI-A-1", "screens by output name")
        T.eq(D.optionValue("screens", ""), "", "no screens named: every screen")
        T.eq(D.optionValue("screens", "a b"), null, "no spaces in output names")
        T.eq(D.optionValue("nonsense", "1"), null, "an unknown key")

        // ---- which app a window belongs to -------------------------------------------
        const outlook = entry("brave-faolnafnngnfdaknnbpnkhgohbobgegn-Default", "Outlook (PWA)", "crx_faolnafnngnfdaknnbpnkhgohbobgegn")
        T.ok(D.entryMatches(outlook, "brave-faolnafnngnfdaknnbpnkhgohbobgegn-Default"), "a web app by its Wayland app id")
        T.ok(D.entryMatches(outlook, "crx_faolnafnngnfdaknnbpnkhgohbobgegn"), "and by its X11 class (StartupWMClass)")
        T.ok(!D.entryMatches(outlook, "brave-browser"), "but the browser is not the web app")
        T.ok(D.entryMatches(entry("org.mozilla.firefox"), "firefox"), "the last part of a reverse-DNS id")
        T.ok(D.entryMatches(entry("firefox"), "org.mozilla.firefox"), "on either side")
        T.ok(D.entryMatches(entry("com.discordapp.Discord", "", "discord"), "discord"), "a Flatpak through its WM class")
        T.ok(D.entryMatches(entry("code", "", "Code"), "Code"), "a WM class in its own case")
        T.ok(D.entryMatches(entry("Alacritty"), "alacritty"), "case does not matter")
        T.ok(!D.entryMatches(entry("org.kde.dolphin"), ""), "an empty class matches nothing")
        T.ok(!D.entryMatches(null, "x"), "no entry matches nothing")
        const brave = entry("brave-browser", "Brave")
        const braveFlatpak = entry("com.brave.Browser", "Brave (Flatpak)", "brave-browser")
        const lookup = cls => cls === "brave-browser" ? brave : cls === "org.kde.dolphin" ? entry("org.kde.dolphin", "Dolphin") : null
        T.eq(D.resolve("brave-browser", [braveFlatpak], lookup).key, "app:com.brave.Browser", "a pinned duplicate wins over the lookup")
        T.eq(D.resolve("brave-browser", [], lookup).key, "app:brave-browser", "else the lookup")
        T.eq(D.resolve("steam_app_1", [], lookup), { key: "class:steam_app_1", entry: null }, "else the class itself")
        T.eq(D.resolve("", [], lookup), null, "no class, no app")
        T.eq(D.visibleWindows([win("0x1", "xwaylandvideobridge", 1), win("0x2", "a", 2, { workspaceName: "special:buchhwin-hidden" }),
                               win("0x3", "", 3), win("0x4", "foot", 4)]).map(w => w.address), ["0x4"],
             "the shell's helpers, the hidden workspace and classless windows are not shown")

        // ---- the apps in order -----------------------------------------------------------
        const a = entry("a"), b = entry("b"), c = entry("c")
        const look = cls => ({ a: a, b: b, c: c })[cls] || null
        T.eq(D.build([], [], look), [], "nothing pinned, nothing open: an empty dock")
        let items = D.build([a, b], [win("0x1", "b", 5), win("0x2", "c", 3)], look)
        T.eq(items.map(item => item.key), ["app:a", "app:b", "app:c"], "pins first in their order, then running apps")
        T.eq(items.map(item => [item.pinned, item.running]), [[true, false], [true, true], [false, true]], "pinned and running flags")
        items = D.build([a], [win("0x9", "c", 9), win("0x2", "c", 2)], look)
        T.eq(items[1].windows.map(w => w.address), ["0x2", "0x9"], "an app's windows in the order they appeared")
        T.eq(items[1].count, 2, "and how many")
        items = D.build([a, b], [win("0x1", "b", 1), win("0x2", "c", 2)], look, { showRunning: false })
        T.eq(items.map(item => item.key), ["app:a", "app:b"], "running apps off: the pins only")
        T.ok(items[1].running, "a pin still shows it runs")
        items = D.build([], [win("0x1", "c", 1, { activated: true }), win("0x2", "b", 2, { urgent: true })], look)
        T.ok(items[0].active && !items[0].urgent && items[1].urgent && !items[1].active, "active and urgent")
        items = D.build([], [win("0x1", "c", 1), win("0x2", "b", 2), win("0x3", "c", 7)], look)
        T.eq(items.map(item => item.key), ["app:c", "app:b"], "a new window of an app does not move the app")
        items = D.build([], [win("0x2", "b", 2), win("0x4", "c", 8)], look)
        T.eq(items.map(item => item.key), ["app:b", "app:c"], "an app whose windows all closed and one opened again comes back at the end")
        T.eq(D.build([], [win("0x1", "steam_app_9", 1)], look)[0].icons, ["", "steam_app_9"], "an unknown app's icon is its class")
        T.eq(D.build([], [win("0x1", "steam_app_9", 1)], look)[0].entryId, "", "and it has no entry to start")
        // Keyed: the same input twice gives the very same objects back.
        const first = Keyed.keep([], D.build([a], [win("0x1", "c", 1)], look), "key", { windows: "address" })
        const second = Keyed.keep(first, D.build([a], [win("0x1", "c", 1)], look), "key", { windows: "address" })
        T.ok(first[0] === second[0] && first[1] === second[1], "unchanged apps stay the same objects (pitfall 76)")

        // ---- a click ----------------------------------------------------------------
        const three = { entryId: "c", windows: [{ address: "0x1" }, { address: "0x2" }, { address: "0x3" }] }
        T.eq(D.clickTarget({ entryId: "a", windows: [] }, "", []), { action: "launch", address: "" }, "not running: start it")
        T.eq(D.clickTarget({ entryId: "", windows: [] }, "", []), { action: "none", address: "" }, "nothing to start")
        T.eq(D.clickTarget(three, "0x9", ["0x8", "0x2", "0x1"]), { action: "focus", address: "0x2" }, "not active: the window used last")
        T.eq(D.clickTarget(three, "0x9", []), { action: "focus", address: "0x1" }, "no history: its first window")
        T.eq(D.clickTarget(three, "0x2", ["0x2"]), { action: "focus", address: "0x3" }, "active: the next of its windows")
        T.eq(D.clickTarget(three, "0x3", ["0x3"]), { action: "focus", address: "0x1" }, "and round again")
        T.eq(D.clickTarget({ entryId: "c", windows: [{ address: "0x1" }] }, "0x1", []), { action: "none", address: "" },
             "active with one window: nothing")
        T.eq(D.newWindowAction([{ id: "new-private-window" }, { id: "new-window" }]), "new-window", "the new window action, not the private one")
        T.eq(D.newWindowAction([{ id: "Neue-Nachricht" }]), "", "none")
        T.eq(D.newWindowAction(null), "", "no actions")

        // ---- the menu -------------------------------------------------------------------
        const menuItem = { entryId: "brave-browser", pinned: false, windows: [{ address: "0x1", workspace: 2 }, { address: "0x2", workspace: 3 }, { address: "0x3", workspace: 3 }] }
        const rows = D.menuRows(menuItem, [{ id: "new-window", name: "New Window" }, { id: "new-private-window", name: "New Incognito Window" }], false, 2)
        T.eq(rows.map(row => row.kind), ["window", "window", "more", "new", "action", "pin", "close"], "windows, more, new, actions, pin, close")
        T.eq(rows[4].id, "new-private-window", "the new window action is not listed twice")
        T.eq(rows[2].count, 1, "one more window")
        T.eq(rows[6].count, 3, "close counts every window")
        T.eq(D.menuRows(menuItem, [], true).find(row => row.kind === "pin"), { kind: "pin", enabled: false }, "ten pinned: Pin is off")
        T.eq(D.menuRows({ entryId: "a", pinned: true, windows: [] }, [], false).map(row => row.kind), ["new", "unpin"], "a pinned app not running")
        T.eq(D.menuRows({ entryId: "", pinned: false, windows: [{ address: "0x1" }] }, [], false).map(row => row.kind), ["window", "close"],
             "an app without an entry: its windows and close")

        // ---- covered ----------------------------------------------------------------------
        const body = { x: 700, y: 1100, width: 520, height: 64 }
        const view = { monitor: "DP-1", workspace: 1, special: "" }
        function placed(extra) { return Object.assign(win("0x1", "foot", 1), { at: [0, 0], size: [1920, 1090] }, extra || {}) }
        T.ok(!D.covered(body, [], view, 4), "no windows")
        T.ok(D.covered(body, [placed({ size: [1920, 1188] })], view, 4), "a tile down to the bottom covers it")
        T.ok(!D.covered(body, [placed({ size: [1920, 1095] })], view, 0), "a window ending 5 px above it, no slack: not")
        T.ok(D.covered(body, [placed({ size: [1920, 1097] })], view, 4), "3 px above with 4 px slack: covered")
        T.ok(!D.covered(body, [placed({ at: [0, 1000], size: [600, 188] })], view, 4), "a window beside it")
        T.ok(!D.covered(body, [placed({ size: [1920, 1188], monitor: "DP-2" })], view, 4), "on another monitor")
        T.ok(!D.covered(body, [placed({ size: [1920, 1188], workspace: 2, workspaceName: "2" })], view, 4), "on another workspace")
        T.ok(D.covered(body, [placed({ size: [1920, 1188], workspace: 2, workspaceName: "2", pinned: true })], view, 4), "pinned to all")
        T.ok(D.covered(body, [placed({ size: [1920, 1188], workspace: -98, workspaceName: "special:term" })],
                       { monitor: "DP-1", workspace: 1, special: "special:term" }, 4), "on the special workspace open over it")
        T.ok(!D.covered(body, [placed({ size: [1920, 1188], hidden: true })], view, 4), "a hidden window")
        T.ok(!D.covered(body, [placed({ at: null })], view, 4), "no geometry yet: not covered")
        T.ok(!D.covered(body, [placed({ size: [0, 0] })], view, 4), "a zero size")
        T.ok(!D.covered(null, [placed({ size: [1920, 1188] })], view, 4), "no body yet")
        T.ok(D.needsPoll([placed({ floating: true })], [view]), "a floating window on a dock's workspace: poll")
        T.ok(!D.needsPoll([placed({ floating: false })], [view]), "tiled only: the events say everything")
        T.ok(!D.needsPoll([placed({ floating: true, workspace: 4, workspaceName: "4" })], [view]), "floating elsewhere: no poll")

        // ---- shown or not --------------------------------------------------------------
        const base = { enabled: true, mode: "intellihide" }
        function want(extra) { return D.wantRevealed(Object.assign({}, base, extra)) }
        T.ok(!D.wantRevealed({ enabled: false, mode: "always" }), "off is off")
        T.ok(!want({ fullscreen: true, dragging: true, menuOpen: true, keyboard: true, mode: "always" }), "fullscreen beats everything")
        T.ok(want({ covered: true, dragging: true }), "a drag keeps it")
        T.ok(want({ covered: true, menuOpen: true }), "its menu keeps it")
        T.ok(want({ covered: true, keyboard: true }), "the keyboard keeps it")
        T.ok(want({ mode: "always", covered: true }), "always shown")
        T.ok(want({ covered: true, pointer: true }), "the pointer at the edge shows it")
        T.ok(want({ covered: true, hotkey: true }), "the key shows it")
        T.ok(want({ covered: false }), "intellihide, nothing on it: shown")
        T.ok(!want({ covered: true }), "intellihide, a window on it: hidden")
        T.ok(!want({ mode: "hidden", covered: false }), "edge or key only: hidden on an empty desktop")
        T.ok(want({ mode: "hidden", pointer: true }), "and shown at the edge")
        T.eq(D.maskKind({ active: false, revealed: true }), "none", "under fullscreen no input")
        T.eq(D.maskKind({ active: true, revealed: true }), "body", "shown: its body")
        T.eq(D.maskKind({ active: true, revealed: false }), "strip", "hidden: the strip at the edge")
        T.eq(D.maskKind({ active: true, revealed: false, reserves: true }), "none", "a reserving dock is never hidden but under fullscreen")
        T.eq(D.revealTarget("B", ["A", "B"]), "B", "the key shows it on the focused screen")
        T.eq(D.revealTarget("C", ["A", "B"]), "A", "or the first screen with a dock")
        T.eq(D.revealTarget("C", []), "", "or nowhere")

        // ---- geometry -------------------------------------------------------------------
        const m = { icon: 48, pad: 6, gap: 6, margin: 8, headroom: 40, windowGap: 12, strip: 2, count: 3, room: 1920, sep: -1, sepRoom: 0 }
        let g = D.geometry("bottom", m, false)
        T.eq(g.thickness, 8 + 60 + 40, "thickness: margin, body, headroom")
        T.eq(g.length, 6 + 48 * 3 + 6 * 2 + 6, "length: the icons, their gaps and the padding")
        T.eq(g.body, { x: Math.round((1920 - 168) / 2), y: 108 - 8 - 60, width: 168, height: 60 }, "bottom: centred, a margin above the edge")
        T.eq(g.strip.y + g.strip.height, g.thickness, "the strip lies on the screen edge")
        T.eq(g.hit.y + g.hit.height, g.thickness, "the pointer on the edge under the dock is on it")
        T.eq(g.zone, 0, "intellihide reserves nothing")
        T.eq(D.geometry("bottom", m, true).zone, 2 * 8 + 60 - 12, "always: the body and a margin each side, less the window gap")
        T.eq(g.reach, 68, "how far it reaches into the screen")
        g = D.geometry("left", Object.assign({}, m, { room: 1200 }), false)
        T.eq([g.body.x, g.body.width, g.body.height], [8, 60, 168], "left: a margin from the edge, the body across")
        g = D.geometry("right", Object.assign({}, m, { room: 1200 }), false)
        T.eq(g.body.x + g.body.width, g.thickness - 8, "right: a margin from the right edge")
        T.eq(D.geometry("top", m, false).edge, "bottom", "an unknown edge is the bottom")
        const many = Object.assign({}, m, { count: 40, room: 1000 })
        g = D.geometry("bottom", many, false)
        T.ok(g.icon < 48 && g.length <= 1000, "too many apps: smaller icons, still on the screen (" + g.icon + ", " + g.length + ")")
        T.eq(g.thickness, D.geometry("bottom", m, false).thickness, "and the surface keeps its thickness")
        T.eq(D.fit(0, 48, 6, 100, 6), 48, "no apps: the setting")
        T.eq(D.fit(1000, 48, 6, 100, 6), D.MIN_ICON, "never below the smallest")
        const lay = D.layout(3, 48, 8, [1, 1, 1], 0, -1, 0)
        T.eq([lay.offsets, lay.length], [[0, 56, 112], 160], "layout: offsets and length")
        T.eq(D.layout(3, 48, 8, null, 4, 2, 10).offsets, [4, 60, 126], "a separator's room before the first running app")
        T.eq(D.globalRect({ x: 10, y: 40, width: 100, height: 60 }, { x: 1920, y: 0, width: 1920, height: 1200 }, { bottom: 30 }, 108, "bottom"),
             { x: 1930, y: 1200 - 30 - 108 + 40, width: 100, height: 60 }, "bottom: lifted by a bar under it, on its screen")
        T.eq(D.globalRect({ x: 8, y: 300, width: 60, height: 100 }, { x: 0, y: 0, width: 1920, height: 1200 }, { top: 40 }, 108, "left"),
             { x: 8, y: 340, width: 60, height: 100 }, "left: below a top bar")
        T.eq(D.globalRect(null, { x: 0, y: 0, width: 1, height: 1 }, {}, 1, "bottom"), null, "no rect")

        // ---- magnification -------------------------------------------------------------
        const scales = D.magnify(110, [30, 70, 110, 150, 190], 1.6, 70)
        T.near(scales[2], 1.6, "the icon under the pointer at the peak", 0.001)
        T.ok(scales[1] > 1 && scales[1] < 1.6 && Math.abs(scales[1] - scales[3]) < 0.001, "its neighbours less, the same each side")
        T.near(scales[0], 1, "outside the reach: rest", 0.001)
        T.eq(D.magnify(-1, [10, 20], 1.6, 96), [1, 1], "the pointer away: all at rest")
        T.eq(D.magnify(10, [10], 1, 96), [1], "no magnification at 1")

        // ---- drag -------------------------------------------------------------------------
        const pins = ["a", "b", "c"]
        T.eq(D.dropPlan({ entryId: "a", pinned: true }, 2, pins, 10), { action: "move", id: "a", index: 2 }, "a pin to the end")
        T.eq(D.dropPlan({ entryId: "b", pinned: true }, 1, pins, 10), { action: "none" }, "dropped where it was")
        T.eq(D.dropPlan({ entryId: "c", pinned: true }, 9, pins, 10), { action: "none" }, "past the last pin is the last place, where c is")
        T.eq(D.dropPlan({ entryId: "x", pinned: false }, 1, pins, 10), { action: "pin", id: "x", index: 1 }, "a running app is pinned there")
        T.eq(D.dropPlan({ entryId: "x", pinned: false }, 1, pins, 3), { action: "full" }, "unless the pins are full")
        T.eq(D.dropPlan({ entryId: "", pinned: false }, 0, pins, 10), { action: "none" }, "an app without an entry cannot be pinned")
        T.eq(D.slotAt(10, [[0, 48], [54, 48]]), 0, "before the first pin's middle")
        T.eq(D.slotAt(60, [[0, 48], [54, 48]]), 1, "between")
        T.eq(D.slotAt(500, [[0, 48], [54, 48]]), 2, "past the last")
        T.eq(D.slotAt(5, []), 0, "no pins")

        T.finish("DockTest")
    }
}
