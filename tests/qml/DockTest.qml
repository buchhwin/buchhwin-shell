import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/dock/DockLogic.js" as D
import "../../services/model/KeyedLogic.js" as Keyed

// The dock's arithmetic (services/dock/DockLogic.js): which app a window
// belongs to, the order of the apps, what a click does, when a window covers
// the dock, when it shows, its geometry, its keys and its drag.
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
        T.eq(D.optionValue("startOpens", "launcher"), "launcher", "the start button opens the launcher")
        T.eq(D.optionValue("startOpens", "startMenu"), "startMenu", "or the start menu")
        T.eq(D.optionValue("startOpens", "dashboard"), null, "nothing else")

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
        items = D.build([], [win("0x1", "c", 1), win("0x2", "b", 2, { urgent: true })], look)
        T.ok(D.isActive(items[0], "0x1") && !items[0].urgent && items[1].urgent && !D.isActive(items[1], "0x1"), "active and urgent")
        T.ok(items[0].active === undefined, "which app is in front is not built in: a focus change rebuilds nothing")
        T.ok(!D.isActive(items[0], "") && !D.isActive(null, "0x1"), "nothing in front: no app is active")
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
        // An empty workspace in front: Quickshell still names the last window
        // as active, and the click on its app did nothing.
        T.eq(D.frontAddress({ address: "0x1", workspace: 1 }, 2), "", "a window on a workspace behind is not in front")
        T.eq(D.frontAddress({ address: "0x1", workspace: 2 }, 2), "0x1", "on the focused workspace it is")
        T.eq([D.frontAddress({ address: "0x1", workspace: -98 }, 2), D.frontAddress({ address: "0x1", workspace: 1, pinned: true }, 2)],
             ["0x1", "0x1"], "a special workspace's window and a pinned one are in front wherever")
        T.eq([D.frontAddress({ address: "0x1", workspace: 1 }, 0), D.frontAddress({ address: "0x1" }, 2),
              D.frontAddress(null, 2), D.frontAddress({ address: "", workspace: 2 }, 2)], ["0x1", "0x1", "", ""],
             "nothing known: as before; no window: none")
        T.eq(D.clickTarget({ entryId: "code", windows: [{ address: "0x1" }] }, D.frontAddress({ address: "0x1", workspace: 1 }, 2), []),
             { action: "focus", address: "0x1" }, "so its app's click goes to that window")
        T.eq(D.clickTarget(three, "0x9", ["0x8", "0x2", "0x1"]), { action: "focus", address: "0x2" }, "not active: the window used last")
        T.eq(D.clickTarget(three, "0x9", []), { action: "focus", address: "0x1" }, "no history: its first window")
        T.eq(D.clickTarget(three, "0x2", ["0x2"]), { action: "focus", address: "0x3" }, "active: the next of its windows")
        T.eq(D.clickTarget(three, "0x3", ["0x3"]), { action: "focus", address: "0x1" }, "and round again")
        T.eq(D.clickTarget({ entryId: "c", windows: [{ address: "0x1" }] }, "0x1", []), { action: "none", address: "" },
             "active with one window: nothing")
        T.eq(D.newWindowAction([{ id: "new-private-window" }, { id: "new-window" }]), "new-window", "the new window action, not the private one")
        T.eq(D.newWindowAction([{ id: "Neue-Nachricht" }]), "", "none")
        T.eq(D.newWindowAction(null), "", "no actions")
        // The ids on this machine: VS Code's and Alacritty's own
        // actions did what "New window" does, and the menu listed both.
        T.eq(D.newWindowAction([{ id: "new-empty-window", command: ["/usr/bin/code", "--new-window"] }], ["/usr/bin/code"]),
             "new-empty-window", "VS Code's new empty window")
        T.eq(D.newWindowAction([{ id: "New", command: ["alacritty"] }], ["alacritty"]), "New",
             "Alacritty's bare New runs its own program")
        T.eq(D.newWindowAction([{ id: "New", command: ["libreoffice", "--writer"] }], ["soffice"]), "",
             "a bare New of another program may be a document: not")
        T.eq(D.newWindowAction([{ id: "new", command: ["kate"] }], []), "", "and not without the entry's own command")
        T.eq(D.newWindowAction([{ id: "new-instance" }]), "new-instance", "a new instance")
        T.eq(D.newWindowAction([{ id: "new-document" }]), "", "a new document is no window")

        // ---- the menu -------------------------------------------------------------------
        const menuItem = { entryId: "brave-browser", pinned: false, windows: [{ address: "0x1", workspace: 2 }, { address: "0x2", workspace: 3 }, { address: "0x3", workspace: 3 }] }
        const rows = D.menuRows(menuItem, [{ id: "new-window", name: "New Window" }, { id: "new-private-window", name: "New Incognito Window" }], false, 2)
        T.eq(rows.map(row => row.kind), ["window", "window", "more", "new", "action", "pin", "close"], "windows, more, new, actions, pin, close")
        T.eq(rows[4].id, "new-private-window", "the new window action is not listed twice")
        T.eq(rows[2].count, 1, "one more window")
        T.eq(rows[6].count, 3, "close counts every window")
        T.eq(D.menuRows(menuItem, [], true).find(row => row.kind === "pin"), { kind: "pin", enabled: false, reason: "full" },
             "the pins full: Pin is off, and says why")
        const alacritty = { entryId: "Alacritty", pinned: true, windows: [] }
        T.eq(D.menuRows(alacritty, [{ id: "New", name: "New Terminal", command: ["alacritty"] }], false, 3, ["alacritty"])
                 .map(row => row.kind), ["new", "unpin"], "Alacritty's New Terminal is not listed beside New window")
        T.eq(D.menuRows({ entryId: "x", pinned: false, pinnable: false, windows: [{ address: "0x1" }] }, [], false)
                 .find(row => row.kind === "pin"), { kind: "pin", enabled: false, reason: "hidden" },
             "an entry the dock could not draw once pinned: Pin is off")
        T.eq(D.menuRows({ entryId: "default:files", special: "choose", pinned: true, windows: [] }, [], false).map(row => row.kind),
             ["unpin"], "a default's placeholder: only unpin")
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
        // Polled only for a floating window that could come over a drawn
        // dock or leave it.
        const bodies = { "DP-1": body }
        const onIt = { size: [1920, 1188] }
        T.ok(D.needsPoll([placed(Object.assign({ floating: true }, onIt))], [view], bodies, "", 4),
             "a floating window on the dock: poll, to see it go")
        T.ok(!D.needsPoll([placed({ floating: true })], [view], bodies, "", 4),
             "a floating window away from the dock, not focused: no poll")
        T.ok(D.needsPoll([placed({ floating: true })], [view], bodies, "0x1", 4),
             "the focused one, which a hand or a key may move: poll")
        T.ok(D.needsPoll([placed({ floating: true, at: null })], [view], bodies, "", 4), "one not placed yet: poll")
        T.ok(!D.needsPoll([placed({ floating: true, pinned: true, workspace: 4, workspaceName: "4", at: [1500, 40], size: [400, 225] })],
                          [view], bodies, "", 4), "a pinned picture-in-picture far from the dock: no poll")
        T.ok(!D.needsPoll([placed(Object.assign({ floating: true }, onIt))], [view], {}, "0x1", 4),
             "no body reported - fullscreen, or no dock drawn there: no poll")
        T.ok(!D.needsPoll([placed(Object.assign({ floating: false }, onIt))], [view], bodies, "0x1", 4), "tiled only: the events say everything")
        T.ok(!D.needsPoll([placed({ floating: true, workspace: 4, workspaceName: "4" })], [view], bodies, "0x1", 4), "floating elsewhere: no poll")
        // Special workspaces open before the dock listened.
        T.eq(D.specialsFrom([{ name: "eDP-1", specialWorkspace: { id: -98, name: "special:term" } },
                             { name: "DP-8", specialWorkspace: { id: 0, name: "" } }, { name: "" }, null]),
             { "eDP-1": "special:term", "DP-8": "" }, "the special workspace open on each monitor, from hyprctl monitors")
        T.eq(D.specialsFrom(null), {}, "nothing read: nothing")
        T.eq(D.seededSpecials({ "eDP-1": "", "DP-8": "special:a" }, { "eDP-1": "special:term", "DP-8": "" }, { "DP-8": true }),
             { "eDP-1": "special:term", "DP-8": "special:a" }, "the read fills in, an event since keeps its newer word")
        T.ok(D.covered(body, [placed({ size: [1920, 1188], workspace: -98, workspaceName: "special:term" })],
                       { monitor: "DP-1", workspace: 1, special: D.specialsFrom([{ name: "DP-1", specialWorkspace: { name: "special:term" } }])["DP-1"] }, 4),
             "so its windows cover the dock from the start")

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
        T.eq(D.maskKind({ active: true, revealed: true, dragging: true }), "window", "a drag keeps the whole surface")
        T.eq(D.maskKind({ active: false, revealed: true, dragging: true }), "none", "but not under fullscreen")
        T.eq(D.revealTarget("B", ["A", "B"]), "B", "the key shows it on the focused screen")
        T.eq(D.revealTarget("C", ["A", "B"]), "A", "or the first screen with a dock")
        T.eq(D.revealTarget("C", []), "", "or nowhere")

        // ---- geometry -------------------------------------------------------------------
        T.eq(D.fit(0, 48, 6, 100, 6), 48, "no apps: the setting")
        T.eq(D.fit(1000, 48, 6, 100, 6), D.MIN_ICON, "never below the smallest")
        T.eq(D.fit(3, 48, 6, 1000, 0), 48, "room enough: the setting")
        // The room the apps have, measured without them, and the
        // icons fitted into it - a side dock under the notch (1172 px) with
        // 24 apps, and a portrait taskbar whose right zone holds the status.
        T.eq(D.appsRoom(1172 - 16, 6, 12, [{ apps: false, length: 0 }, { apps: true, beside: 20 }, { apps: false, length: 0 }]),
             1156 - 12 - 20, "the body less its padding and the apps' own padding")
        const portrait = D.appsRoom(1270, 6, 12, [{ apps: true, beside: 80 }, { apps: false, length: 0 }, { apps: false, length: 300 }])
        T.eq(portrait, 1270 - 12 - 80 - 300 - 12, "less the start button beside them, the right zone and one gap")
        const fitted = D.fit(24, 40, 6, portrait, 0)
        T.ok(fitted < 40 && D.layout(24, fitted, 6, null, 0, -1, 0).length <= portrait,
             "24 apps fit beside the status zone (" + fitted + " px)")
        T.eq(D.appsRoom(1920, 6, 12, [{ apps: false, length: 100 }, { apps: false, length: 0 }, { apps: false, length: 0 }]), -1,
             "no apps zone: no room to fit")
        T.eq(D.appsRoom(100, 6, 12, [{ apps: true, beside: 400 }]), 0, "never below nothing")
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

        // ---- the key ---------------------------------------------------------------------
        T.eq(D.keyAction({ enabled: false, target: "A" }), "on", "an off dock is switched on")
        T.eq(D.keyAction({ enabled: true, target: "A", hotkey: "", fullscreen: false }), "shown", "shown with the keyboard")
        T.eq(D.keyAction({ enabled: true, target: "A", hotkey: "A" }), "hidden", "again: hidden")
        T.eq(D.keyAction({ enabled: true, target: "A", hotkey: "A", peeking: true }), "shown",
             "after the look \"on\" gave it, the key gives it the keyboard")
        // Under a fullscreen window nothing is armed.
        T.eq(D.keyAction({ enabled: true, target: "A", hotkey: "", fullscreen: true }), "fullscreen", "under fullscreen: nothing")
        T.eq(D.keyAction({ enabled: true, target: "" }), "none", "no screen with a dock")
        // The dock's menu holds the keys and gives them back on Escape.
        T.eq(D.keysAfterPanel("dockMenu", false, false), { keep: true, withMenu: true }, "the menu opens: it holds the keys")
        T.eq(D.keysAfterPanel("", true, true), { keep: true, withMenu: false }, "closed with Escape: back to the dock")
        T.eq(D.keysAfterPanel("", true, false), { keep: false, withMenu: false }, "closed by a click elsewhere: let go")
        T.eq(D.keysAfterPanel("launcher", true, false), { keep: false, withMenu: false }, "another panel: let go")
        T.eq(D.keysAfterPanel("launcher", false, false), { keep: false, withMenu: false }, "any panel takes the keys")
        T.eq(D.keysAfterPanel("", false, false), { keep: true, withMenu: false }, "a close of nothing: nothing")
        // The start button in the keys' ring.
        T.eq(D.keyRange(4, 1, 0), { low: -1, high: 3 }, "a start button before the apps")
        T.eq(D.keyRange(4, 0, 1), { low: 0, high: 4 }, "and after them")
        T.eq(D.keyRange(4, 0, 0), { low: 0, high: 3 }, "none")
        T.eq(D.keyRange(0, 0, 0), { low: 0, high: 0 }, "no apps")
        T.eq([D.keyStop(-1, 4, ["start"], []), D.keyStop(4, 4, [], ["start"]), D.keyStop(0, 4, ["start"], []), D.keyStop(-1, 4, [], [])],
             [{ kind: "item", type: "start" }, { kind: "item", type: "start" }, { kind: "app", index: 0 }, null],
             "where the start button is in the ring")
        // And the taskbar's other items: its status, notifications, clock.
        const taskbarItems = [{ type: "clock", rect: { x: 1800, y: 1150, width: 60, height: 50 } },
                              { type: "start", rect: { x: 0, y: 1150, width: 50, height: 50 } },
                              { type: "network", rect: { x: 1600, y: 1150, width: 40, height: 50 } },
                              { type: "apps", rect: { x: 60, y: 1150, width: 300, height: 50 } },
                              { type: "battery", rect: null },
                              { type: "media", rect: { x: 1500, y: 1150, width: 40, height: 50 } }]
        const sides = D.keySides(taskbarItems, { x: 66, y: 1155, width: 40, height: 40 }, false, type => type !== "media")
        T.eq(sides, { before: ["start"], after: ["network", "clock"] },
             "the items that open something, in order along the dock, minus the apps, one not shown and one that opens nothing")
        T.eq(D.keySides(taskbarItems, null, false, null), { before: ["start", "media", "network", "clock"], after: [] },
             "no apps on the dock: everything is before them")
        T.eq(D.keySides([{ type: "clock", rect: { x: 0, y: 900, width: 60, height: 40 } }, { type: "start", rect: { x: 0, y: 10, width: 60, height: 40 } }],
                        { x: 4, y: 60, width: 52, height: 52 }, true, null), { before: ["start"], after: ["clock"] },
             "down a side dock by y")
        T.eq(D.keyRange(4, sides.before.length, sides.after.length), { low: -1, high: 5 }, "the ring runs over them all")
        T.eq([D.keyStop(4, 4, sides.before, sides.after), D.keyStop(5, 4, sides.before, sides.after), D.keyStop(6, 4, sides.before, sides.after)],
             [{ kind: "item", type: "network" }, { kind: "item", type: "clock" }, null], "past the apps, the items in order")
        T.eq(D.keyRange(0, 2, 0), { low: -2, high: -1 }, "items only: no place for an app that is not there")
        T.eq(D.keyStop(-2, 0, ["start", "clock"], []), { kind: "item", type: "start" }, "the farthest before is the first along the dock")
        T.eq(D.layoutTypes({ left: [{ items: [{ type: "start" }, { type: "apps" }] }], center: [],
                             right: [{ items: [{ type: "clock" }, { type: "date" }] }, { items: [{ type: "clock" }] }] }),
             ["start", "apps", "clock", "date"], "every type on a dock layout, once")
        T.eq(D.layoutTypes(null), [], "no layout: none")

        // ---- events --------------------------------------------------------------------
        T.ok(D.COVER_EVENTS.indexOf("activewindowv2") < 0, "a focus change re-reads no window")
        T.ok(D.COVER_EVENTS.indexOf("focusedmon") < 0 && D.COVER_EVENTS.indexOf("focusedmonv2") < 0,
             "nor does the focus going to another monitor: each keeps its workspace")
        T.ok(D.COVER_EVENTS.indexOf("workspace") >= 0 && D.COVER_EVENTS.indexOf("activespecial") >= 0,
             "a workspace that changes says so itself")
        T.ok(D.COVER_EVENTS.indexOf("moveworkspacev2") >= 0 && D.COVER_EVENTS.indexOf("moveworkspace") >= 0,
             "a workspace moved to another monitor does")

        // ---- a default with no app ------------------------------------------------------
        const glyphs = { files: "F", terminal: "T", browser: "B" }
        T.eq(D.defaultPlaceholder("@files", false, glyphs), { id: "default:files", name: "File manager", icon: "", startupClass: "",
                                                            pin: "@files", special: "default", glyph: "F" },
             "not read yet: its place and glyph, a click starts the default")
        T.eq(D.menuRows(D.build([D.defaultPlaceholder("@files", false, glyphs)], [], look)[0], [], false).map(row => row.kind),
             ["unpin"], "and its menu has no New window that would start nothing, only unpin")
        T.eq(D.defaultPlaceholder("@browser", true, glyphs).special, "choose", "read and none: a click asks for one")
        T.eq(D.defaultPlaceholder("@browser", true, glyphs).name, "Choose a web browser", "and says so")
        T.eq(D.defaultPlaceholder("org.kde.dolphin", true, glyphs), null, "an app id has no placeholder")
        const placeholderItem = D.build([D.defaultPlaceholder("@terminal", false, glyphs)], [], look)[0]
        T.eq([placeholderItem.key, placeholderItem.pin, placeholderItem.glyph, placeholderItem.pinned],
             ["app:default:terminal", "@terminal", "T", true], "it stays on the dock as a pin")
        T.eq(D.clickTarget(placeholderItem, "", []).action, "launch", "and can be clicked")

        // ---- zones ---------------------------------------------------------------------
        const shownPills = [{ hasContent: true, visible: false }, { hasContent: false, visible: false }, { hasContent: true, visible: false }]
        T.eq(D.shownCount(shownPills), 2, "pills counted by their own condition, not by visible")
        T.eq(D.shownFlags([null].concat(shownPills)), [false, true, false, true], "and flagged the same way")

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
        // The slot is counted over the pins shown, the plan over
        // the stored ones, which hold one the dock cannot draw.
        const stored = ["gone-app", "@files", "@terminal", "@settings", "@browser"]
        const shown = ["@files", "@terminal", "@settings", "@browser"]
        let at = D.storedSlot(1, shown, stored, "@files")
        T.eq(D.dropPlan({ pin: "@files", pinned: true }, at, stored, 12), { action: "move", id: "@files", index: 2 },
             "Files dropped behind Terminal moves there")
        at = D.storedSlot(3, shown, stored, "@files")
        T.eq(D.dropPlan({ pin: "@files", pinned: true }, at, stored, 12), { action: "move", id: "@files", index: 4 }, "and to the end")
        T.eq(D.storedSlot(0, shown, stored, "@browser"), 1, "first among the shown: before the first shown pin")
        T.eq(D.storedSlot(1, ["a", "b"], ["a", "b"], "x"), 1, "a running app dropped among the pins")
        // Pulled off the dock.
        const pinned = { pin: "a", pinned: true }, running = { pin: "b", pinned: false }
        T.eq(D.dragOutcome(pinned, 10, 48, 1, 1.5), "drop", "near the dock: a drop")
        T.eq(D.dragOutcome(pinned, 60, 48, 1, 1.5), "none", "off the dock, not far: nothing")
        T.eq(D.dragOutcome(pinned, 80, 48, 1, 1.5), "unpin", "far off the dock: unpinned")
        T.eq(D.dragOutcome(running, 200, 48, 1, 1.5), "none", "a running app has no pin to lose")
        T.eq(D.dragOutcome(pinned, Infinity, 48, 1, 1.5), "none", "a drag the system took away does nothing")
        T.eq(D.unpinDistance(40, 1.5, 28), 28, "the unpin distance stays within the room above the dock")
        T.eq([D.unpinDistance(40, 1.5, Infinity), D.unpinDistance(40, 1.5, 0)], [60, 60], "with room to spare: 1.5 icons")
        T.eq(D.dragOutcome(pinned, 30, 40, 1, 1.5, 28), "unpin", "a pull just past the room's limit unpins")
        T.eq(D.dragOutcome(pinned, 20, 40, 1, 1.5, 28), "drop", "a shorter one is still a move")
        T.ok(D.dragAway(pinned, 72, 48, 1.5) && !D.dragAway(pinned, 71, 48, 1.5) && !D.dragAway(pinned, Infinity, 48, 1.5),
             "where the label starts to say so")
        // Pulled straight off the dock: a drag, though it moved nothing along
        // the dock - counted along alone the pull never began one.
        T.ok(D.dragStarts(0, 3, 3), "pulled out past the icon: a drag")
        T.ok(D.dragStarts(-3, 0, 3) && D.dragStarts(3, 0, 3), "moved along: a drag")
        T.ok(!D.dragStarts(2, 2, 3) && !D.dragStarts(0, 0, 3), "a wobble on the icon stays a click")

        // ---- panels out of the dock -----------------------------------------------
        const button = { x: 10, y: 1032, width: 40, height: 40 }
        T.eq(D.panelAnchor("bottom", button, 6), { anchorX: 30, anchorBottom: 1026, fromDock: true }, "above a bottom dock, centred on it")
        T.eq(D.panelAnchor("left", { x: 0, y: 500, width: 48, height: 41 }, 6),
             { anchorY: 521, anchorLeft: 54, fromDock: true }, "beside a left one")
        T.eq(D.panelAnchor("right", { x: 1872, y: 500, width: 48, height: 40 }, 6),
             { anchorY: 520, anchorRight: 1866, fromDock: true }, "and a right one")
        T.eq(D.panelAnchor("bottom", null, 6), {}, "no place: nothing to anchor to")
        T.eq(D.panelAnchor("bottom", { x: 0, y: 0, width: 0, height: 40 }, 6), {}, "nor an empty one")
        T.eq(D.panelAnchor("bottom", button, -3).anchorBottom, 1032, "no negative gap")
        // The gap off the dock's body, not off the item inside it - the
        // start menu stood flush on the taskbar.
        const taskbar = { x: 0, y: 1149, width: 1920, height: 51 }
        const start = { x: 8, y: 1157, width: 60, height: 35 }
        T.eq(D.panelAnchor("bottom", start, 16, taskbar), { anchorX: 38, anchorBottom: 1133, fromDock: true },
             "above the taskbar's top line by the gap")
        T.eq(D.panelAnchor("left", { x: 12, y: 500, width: 40, height: 40 }, 16, { x: 8, y: 300, width: 52, height: 600 }),
             { anchorY: 520, anchorLeft: 76, fromDock: true }, "beside a left dock's body")
        T.eq(D.panelAnchor("right", { x: 1870, y: 500, width: 40, height: 40 }, 16, { x: 1860, y: 300, width: 52, height: 600 }),
             { anchorY: 520, anchorRight: 1844, fromDock: true }, "and a right one's")
        T.eq(D.panelAnchor("bottom", start, 16, { x: 0, y: 0, width: 0, height: 0 }).anchorBottom, 1157 - 16,
             "no body known: off the item, as before")
        // A full dock's menu offers no pin: the dock's own limit, not the
        // launcher's (DockMenu handed the launcher's flag before).
        T.eq(D.menuRows({ entryId: "x", pinned: false, windows: [] }, [], true, 3).find(row => row.kind === "pin"),
             { kind: "pin", enabled: false, reason: "full" }, "the pin row is off while the dock's pins are full")

        // ---- the room an "always" dock keeps ---------------------------------------------
        // The taskbar (margin 0, 40 px icons: 52 across) and the dock (margin
        // 8, 48 px: 60): Hyprland puts gaps_out between a window and the
        // reserved room, so the windows end the margin off the body at every
        // gap - with a fixed 12 they ran 4 px under the taskbar at the
        // laptop mode's 8 and 12 px at 0.
        for (const gap of [12, 8, 0]) {
            T.eq(D.reserveZone(0, 52, gap) + gap, 52, "taskbar, gap " + gap + ": the windows end at its top line")
            T.eq(D.reserveZone(8, 60, gap) + gap - (8 + 60), 8, "dock, gap " + gap + ": its margin above it")
        }
        T.eq(D.reserveZone(0, 52, 60), 0, "a gap wider than the taskbar: no room reserved, never less")
        T.eq(D.reserveZone(8, 60, "x"), 76, "a gap not known: none")

        // ---- a drag the system took away ---------------------------------------------
        // A pull past the surface's edge is a leave, and Qt cancels the press
        // there: the bottom dock's 28 px to the unpin, its surface 42 px high.
        T.eq(D.cancelOutcome(pinned, 30, true, 40, 1.5, 28), "unpin", "pulled past the unpin distance, then off the surface: unpinned")
        T.eq(D.cancelOutcome(pinned, 30, false, 40, 1.5, 28), "unpin", "however it was moving last")
        T.eq(D.cancelOutcome(pinned, 16, true, 40, 1.5, 28), "unpin", "a quick pull still going away past half of it")
        T.eq(D.cancelOutcome(pinned, 16, false, 40, 1.5, 28), "none", "half way and not going away: nothing")
        T.eq(D.cancelOutcome(pinned, 10, true, 40, 1.5, 28), "none", "a cancel near the dock: nothing")
        T.eq(D.cancelOutcome(running, 60, true, 40, 1.5, 28), "none", "a running app has no pin to lose")
        T.eq(D.cancelOutcome(pinned, Infinity, true, 40, 1.5, 28), "none", "no place known: nothing")
        T.eq(D.cancelOutcome(null, 60, true, 40, 1.5, 28), "none", "no app: nothing")
        T.eq(D.dragOutcome(pinned, Infinity, 48, 1, 1.5), "none", "a release with no place known still does nothing")

        // ---- a drag whose app went ---------------------------------------------------------
        T.ok(D.dragLost("app:a", [{ key: "app:b" }]), "the dragged app is gone: the drag is over")
        T.ok(!D.dragLost("app:a", [{ key: "app:a" }, { key: "app:b" }]), "still there: it goes on")
        T.ok(!D.dragLost("", []), "no drag: nothing to end")

        // ---- the names over the icons ------------------------------------------------------
        let label = D.labelAfter({ index: -1, shown: false }, 0, true)
        T.eq(label, { index: 0, shown: false, timer: "show" }, "onto an icon: its name after the delay")
        label = D.labelAfter({ index: 0, shown: true }, 0, false)
        T.eq(label, { index: 0, shown: true, timer: "hide" }, "off it, into the gap: the name stays for the grace")
        label = D.labelAfter({ index: label.index, shown: label.shown }, 1, true)
        T.eq(label, { index: 1, shown: true, timer: "stop" }, "onto the next icon within it: its name at once")
        T.eq(D.labelAfter({ index: 1, shown: true }, 0, false), { index: 1, shown: true, timer: "keep" },
             "the old icon's leave after the new one's enter changes nothing")
        T.eq(D.labelAfter({ index: 0, shown: false }, 0, false), { index: 0, shown: false, timer: "stop" },
             "off an icon before its name showed: no name")
        T.eq(D.labelAfter({ index: 0, shown: false }, 1, true), { index: 1, shown: false, timer: "show" },
             "onto another before any showed: the delay again")
        T.eq(D.labelInRow({ index: 2, shown: true }, 2), { index: -1, shown: false, timer: "stop" },
             "the last icon gone from under the pointer: its name goes with it")
        T.eq(D.labelInRow({ index: 2, shown: false }, 2), { index: -1, shown: false, timer: "stop" },
             "and so does a name still waiting to show")
        T.eq([D.labelInRow({ index: 1, shown: true }, 2), D.labelInRow({ index: -1, shown: false }, 0),
              D.labelInRow({ index: 0, shown: true }, 3)], [null, null, null],
             "an icon still in the row keeps its name, and no name has nothing to take down")
        T.eq(D.labelInRow({ index: 0, shown: true }, 0), { index: -1, shown: false, timer: "stop" }, "an emptied row takes it down too")

        // ---- started, not open yet -----------------------------------------------------
        const firstStart = { since: 1000, before: 0, active: false }
        T.ok(!D.launchDone(firstStart, { count: 0, active: false }, 2000, 10000), "started, no window yet")
        T.ok(D.launchDone(firstStart, { count: 1, active: false }, 2000, 10000), "its window shows")
        T.ok(D.launchDone(firstStart, { count: 0, active: false }, 11000, 10000), "or the limit is up")
        const again = { since: 1000, before: 1, active: false }
        T.ok(D.launchDone(again, { count: 1, active: true }, 1500, 10000), "a single-instance app that only came to the front")
        const front = { since: 1000, before: 1, active: true }
        T.ok(!D.launchDone(front, { count: 1, active: true }, 3000, 10000), "started again in front: not at once")
        T.ok(D.launchDone(front, { count: 1, active: true }, 3500, 10000), "but after a quarter of the limit, not ten seconds")
        T.eq(D.launchWait({ a: firstStart, b: front }, 2000, 10000), 1500, "the next deadline: the relaunch's")
        T.eq(D.launchWait({ a: firstStart }, 2000, 10000), 9000, "a first start waits the whole limit")
        T.eq(D.launchWait({}, 2000, 10000), -1, "nothing started: no timer")

        // ---- where a window is, in the menu -------------------------------------------
        T.eq(D.workspaceLabel(3, "3"), "Workspace 3", "a numbered workspace")
        T.eq(D.workspaceLabel(-98, "special:term"), "Scratchpad term", "a named special workspace, not -98")
        T.eq([D.workspaceLabel(-99, "special:special"), D.workspaceLabel(-99, "special")], ["Scratchpad", "Scratchpad"],
             "the unnamed one")
        T.eq(D.workspaceLabel(-1337, "music"), "Workspace music", "a named workspace by its name")
        T.eq([D.workspaceLabel(-1, ""), D.workspaceLabel(4, "")], ["", "Workspace 4"], "not known: nothing; no name: its number")
        const special = D.build([], [win("0x5", "c", 5, { workspace: -98, workspaceName: "special:term" })], look)[0]
        T.eq(D.menuRows(special, [], false)[0], { kind: "window", address: "0x5", workspace: -98, workspaceName: "special:term" },
             "the window rows carry the workspace's name")

        // ---- the resolver -------------------------------------------------------------
        let asked = 0
        const counting = cls => { asked += 1; return look(cls) }
        const find = D.resolver([braveFlatpak, entry("org.kde.dolphin")], counting)
        T.eq([find("brave-browser").key, find("dolphin").key, find("c").key, find("steam_app_1").key],
             ["app:com.brave.Browser", "app:org.kde.dolphin", "app:c", "class:steam_app_1"], "resolves as resolve() does")
        const before = asked
        T.ok(find("c") === find("c") && find("steam_app_1").key === "class:steam_app_1" && asked === before,
             "and asks the lookup once per class")
        T.eq(find(""), null, "no class, no app")
        T.ok(find("__proto__").key === "class:__proto__", "any class name is a plain key")
        T.eq(D.build([a], [win("0x1", "c", 1), win("0x2", "c", 2)], look, { resolve: D.resolver([a], look) }).map(item => item.key),
             ["app:a", "app:c"], "a build with a kept resolver")

        // ---- the same list --------------------------------------------------------------
        const one = { key: "a" }, two = { key: "b" }
        T.ok(D.sameObjects([one, two], [one, two]) && D.sameObjects([], []), "entry for entry the same objects")
        T.ok(!D.sameObjects([one, two], [one, { key: "b" }]) && !D.sameObjects([one], [one, two]), "one new object, or one more: not")
        const keptOnce = Keyed.keep([], D.build([a], [win("0x1", "c", 1)], look), "key", { windows: "address" })
        T.ok(D.sameObjects(keptOnce, Keyed.keep(keptOnce, D.build([a], [win("0x1", "c", 1)], look), "key", { windows: "address" })),
             "an unchanged build kept: the previous list can be handed out again")

        // ---- each screen's own running apps --------------------------------------------
        T.eq(D.optionValue("runningOn", "screen"), "screen", "running apps of the dock's own screen")
        T.eq(D.optionValue("runningOn", "all"), "all", "or of every screen")
        T.eq(D.optionValue("runningOn", "some"), null, "nothing else")
        const spread = [win("0x1", "b", 1, { monitor: "DP-1" }), win("0x2", "c", 2, { monitor: "DP-2" })]
        T.eq(D.build([a, b], D.windowsOn(spread, "DP-2"), look).map(item => [item.key, item.running]),
             [["app:a", false], ["app:b", false], ["app:c", true]], "on DP-2: the pins, and the app with a window there")

        T.finish("DockTest")
    }
}
