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
        T.eq(S.keyLabel("Caps_Lock"), "Caps Lock", "Caps Lock by its name, not its keysym")
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
        T.eq([S.describeExec("quickshell --path /opt/b ipc call dock toggle").title,
              S.describeExec("quickshell --path /opt/b ipc call dock toggle").group], ["Dock", "panels"],
             "the dock's key in the conf dialect, which has no description")
        T.eq(S.describeExec("/opt/b/scripts/screenshot.sh text"), { title: "Copy text from the screen", group: "screenshots" },
             "the screenshots' text mode (Super+Alt+T in the conf dialect)")
        T.eq(S.describeExec("quickshell --path /opt/b ipc call startMenu toggle"), { title: "Start menu", group: "panels" },
             "the start menu, once a key is put on it")
        T.eq(S.describeExec("quickshell --path /opt/b ipc call startMenu key"), { title: "Start menu", group: "panels" },
             "and its own key in the conf dialect")
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
             "Pick a color off the screen", "Desktop mode: widgets, bar, notch",
             "Mode: minimal, work, gaming, laptop, desk"],
            "and the six surfaces that had no pattern at all")
        T.eq(S.describeExec("quickshell --path /opt/b ipc call shortcuts toggleSheet").group, "panels",
            "the sheet is a panel, not Other")
        // scripts/launch-terminal.sh: the session's terminal, with or without
        // a command in it; the script's options are not the command.
        T.eq(S.describeExec("/opt/b/scripts/launch-terminal.sh"), { title: "Terminal", group: "apps" },
            "the terminal script alone opens the terminal")
        T.eq(S.describeExec("/opt/b/scripts/launch-terminal.sh -- htop"), { title: "htop in the terminal", group: "apps" },
            "a command in it is named by its program")
        T.eq(S.describeExec("/opt/b/scripts/launch-terminal.sh --hold --title 'Disk usage' --unit du-job -- /usr/bin/ncdu -x /").title,
            "ncdu in the terminal", "past --hold, --title and --unit, by the program's file name")
        T.eq(S.describeExec("'/opt/my shell/scripts/launch-terminal.sh' --hold btop").title, "btop in the terminal",
            "a quoted script path, and a command without --")
        T.eq(S.describeExec("/opt/b/scripts/launch-terminal.sh \"/opt/my tools/top\" -d 1").title, "top in the terminal",
            "a quoted program path")
        T.eq(S.describeExec("/opt/b/scripts/launch-terminal.sh --hold").title, "Terminal", "options alone: still the terminal")
        T.eq([S.describeExec("/opt/b/scripts/launch-alacritty.sh").title, S.describeExec("/opt/b/scripts/launch-kitty.sh").title],
            ["Alacritty", "Kitty"], "the two terminals' own launchers by name")
        T.eq(S.describeExec("/opt/b/scripts/launch-default.sh terminal").title, "Terminal", "Super+Enter is still the terminal")

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

        // Super+Ctrl+arrows arrange the windows: titled from movewindow (conf)
        // or the description (Lua), one row on the sheet either way.
        const arrange = ["LEFT", "RIGHT", "UP", "DOWN"]
        const confMoves = S.rows(arrange.map(key => ({ modmask: 68, key: key, dispatcher: "movewindow", arg: key[0].toLowerCase() })), [], null)
        T.eq(confMoves.map(item => item.title), ["Move window left", "Move window right", "Move window up", "Move window down"], "movewindow titles")
        T.eq(titles(S.grouped(confMoves, ""), "windows"), ["Super+Ctrl+Arrows Move window"], "window moves condensed")
        const luaMoves = S.rows(arrange.map(key => ({ modmask: 68, key: key, dispatcher: "__lua", arg: "", has_description: true,
                                                     description: "Move window " + key.toLowerCase() })), [], null)
        T.eq(titles(S.grouped(luaMoves, ""), "windows"), ["Super+Ctrl+Arrows Move window"], "Lua window moves condensed")
        T.eq(S.grouped(legacyRows, "screenshot").map(group => group.id), ["screenshots"], "search by title")
        T.eq(titles(S.grouped(legacyRows, "super+shift+s"), "screenshots"), ["Super+Shift+S Screenshot of the screen"], "search by combo")
        T.eq(S.grouped(legacyRows, "nothing matches this").length, 0, "empty search result")

        // Settings > Shortcuts keys its rows by these strings: one per row,
        // the same for the same row read again, and a narrower search keeps
        // the keys of the rows it still shows - so typing only takes rows
        // away.
        const allKeys = [].concat(...legacyGroups.map(group => S.rowKeys(group.rows)))
        T.eq(allKeys.length, new Set(allKeys).size, "every row has a key of its own")
        T.eq(S.rowKeys(S.grouped(S.rows(legacyBinds, [], null), "").find(group => group.id === "panels").rows),
             S.rowKeys(legacyGroups.find(group => group.id === "panels").rows), "a fresh read gives the same keys")
        const narrowed = S.grouped(legacyRows, "s")
        T.ok(narrowed.every(group => S.rowKeys(group.rows).every(key => allKeys.indexOf(key) >= 0)),
             "a narrower search keeps the keys of the rows it still shows")
        const twice = [{ group: "apps", combo: "Super+E", title: "Files" }, { group: "apps", combo: "Super+E", title: "Files" }]
        T.eq(S.rowKeys(twice), ["apps|Super+E|Files", "apps|Super+E|Files#2"], "one combination bound twice gets a count")
        T.eq(S.rowKeys(null), [], "no rows, no keys")

        // The conf dialect's push to talk and Caps Lock binds are the shell's
        // global shortcuts, and its microphone key goes through the shell.
        T.eq([S.describe({ dispatcher: "global", arg: "buchhwin:audio.talk" }),
              S.describe({ dispatcher: "global", arg: "buchhwin:osd.capsLock" }),
              S.describeExec("quickshell --path /opt/b ipc call audio micMute || wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")],
             [{ title: "Push to talk (hold)", group: "system" }, { title: "Caps Lock message", group: "system" },
              { title: "Mute microphone", group: "system" }], "push to talk, Caps Lock and the microphone key in the conf dialect")
        T.eq(S.describe({ dispatcher: "global", arg: "other:thing" }), { title: "global other:thing", group: "other", raw: true },
             "another program's global shortcut stays a raw line")

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
            { mods: ["SUPER"], key: "Y", app: "bad;id" },
            { mods: ["SUPER"], key: "U", app: "-x" },
            { mods: ["SUPER"], key: "R", app: "Citrix_subscribed_XenApp 7.x.RDS-Buchhwin $S101-255" },
            { mods: ["SUPER"], key: "S", shell: "startMenu key" },
            { mods: ["SUPER"], key: "V", shell: "launcher toggle" }
        ] }))
        T.eq(store, [
            { mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" },
            { mods: ["SUPER"], key: "T", command: "kitty --hold" },
            { mods: [], key: "F9", command: "notify-send nine" },
            { mods: ["SUPER"], key: "R", app: "Citrix_subscribed_XenApp 7.x.RDS-Buchhwin $S101-255" },
            { mods: ["SUPER"], key: "S", shell: "startMenu key" }
        ], "store validated and deduplicated: a Citrix id with spaces and `$` is kept, a shell action only from the offered ones")
        T.eq([S.validAppId("org.kde.dolphin"), S.validAppId("Citrix_subscribed_XenApp 7.x.RDS-Buchhwin $S101-255"),
              S.validAppId("a;b"), S.validAppId("a\nb"), S.validAppId("--unit"), S.validAppId("a/b"), S.validAppId(""), S.validAppId(3)],
             [true, true, false, false, false, false, false, false], "desktop ids a bind can carry")
        T.eq(S.shellActions(), [{ value: "startMenu key", label: "Start menu" }, { value: "assistant toggle", label: "Assistant" }],
             "the start menu and the assistant are offered as shell actions")
        T.eq(S.normalizeEntry({ mods: ["SUPER"], key: "S", shell: "startMenu toggle" }), { mods: ["SUPER"], key: "S", shell: "startMenu key" },
             "a shortcut stored with the old action is the key's")
        T.eq(S.entryLabel({ mods: ["SUPER"], key: "S", shell: "startMenu key" }), "Start menu", "a shell action named by its panel")
        T.eq(S.descriptionFor({ mods: ["SUPER"], key: "S", shell: "startMenu key" }), "Custom: Start menu", "and described so")
        T.eq(S.parseStore("{"), [], "broken store")
        T.eq(S.parseStore(S.serializeStore(store)), store, "store round trip")
        // The watch reads back every save of the service's own (pitfall 77):
        // that text is the list it holds, and parsed again it rebuilt every
        // row and ran one more `hyprctl -j binds`.
        const saved = S.serializeStore(store)
        T.eq(S.storeReadIsNews(true, saved, saved), false, "the store's own write read back is no news")
        T.eq(S.storeReadIsNews(true, S.serializeStore([]), saved), true, "another program's write is")
        T.eq(S.storeReadIsNews(true, "  \n", saved), false, "an empty read while the file is replaced is not")
        T.eq(S.storeReadIsNews(false, "", ""), true, "and before the first read every answer is")
        T.eq(S.storeReadIsNews(false, saved, saved), true, "even one that matches")
        T.eq(S.comboError(["SHIFT"], "A"), "Add Super, Ctrl or Alt to this key", "letters need a real modifier")
        T.eq(S.comboError([], "XF86Calculator"), "", "media keys alone")
        T.eq(S.commandError("echo a; echo b"), "Use && instead of ; or put the commands in a script", "semicolon refused")
        T.eq(S.commandError("echo a\necho b"), "Commands must be on one line", "newline refused")
        T.eq(S.commandError("  "), "Enter a command", "empty command")
        // An app starts the way the launcher starts it (LaunchLogic), not by
        // a bare gtk-launch: a web app past launch-brave.sh came up without
        // the wallet (pitfalls 32, 98), and GLib knows no terminal installed
        // here, so a Terminal=true entry started nothing.
        const script = name => "/s/" + name
        const overrides = { "kitty": "launch-kitty.sh", "brave-browser": "launch-brave.sh" }
        const start = app => ({ app: app, overrides: overrides, script: script })
        const outlook = { id: "brave-faolnafnngnfdaknnbpnkhgohbobgegn-Default",
            command: ["/opt/brave-bin/brave", "--profile-directory=Default", "--app-id=faolnafnngnfdaknnbpnkhgohbobgegn"] }
        T.eq(S.commandFor({ mods: ["SUPER"], key: "O", app: outlook.id }, start(outlook)),
             "/s/launch-brave.sh --profile-directory=Default --app-id=faolnafnngnfdaknnbpnkhgohbobgegn",
             "a Brave web app through launch-brave.sh")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "H", app: "htop" }, start({ id: "htop", command: ["htop"], runInTerminal: true })),
             "/s/launch-terminal.sh -- htop", "a Terminal=true entry in the session's terminal")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "T", app: "kitty" }, start({ id: "kitty", command: ["kitty"] })),
             "/s/launch-kitty.sh", "an override's session launcher")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "T", app: "kitty" }, { app: { id: "kitty", command: ["kitty"] }, overrides: overrides,
                                                                       script: name => "/opt/my shell/" + name }),
             "'/opt/my shell/launch-kitty.sh'", "a script path with a space quoted")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "G", app: "game" }, start({ id: "game", command: ["./run", "--level=2"], workingDirectory: "/opt/my game" })),
             "cd -- '/opt/my game' && /s/launch-app.sh game ./run --level=2", "the entry's Path= first, as the launcher passes it")
        const citrixId = "Citrix_subscribed_XenApp 7.x.RDS-Buchhwin $S101-255"
        T.eq(S.commandFor({ mods: ["SUPER"], key: "R", app: citrixId },
                          start({ id: citrixId, command: ["/opt/Citrix/ICAClient/util/storebrowse", "-L", "XenApp 7.x.RDS-Buchhwin $S101-255", "it's"] })),
             "/s/launch-app.sh 'Citrix_subscribed_XenApp 7.x.RDS-Buchhwin '\"$\"'S101-255' /opt/Citrix/ICAClient/util/storebrowse -L "
             + "'XenApp 7.x.RDS-Buchhwin '\"$\"'S101-255' 'it'\\''s'",
             "spaces, quotes and `$` quoted for sh; the `$` outside the quotes, where the conf dialect's ${NAME} reads the same")
        T.eq(S.commandFor({ mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" }, { app: null, overrides: overrides, script: script }),
             "/s/launch-app.sh firefox gtk-launch firefox", "an id the desktop entries do not know: gtk-launch, in a unit of its own")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "X", app: "dbus-only" }, start({ id: "dbus-only", command: [] })),
             "/s/launch-app.sh dbus-only gtk-launch dbus-only", "an entry without a command line the same")
        // A shell action's bind is the global shortcut itself, like the
        // built-in keys: pressed and released, and the shell acts on the press.
        const startMenu = { mods: ["SUPER", "ALT"], key: "S", shell: "startMenu key" }
        T.eq(S.globalBind(startMenu), {
            legacy: "keyword bindd SUPER ALT,S,Custom: Start menu,global,buchhwin:startMenu.key", legacyEmpty: [],
            lua: "hl.bind(\"SUPER + ALT + S\", hl.dsp.global(\"buchhwin:startMenu.key\"), { description = \"Custom: Start menu\" })" },
             "a shell action binds its global shortcut in both dialects")
        T.eq(S.commandFor(startMenu, {}), "global buchhwin:startMenu.key", "and is remembered by it")
        T.throwsError(() => S.globalBind({ mods: ["SUPER"], key: "S", shell: "launcher toggle" }), "only the offered actions")
        T.throwsError(() => S.globalBind({ mods: ["SUPER"], key: "S,exec", shell: "startMenu key" }), "the key checked as for any bind")
        T.eq(S.commandFor({ mods: ["SUPER"], key: "T", command: "kitty --hold" }, start(null)), "kitty --hold", "a command as typed")
        T.eq([S.shellWord("plain-word_1.2,x=y:z@%+/"), S.shellWord(""), S.shellWord("a b"), S.shellWord("~/x"), S.shellWord("#x")],
             ["plain-word_1.2,x=y:z@%+/", "''", "'a b'", "'~/x'", "'#x'"], "only plain words stay bare")
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
        // A bind with the right name may run an older command line (an older
        // shell's gtk-launch, or one made before the desktop entries were
        // read): bound again, and only that one.
        const outdated = S.syncPlan(legacyBinds, [{ mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" }], entry => false)
        T.eq([outdated.unbind, outdated.bind], [[{ mods: ["SUPER", "SHIFT"], key: "F" }], [{ mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" }]],
             "an outdated bind is unbound and bound again")
        const current = S.syncPlan(legacyBinds, [{ mods: ["SUPER", "SHIFT"], key: "F", app: "firefox" }], entry => true)
        T.eq([current.unbind, current.bind], [[], []], "a current one is left alone")
        T.eq(S.syncPlan(legacyBinds, [{ mods: ["SUPER"], key: "D", command: "taken" }], entry => false).conflicts, ["Super+D"],
             "and a config bind on the combination stays a conflict, never unbound")

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
