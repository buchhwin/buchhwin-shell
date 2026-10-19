import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/shortcuts/ShortcutLogic.js" as S
import "../../services/shortcuts/ShellShortcuts.js" as Shell

// The keys of the neighbouring workspace, the zoom, the color filter, keep on
// top, the drop-down terminal and the keyboard passthrough: in the
// configuration, as the shell registers them, and as Settings > Shortcuts
// and the sheet read them in both dialects.
ShellRoot {
    FileView { id: lua; path: Qt.resolvedUrl("../../hypr/hyprland.lua").toString().replace("file://", ""); blockLoading: true }
    FileView { id: conf; path: Qt.resolvedUrl("../../hypr/keybinds.conf").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // Every new key starts where the configuration says, with its title.
        const defaults = S.parseDefaults(lua.text())
        const wanted = {
            "SUPER + Next": "Next workspace", "SUPER + Prior": "Previous workspace",
            "SUPER + SHIFT + Next": "Move window to the next workspace",
            "SUPER + SHIFT + Prior": "Move window to the previous workspace",
            "SUPER + mouse_down": "Next workspace", "SUPER + mouse_up": "Previous workspace",
            "SUPER + CTRL + T": "Keep window on top", "SUPER + code:49": "Drop-down terminal",
            "SUPER + plus": "Zoom in", "SUPER + minus": "Zoom out", "SUPER + 0": "Reset zoom",
            "SUPER + CTRL + C": "Color filter on or off", "SUPER + Escape": "Pass the keys to the window"
        }
        for (const combo of Object.keys(wanted)) {
            const found = defaults.find(item => item.combo === combo)
            T.eq(found ? found.description : null, wanted[combo], combo + " is a built-in shortcut")
            T.ok(S.titleGroups[wanted[combo]] !== undefined, wanted[combo] + " has a group")
        }
        // No two built-ins on one combination, the way out of the
        // passthrough aside (it is the same key, in its own submap).
        const canons = defaults.map(item => item.canon)
        T.eq(canons.filter((canon, index) => canons.indexOf(canon) !== index), [], "every built-in combination once")
        T.ok(/hl\.define_submap\("passthrough"[\s\S]*?keyFor\("SUPER \+ Escape"\), hl\.dsp\.submap\("reset"\)/.test(lua.text()),
             "the Lua passthrough's way out is bound in the submap itself, through the same keyFor")
        T.ok(/^submap = passthrough\nbind = SUPER, Escape, submap, reset\nsubmap = reset$/m.test(conf.text()),
             "and the conf's")
        // The hardware keys work in every submap, in both dialects.
        const hardware = lua.text().split("\n").filter(line => /hl\.bind\(keyFor\("(XF86|switch:)/.test(line))
        T.ok(hardware.length >= 15 && hardware.every(line => line.indexOf("submap_universal = true") >= 0),
             "every hardware key and the lid are bound for every submap in Lua")
        const confHardware = conf.text().split("\n").filter(line => /^bind\w* = , (XF86|switch:)/.test(line))
        T.ok(confHardware.length >= 15 && confHardware.every(line => /^bind\w*u\w* = /.test(line)), "and in the conf")

        // The shell's side: registered, parsed, offered.
        for (const action of ["workspaces next", "workspaces previous", "workspaces moveNext", "workspaces movePrevious",
                              "workspaces scroll down", "workspaces scroll up", "zoom increase", "zoom decrease", "zoom reset",
                              "colorFilter toggle", "window keepOnTop", "dropdown toggle"])
            T.ok(Shell.names().indexOf(Shell.nameOf(action)) >= 0, action + " is a registered shortcut")
        T.eq(Shell.parse("workspaces.scroll.down"), { target: "workspaces", fn: "scroll", args: ["down"] }, "the wheel's direction is a word")
        T.eq(Shell.names().filter((name, index, all) => all.indexOf(name) !== index), [], "no name twice")
        // The Citrix span has no key: IPC and the launcher's, and a command
        // shortcut of one's own (`buchhwin citrix span`) where it earns one.
        T.eq([Shell.bindable("citrix span"), Shell.names().indexOf("citrix.span")], [false, -1], "the Citrix span is no key")
        T.eq(S.shellTitle("citrix  span"), "Spread Citrix over the screens", "but has a title for one")

        // The conf dialect's rows carry no description: titles from the command.
        const ipc = "quickshell --path /p ipc call "
        const titles = [
            [ipc + "workspaces next || hyprctl dispatch workspace m+1", "Next workspace"],
            [ipc + "workspaces movePrevious || hyprctl dispatch movetoworkspace m-1", "Move window to the previous workspace"],
            [ipc + "workspaces scroll up || hyprctl dispatch workspace m-1", "Previous workspace"],
            [ipc + "zoom increase", "Zoom in"], [ipc + "zoom reset", "Reset zoom"],
            [ipc + "colorFilter toggle", "Color filter on or off"], [ipc + "window keepOnTop", "Keep window on top"],
            [ipc + "dropdown toggle || hyprctl dispatch togglespecialworkspace buchhwin-dropdown", "Drop-down terminal"],
            [ipc + "citrix span", "Spread Citrix over the screens"]
        ]
        for (const pair of titles) {
            const info = S.describe({ dispatcher: "exec", arg: pair[0] })
            T.eq([info.title, info.raw === true], [pair[1], false], pair[1] + " from the conf")
        }
        T.eq(S.describe({ dispatcher: "exec", arg: ipc + "workspaces next" }).group, "workspaces", "in its group")
        T.eq([S.describe({ dispatcher: "submap", arg: "passthrough" }).title, S.describe({ dispatcher: "submap", arg: "reset" }).title],
             ["Pass the keys to the window", "Give the keys back"], "the submap's two binds")

        // A key bound by its place reads as one, and is movable by it.
        const rows = S.rows([{ modmask: 64, key: "", keycode: 49, has_description: true, description: "Drop-down terminal" },
                             { modmask: 64, key: "Escape", has_description: true, description: "Give the keys back", submap: "passthrough" },
                             { modmask: 64, key: "Next", has_description: true, description: "Next workspace" },
                             { modmask: 64, key: "mouse_down", has_description: true, description: "Next workspace" }], [], null)
        T.eq(rows.map(row => row.combo), ["Super+^", "Super+Page Down", "Super+Scroll down"], "the rows, the submap's bind left out")
        T.eq(rows[0].key, "code:49", "the place's key, as the configuration writes it")
        T.eq(S.canonicalBind(rows[0].modmask, rows[0].key), S.canonicalCombo("SUPER + code:49"), "and the same combination as its default")
        T.eq(S.rowKeys(rows).length, new Set(S.rowKeys(rows)).size, "two rows with one title still have keys of their own")
        T.eq(S.grouped(rows, "").map(group => group.id), ["apps", "workspaces"], "in the apps and workspaces groups")
        T.eq(S.comboLabel("SUPER + code:49", true), "Super+^", "a hint names it")
        // The Lua dialect reports such a bind with no key and keycode 0.
        const luaRows = S.rows([{ modmask: 64, key: "", keycode: 0, has_description: true, description: "Drop-down terminal", dispatcher: "__lua" }], [], null)
        T.eq([luaRows[0].key, luaRows[0].combo], ["code:49", "Super+^"], "the Lua dialect's bind by place: its key from its description")
        T.eq(S.bindKey({ modmask: 64, key: "", keycode: 0, has_description: true, description: "Something else" }), "", "an unknown one stays empty")
        T.finish("KeyActionsTest")
    }
}
