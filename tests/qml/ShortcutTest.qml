import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/shortcuts/ShortcutLogic.js" as S

ShellRoot {
    // `hyprctl -j binds` of the nested sessions (legacy .conf and Lua config)
    // with synthetic paths plus a few extra binds.
    FileView { id: legacy; path: Qt.resolvedUrl("../fixtures/hypr-binds-legacy.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: lua; path: Qt.resolvedUrl("../fixtures/hypr-binds-lua.json").toString().replace("file://", ""); blockLoading: true }

    function row(list, combo) { return list.find(item => item.combo === combo) || null }
    function titles(groups, id) {
        const group = groups.find(item => item.id === id)
        return group ? group.rows.map(item => item.combo + " " + item.title) : []
    }

    Component.onCompleted: {
        // Modifiers and key names
        T.eq(S.modNames(65), ["SUPER", "SHIFT"], "modmask bits")
        T.eq(S.modmask(["SHIFT", "SUPER"]), 65, "modmask from names")
        T.eq(S.comboText(76, "F5"), "Super+Ctrl+Alt+F5", "combo text in display order")
        T.eq(S.keyLabel("RETURN"), "Enter", "Return is Enter")
        T.eq(S.keyLabel("XF86AudioRaiseVolume"), "Volume up", "known XF86 key")
        T.eq(S.keyLabel("XF86KbdLightOnOff"), "Kbd Light On Off", "other XF86 keys split")
        T.eq(S.keyLabel("mouse:272"), "Left drag", "mouse button")
        T.eq(S.keyLabel("switch:on:Lid Switch"), "Lid closed", "lid switch")
        T.eq(S.keyLabel("comma"), ",", "punctuation")
        T.eq(S.keyLabel("t"), "T", "single letters upper case")
        T.eq(S.parseBinds("not json"), [], "broken hyprctl output")

        // Legacy config: titles from dispatcher and argument
        const legacyBinds = S.parseBinds(legacy.text())
        const legacyRows = S.rows(legacyBinds, [], null)
        T.eq(legacyRows.length, 66, "submap binds skipped")
        T.eq(row(legacyRows, "Super+D").title, "Launcher", "ipc launcher")
        T.eq(row(legacyRows, "Super+D").group, "panels", "panel group")
        T.eq(row(legacyRows, "Super+B").title, "Web browser", "default browser")
        T.eq(row(legacyRows, "Super+Enter").group, "apps", "terminal group")
        T.eq(row(legacyRows, "Super+Q").title, "Close window", "killactive")
        T.eq(row(legacyRows, "Super+Left").title, "Resize window", "resizeactive")
        T.eq(row(legacyRows, "Super+3").title, "Go to workspace 3", "workspace")
        T.eq(row(legacyRows, "Super+Shift+3").title, "Move window to workspace 3", "movetoworkspacesilent")
        T.eq(row(legacyRows, "Super+Alt+Up").title, "Move focus up", "movefocus")
        T.eq(row(legacyRows, "Super+Left drag").title, "Move window", "mouse bind")
        T.eq(row(legacyRows, "Release Alt").title, "Switch to selected window", "release bind")
        T.eq(row(legacyRows, "Super+Shift+S").group, "screenshots", "screenshot group")
        T.eq([S.describeExec("quickshell --path /opt/b ipc call recording toggle region").title,
              S.describeExec("quickshell --path /opt/b ipc call recording toggle screen").title,
              S.describeExec("quickshell --path /opt/b ipc call recording toggle screen").group],
             ["Record a region", "Record the screen", "screenshots"], "recording binds")
        // The legacy `.conf` dialect carries no descriptions, so every title
        // has to be read back out of the command. Eighteen workspace binds and
        // six more landed in Other as raw command lines until these; the
        // titles are the ones `hyprland.lua` gives the same binds, so the two
        // dialects say the same thing.
        T.eq(S.describeExec("quickshell --path /opt/b ipc call workspaces switchTo 3 || hyprctl dispatch workspace 3"),
            { title: "Go to workspace 3", group: "workspaces" }, "a workspace switch keeps its number")
        T.eq(S.describeExec("quickshell --path /opt/b ipc call workspaces move 7 || hyprctl dispatch movetoworkspacesilent 7"),
            { title: "Move window to workspace 7", group: "workspaces" }, "and so does moving a window there")
        T.eq([S.describeExec("quickshell --path /opt/b ipc call shortcuts toggleSheet").title,
              S.describeExec("quickshell --path /opt/b ipc call profile toggle").title,
              S.describeExec("quickshell --path /opt/b ipc call wallpaperPicker toggle").title,
              S.describeExec("quickshell --path /opt/b ipc call colorPicker pick").title,
              S.describeExec("quickshell --path /opt/b ipc call desktop cycleMode").title,
              S.describeExec("quickshell --path /opt/b ipc call mode cycle").title],
            ["All keyboard shortcuts", "Profiles and modes", "Wallpaper picker",
             "Pick a colour off the screen", "Desktop mode: widgets, bar, notch",
             "Mode: minimal, work, gaming, laptop, docked"],
            "and the six surfaces that had no pattern at all")
        T.eq(S.describeExec("quickshell --path /opt/b ipc call shortcuts toggleSheet").group, "panels",
            "the sheet is a panel, not Other")

        T.eq([S.describeExec("quickshell --path /opt/b ipc call kbdBacklight up").title,
              S.describeExec("quickshell --path /opt/b ipc call kbdBacklight down").title,
              S.describeExec("quickshell --path /opt/b ipc call kbdBacklight toggle").title],
             ["Keyboard light up", "Keyboard light down", "Keyboard light on or off"],
             "the keyboard light keys are named, not shown as the call they make")
        T.eq(row(legacyRows, "Volume up").title, "Volume up", "volume key")
        T.eq(row(legacyRows, "Mute").title, "Mute audio", "mute key")
        T.eq(row(legacyRows, "Lid closed").group, "system", "lid switch group")
        T.eq(row(legacyRows, "Super+T").title, "notify-send hello", "unknown exec shows the command")
        T.ok(row(legacyRows, "Super+T").raw, "unknown exec marked raw")
        T.eq(row(legacyRows, "Super+G").title, "togglegroup", "unknown dispatcher raw")
        T.eq(row(legacyRows, "Super+Shift+F").group, "custom", "own bind by description")
        T.eq(row(legacyRows, "Super+Shift+F").title, "firefox", "own bind title")

        const legacyGroups = S.grouped(legacyRows, "")
        T.eq(legacyGroups.map(group => group.id), ["apps", "custom", "panels", "windows", "workspaces", "screenshots", "system", "other"], "group order")
        T.eq(titles(legacyGroups, "workspaces"), ["Super+1–9 Go to workspace 1–9", "Super+Shift+1–9 Move window to workspace 1–9"], "workspace rows condensed")
        T.ok(titles(legacyGroups, "windows").indexOf("Super+Arrows Resize window") >= 0, "arrow resize condensed")
        T.ok(titles(legacyGroups, "windows").indexOf("Super+Alt+Arrows Move focus") >= 0, "arrow focus condensed")
        T.eq(S.grouped(legacyRows, "screenshot").map(group => group.id), ["screenshots"], "search by title")
        T.eq(titles(S.grouped(legacyRows, "super+shift+s"), "screenshots"), ["Super+Shift+S Screenshot of the screen"], "search by combo")
        T.eq(S.grouped(legacyRows, "nothing matches this").length, 0, "empty search result")

        // Lua config: `__lua` binds carry descriptions
        const luaRows = S.rows(S.parseBinds(lua.text()), [], null)
        T.eq(row(luaRows, "Super+D").title, "Launcher", "Lua description")
        T.eq(row(luaRows, "Super+D").group, "panels", "Lua description group")
        T.eq(row(luaRows, "Super+Shift+3").group, "workspaces", "Lua workspace group")
        T.eq(row(luaRows, "Super+Alt+Left").group, "windows", "Lua focus group")
        T.eq(row(luaRows, "Super+Right drag").title, "Resize window", "Lua mouse bind")
        T.eq(row(luaRows, "Super+T").title, "Lua action", "Lua bind without description")
        T.eq(row(luaRows, "Super+Shift+F").group, "custom", "Lua own bind")
        const luaGroups = S.grouped(luaRows, "")
        T.eq(titles(luaGroups, "workspaces"), titles(legacyGroups, "workspaces"), "Lua and legacy workspaces match")
        T.eq(titles(luaGroups, "panels"), titles(legacyGroups, "panels"), "Lua and legacy panels match")

        // Custom shortcuts from the store
        const store = S.parseStore(JSON.stringify({ configVersion: 1, custom: [
            { mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" },
            { mods: ["shift", "super"], key: "f", command: "duplicate" },
            { mods: ["SUPER"], key: "T", command: "kitty --hold" },
            { mods: [], key: "T", command: "no modifier" },
            { mods: ["SHIFT"], key: "T", command: "shift only" },
            { mods: [], key: "F9", command: "notify-send nine" },
            { mods: ["SUPER"], key: "x", command: "a; b" },
            { mods: ["HYPER"], key: "x", command: "bad modifier" },
            { mods: ["SUPER"], key: "code:28", command: "keycode" },
            { mods: ["SUPER"], key: "Y", app: "bad id!" }
        ] }))
        T.eq(store, [
            { mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" },
            { mods: ["SUPER"], key: "T", command: "kitty --hold" },
            { mods: [], key: "F9", command: "notify-send nine" }
        ], "store validated and deduplicated")
        T.eq(S.parseStore("{"), [], "broken store")
        T.eq(S.parseStore(S.serializeStore(store)), store, "store round trip")
        T.eq(S.comboError(["SHIFT"], "A"), "Add Super, Ctrl or Alt to this key", "letters need a real modifier")
        T.eq(S.comboError([], "XF86Calculator"), "", "media keys alone")
        T.eq(S.commandError("echo a; echo b"), "Use && instead of ; or put the commands in a script", "semicolon refused")
        T.eq(S.commandError("echo a\necho b"), "Commands must be on one line", "newline refused")
        T.eq(S.commandError("  "), "Enter a command", "empty command")
        T.eq(S.commandFor(store[0], {}), "gtk-launch firefox", "apps via gtk-launch")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "T", app: "kitty" }, { kitty: "/opt/buchhwin-shell/scripts/launch-kitty.sh" }), "/opt/buchhwin-shell/scripts/launch-kitty.sh", "launcher override")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "T", app: "kitty" }, { kitty: "/opt/my shell/launch-kitty.sh" }), "'/opt/my shell/launch-kitty.sh'", "override path quoted")
        T.eq(S.descriptionFor({ command: "notify-send \"a, b\" # $HOME; x" }), "Custom: notify-send \"a b\" HOME x", "description without hyprlang separators")
        T.eq(S.conflictFor(legacyBinds, ["SUPER"], "d"), "Launcher", "conflict found case-insensitively")
        T.eq(S.conflictFor(legacyBinds, ["SUPER", "CTRL"], "D"), "", "free combination")
        T.eq(S.rows(legacyBinds, [{ mods: ["SUPER"], key: "T", command: "notify-send hello" }], entry => "Say hello").find(item => item.combo === "Super+T").title,
             "Say hello", "store entries name their rows")

        // Sync: bind missing entries, drop stale own binds, never touch config binds
        const plan = S.syncPlan(legacyBinds, [
            { mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" },
            { mods: ["SUPER", "CTRL"], key: "F5", command: "true" },
            { mods: ["SUPER"], key: "D", command: "taken" }
        ])
        T.eq(plan.bind, [{ mods: ["SUPER", "CTRL"], key: "F5", command: "true" }], "only missing entries bound")
        T.eq(plan.unbind, [], "matching own bind kept")
        T.eq(plan.conflicts, ["Super+D"], "config bind reported as conflict")
        const stale = S.syncPlan(legacyBinds, [])
        T.eq(stale.unbind, [{ mods: ["SUPER", "SHIFT"], key: "F" }], "removed entry unbound")
        const renamed = S.syncPlan(legacyBinds, [{ mods: ["SUPER", "SHIFT"], key: "F", command: "firefox --private-window" }])
        T.eq(renamed.unbind, [{ mods: ["SUPER", "SHIFT"], key: "F" }], "changed entry unbound")
        T.eq(renamed.bind.length, 1, "changed entry bound again")

        // Key capture (Qt key codes and modifier flags)
        T.eq(S.captureKey(0x54, 0x10000000 | 0x02000000, 36), { mods: ["SUPER", "SHIFT"], key: "T" }, "Super+Shift+T")
        T.eq(S.captureKey(0x01000000, 0, 9), { cancel: true }, "Escape cancels")
        T.eq(S.captureKey(0x01000022, 0x10000000, 133), { waiting: true, mods: ["SUPER"] }, "modifier alone waits")
        T.eq(S.captureKey(0x21, 0x10000000 | 0x02000000, 10), { mods: ["SUPER", "SHIFT"], key: "1" }, "shifted number row")
        T.eq(S.captureKey(0x01000004, 0x04000000 | 0x08000000, 36), { mods: ["CTRL", "ALT"], key: "Return" }, "named key")
        T.eq(S.captureKey(0x01000034, 0, 71), { mods: [], key: "F5" }, "function key")
        T.eq(S.captureKey(0x2c, 0x10000000, 59), { mods: ["SUPER"], key: "comma" }, "punctuation keysym")
        T.eq(S.captureKey(0x20ac, 0x10000000, 26), { unsupported: true, mods: ["SUPER"] }, "unknown key")

        // Columns for the Super+F1 sheet. A grid put a three-row group beside
        // an eleven-row one and left eight rows of nothing under the short
        // one; these are packed by weight instead, rows plus one heading.
        const sheet = [
            { id: "apps", rows: [1, 2, 3] },
            { id: "panels", rows: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] },
            { id: "windows", rows: [1, 2, 3, 4, 5, 6, 7, 8, 9] },
            { id: "system", rows: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] }
        ]
        const two = S.columnise(sheet, 2)
        T.eq(two.length, 2, "two columns asked for, two returned")
        const weigh = column => column.reduce((total, group) => total + group.rows.length + 1, 0)
        T.eq(two.map(weigh), [19, 22], "two columns come out level")
        T.eq(two[0].map(group => group.id), ["apps", "system"], "and each one reads in the declared order")
        T.eq(two[1].map(group => group.id), ["panels", "windows"], "not in the order they were placed")

        // Reading order alone would have put apps and windows together and
        // left panels with system: 14 rows against 27, which is the gap this
        // replaces.
        T.eq(Math.abs(weigh(two[0]) - weigh(two[1])) <= 3, true, "the two are within three rows of each other")

        const three = S.columnise(sheet, 3)
        T.eq(three.map(weigh), [15, 12, 14], "and three are level too")

        // The length is a promise: a sheet three wide with one group in it is
        // still three columns, so the caller can lay them out without
        // checking.
        T.eq(S.columnise([{ id: "apps", rows: [1] }], 3).map(column => column.length), [1, 0, 0], "empty columns are kept")
        T.eq(S.columnise([], 2).length, 2, "and so are all of them")
        T.eq(S.columnise(null, 2).length, 2, "nothing at all is not a crash")
        T.eq(S.columnise(sheet, 0).length, 1, "asking for no columns gives one")

        // A heading costs one row, which is what stops four groups of one
        // landing in a single column beside one group of four.
        const tiny = [{ rows: [1] }, { rows: [1] }, { rows: [1] }, { rows: [1] }]
        T.eq(S.columnise(tiny, 2).map(column => column.length), [2, 2], "singles are spread, not stacked")

        T.finish("ShortcutTest")
    }
}
