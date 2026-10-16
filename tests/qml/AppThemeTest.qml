import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/AppThemeLogic.js" as A

ShellRoot {
    Component.onCompleted: {
        // Effective theme.
        T.eq([A.effectiveDark("dark", 12), A.effectiveDark("light", 23), A.effectiveDark("auto", 12)], [true, false, false], "fixed themes and daytime")
        T.eq([A.effectiveDark("auto", 19), A.effectiveDark("auto", 6), A.effectiveDark("auto", 7), A.effectiveDark("auto", 18)],
             [true, true, false, false], "automatic switches at 19:00 and 07:00")

        // Parsing tool output.
        T.eq([A.unquote("'prefer-dark'\n"), A.unquote("\"Breeze\""), A.unquote("default"), A.unquote(undefined)],
             ["prefer-dark", "Breeze", "default", ""], "gsettings quotes")
        const listed = A.parseSchemes("You have the following color schemes on your system:\n * BreezeClassic\n * BreezeDark\n"
                                      + " * BreezeLight (current color scheme)\n * Nordic Blue\n")
        T.eq(listed, { schemes: ["BreezeClassic", "BreezeDark", "BreezeLight", "Nordic Blue"], current: "BreezeLight" }, "scheme list with the current one")
        T.eq(A.parseSchemes(""), { schemes: [], current: "" }, "no schemes")
        T.eq(A.parseRange("enum\n'default'\n'prefer-dark'\n'prefer-light'\n"), ["default", "prefer-dark", "prefer-light"], "gsettings range")

        const queryText = "[tools]\n/usr/bin/plasma-apply-colorscheme\n/usr/bin/gsettings\n[colorScheme]\n\n"
            + "[schemes]\nYou have the following color schemes on your system:\n * BreezeDark\n * BreezeLight (current color scheme)\n"
            + "[gtkColorScheme]\n'prefer-dark'\n[colorSchemeRange]\nenum\n'default'\n'prefer-dark'\n'prefer-light'\n"
            + "[gtkTheme]\n'adw-gtk3-dark'\n[themes]\n/usr/share/themes/Breeze/gtk-3.0/gtk.css\n/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css\n"
            + "/home/u/.local/share/themes/Breeze/gtk-3.0/gtk.css\nnot a theme\n"
        const query = A.parseQuery(queryText)
        T.eq(query, { plasma: true, gsettings: true, colorScheme: "BreezeLight", accentColor: "", kdeColors: null,
                      schemes: ["BreezeDark", "BreezeLight"], gtkColorScheme: "prefer-dark", colorSchemeRange: ["default", "prefer-dark", "prefer-light"],
                      gtkTheme: "adw-gtk3-dark", themes: ["Breeze", "Breeze-Dark"], iconTheme: "", icons: [], gtk: null },
             "query: empty kdeglobals key uses the listed current scheme")
        T.eq(A.parseQuery("[colorScheme]\nBreezeDark\n[schemes]\n * BreezeLight (current color scheme)\n").colorScheme, "BreezeDark", "kdeglobals key wins")
        const bare = A.parseQuery("")
        T.eq([bare.plasma, bare.gsettings, bare.colorScheme, bare.gtkTheme, bare.themes], [false, false, "BreezeLight", "", []], "tools missing")

        // Targets.
        T.eq([A.colorSchemeTarget(true, ["BreezeDark", "BreezeLight"]), A.colorSchemeTarget(false, ["BreezeDark", "BreezeLight"]),
              A.colorSchemeTarget(true, ["BreezeLight"]), A.colorSchemeTarget(false, null)],
             ["BreezeDark", "BreezeLight", "", ""], "colour scheme only when installed")
        T.eq([A.gtkColorSchemeTarget(true, []), A.gtkColorSchemeTarget(false, ["default", "prefer-dark", "prefer-light"]),
              A.gtkColorSchemeTarget(false, ["default", "prefer-dark"]), A.gtkColorSchemeTarget(false, [])],
             ["prefer-dark", "prefer-light", "default", "prefer-light"], "GNOME color-scheme values")
        const installed = ["Breeze", "Breeze-Dark", "adw-gtk3"]
        T.eq([A.isDarkThemeName("Breeze-Dark"), A.isDarkThemeName("adw-gtk3-dark"), A.isDarkThemeName("Breeze"), A.isDarkThemeName("Darkish")],
             [true, true, false, false], "dark theme names")
        T.eq([A.gtkThemeTarget("adw-gtk3-dark", true, installed), A.gtkThemeTarget("adw-gtk3-dark", false, installed),
              A.gtkThemeTarget("adw-gtk3", true, installed)],
             ["adw-gtk3-dark", "adw-gtk3", "Breeze-Dark"], "same family when installed, keep a matching theme")
        T.eq([A.gtkThemeTarget("Adwaita", true, []), A.gtkThemeTarget("Adwaita-dark", false, []), A.gtkThemeTarget("Breeze", true, installed)],
             ["Adwaita-dark", "Adwaita", "Breeze-Dark"], "built-in Adwaita and Breeze variants")
        T.eq([A.gtkThemeTarget("Clearlooks", true, installed), A.gtkThemeTarget("Clearlooks", true, []), A.gtkThemeTarget("", false, installed),
              A.gtkThemeTarget("Material-dark", false, [])],
             ["Breeze-Dark", "", "Breeze", ""], "Breeze fallback or no change")
        T.eq(A.targets(true, query), { colorScheme: "BreezeDark", gtkColorScheme: "prefer-dark", gtkTheme: "adw-gtk3-dark", iconTheme: "" }, "dark targets")
        T.eq(A.targets(false, query), { colorScheme: "BreezeLight", gtkColorScheme: "prefer-light", gtkTheme: "Breeze", iconTheme: "" }, "light targets")
        T.eq(A.targets(true, bare), { colorScheme: "", gtkColorScheme: "", gtkTheme: "", iconTheme: "" }, "no tools, no targets")

        // Commands skip values that already match.
        T.eq(A.commandsFor(A.targets(true, query), query), [["plasma-apply-colorscheme", "BreezeDark"]], "dark: only the KDE scheme differs")
        T.eq(A.commandsFor(A.targets(false, query), query),
             [["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-light"],
              ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "Breeze"]], "light: GNOME keys differ")
        T.eq(A.commandsFor({ colorScheme: "BreezeLight", gtkColorScheme: "", gtkTheme: "x" }, null),
             [["plasma-apply-colorscheme", "BreezeLight"], ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "x"]], "no current: all set values")
        T.eq(A.commandsFor(null, query), [], "nothing to set")
        const simulated = A.afterCommands(query, A.commandsFor(A.targets(false, query), query))
        T.eq([simulated.colorScheme, simulated.gtkColorScheme, simulated.gtkTheme, simulated.themes],
             ["BreezeLight", "prefer-light", "Breeze", ["Breeze", "Breeze-Dark"]], "simulated values after commands")
        T.eq([A.afterCommands(query, [])], [query], "no commands, same values")

        // State file.
        T.eq(A.snapshot(query), { colorScheme: "BreezeLight", accentColor: "", kdeColors: null, gtkColorScheme: "prefer-dark", gtkTheme: "adw-gtk3-dark",
                                  iconTheme: "", gtk: null }, "snapshot")
        T.eq(A.snapshot(bare), { colorScheme: "", accentColor: "", kdeColors: null, gtkColorScheme: "", gtkTheme: "", iconTheme: "", gtk: null }, "snapshot without tools")
        T.eq([A.parseState(""), A.parseState("{broken"), A.parseState("[]"), A.parseState("null")],
             [A.emptyState(), A.emptyState(), A.emptyState(), A.emptyState()], "unreadable state files")
        const saved = { colorScheme: "BreezeLight", accentColor: "", kdeColors: null, gtkColorScheme: "prefer-dark", gtkTheme: "adw-gtk3-dark",
                        iconTheme: "", gtk: null }
        const parsed = A.parseState(JSON.stringify({ version: 1, applied: true, restoreOnLogout: false, saved: saved,
                                                     restore: [["rm", "-rf", "/"]] }))
        T.eq(parsed.applied, true, "applied state")
        T.eq(parsed.restoreOnLogout, false, "logout preference")
        T.eq(parsed.saved, saved, "saved values")
        T.eq(parsed.restore, A.commandsFor(saved, null), "restore commands rebuilt from the saved values, not trusted (no backup: saved scheme)")
        T.eq(A.parseState(JSON.stringify({ applied: true, saved: { colorScheme: 3 } })).applied, false, "applied without values")
        T.eq(A.parseState(JSON.stringify({ applied: "yes", saved: saved })).applied, false, "applied must be true")
        T.eq(A.parseState(A.stateText(parsed)), parsed, "state text round trip")

        // Plans (states without a colour backup keep the scheme restore).
        const follow = (dark, restoreOnLogout) => ({ followTheme: true, accentEnabled: false, accent: "#4f8ff7", dark: dark, restoreOnLogout: restoreOnLogout })
        const off = (restoreOnLogout) => ({ followTheme: false, accentEnabled: false, accent: "#4f8ff7", dark: false, restoreOnLogout: restoreOnLogout })
        const first = A.plan(follow(true, true), query, A.emptyState())
        T.eq(first.action, "apply", "enable: apply")
        T.eq(first.commands, [["plasma-apply-colorscheme", "BreezeDark"], A.NOTIFY_COMMAND], "enable: commands")
        T.eq(first.state.saved, saved, "enable: current values saved")
        T.eq([first.state.applied, first.state.restoreOnLogout], [true, true], "enable: applied, restore at logout")
        T.eq(first.state.restore, A.commandsFor(saved, null), "enable: restore commands")

        // Later changes keep the first snapshot, even when the values moved.
        const afterDark = A.parseQuery(queryText.replace("[colorScheme]\n\n", "[colorScheme]\nBreezeDark\n"))
        const second = A.plan(follow(false, false), afterDark, first.state)
        T.eq(second.state.saved, saved, "theme change keeps the saved values")
        T.eq(second.state.restoreOnLogout, false, "logout preference follows the setting")
        T.eq(second.commands[0], ["plasma-apply-colorscheme", "BreezeLight"], "light again")
        T.eq(second.commands.length, 4, "light: scheme, both GNOME keys and the notify signal")

        // Turning the option off restores exactly the saved values that differ.
        const disabled = A.plan(off(true), afterDark, first.state)
        T.eq(disabled.action, "restore", "disable: restore")
        T.eq(disabled.commands, [["plasma-apply-colorscheme", "BreezeLight"]], "disable: only changed values restored")
        T.eq([disabled.state.applied, disabled.state.saved, disabled.state.restore], [false, null, []], "disable: state forgotten")
        const idle = A.plan(off(true), query, disabled.state)
        T.eq([idle.action, idle.commands], ["none", []], "off and nothing applied: nothing to do")
        T.eq(A.plan(off(true), null, A.emptyState()).action, "none", "off without a query")

        // A snapshot without any tool is not remembered.
        const noTools = A.plan(follow(true, true), bare, A.emptyState())
        T.eq([noTools.commands, noTools.state.applied, noTools.state.saved], [[], false, null], "no tools: nothing saved")

        // Colours and the kdeglobals colour backup.
        T.eq([A.colorToHex("61,174,233"), A.colorToHex("61,174,233,255"), A.colorToHex("#4F8FF7"), A.colorToHex("300,0,0"), A.colorToHex(""), A.colorToHex("blue")],
             ["#3daee9", "#3daee9", "#4f8ff7", "", "", ""], "kdeglobals colours to hex")
        T.eq([A.hexToRgb("#E7B43C"), A.hexToRgb("nope")], ["231,180,60", ""], "hex to kdeglobals colours")
        T.eq([A.managedEntry(["General"], "AccentColor"), A.managedEntry(["General"], "BrowserApplication"), A.managedEntry(["KDE"], "frameContrast"),
              A.managedEntry(["KFileDialog Settings"], "Sort by"), A.managedEntry(["Colors:Header", "Inactive"], "BackgroundNormal"),
              A.managedEntry(["WM", "Sub"], "x"), A.managedEntry(["Colors:View"], "Foo[de]"), A.managedEntry(["ColorEffects:Disabled"], "Color")],
             [true, false, true, false, true, false, false, true], "managed kdeglobals entries")
        const entries = [[["Colors:Button"], "DecorationFocus", "61,174,233"], [["Colors:Header", "Inactive"], "BackgroundNormal", "32,35,38"],
                         [["ColorEffects:Disabled"], "Enable", ""], [["General"], "ColorSchemeHash", "0efb"], [["WM"], "activeBackground", "39,44,49"]]
        const backup = { entries: entries }
        T.eq(A.parseSnapshot(JSON.stringify({ entries: entries.concat([[["General"], "TerminalApplication", "kitty"], [["WM"], "x", "a\\b"], "junk"]) })),
             backup, "snapshot keeps only valid colour entries")
        T.eq([A.parseSnapshot(""), A.parseSnapshot("{"), A.parseSnapshot("{\"entries\": 3}")], [null, null, null], "no snapshot")
        const plasmaText = "[tools]\n/usr/bin/plasma-apply-colorscheme\n/usr/bin/gsettings\n[colorScheme]\nBreezeDark\n[accentColor]\n\n"
            + "[kdeColors]\n" + JSON.stringify(backup) + "\n[schemes]\n * BreezeDark\n * BreezeLight (current color scheme)\n"
            + "[gtkColorScheme]\n'prefer-dark'\n[colorSchemeRange]\nenum\n'default'\n'prefer-dark'\n'prefer-light'\n[gtkTheme]\n'Breeze-Dark'\n"
            + "[themes]\n/usr/share/themes/Breeze/gtk-3.0/gtk.css\n/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css\n"
        const plasma = A.parseQuery(plasmaText)
        T.eq([plasma.colorScheme, plasma.accentColor, plasma.kdeColors], ["BreezeDark", "", backup], "query with Plasma's scheme, no accent and the backup")
        T.eq(A.parseQuery("[accentColor]\n231,180,60\n").accentColor, "#e7b43c", "accent from kdeglobals")

        const del = (group, key) => ["kwriteconfig6", "--file", "kdeglobals"].concat(group.reduce((list, part) => list.concat(["--group", part]), []), ["--key", key, "--delete", "--", ""])
        const write = (group, key, value) => ["kwriteconfig6", "--file", "kdeglobals"].concat(group.reduce((list, part) => list.concat(["--group", part]), []), ["--key", key, "--", value])
        T.eq(A.kdeRestoreCommands(backup, backup), [], "backup unchanged: nothing to restore")
        const changed = { entries: [[["Colors:Button"], "DecorationFocus", "231,180,60"], [["General"], "AccentColor", "231,180,60"],
                                    [["Colors:Header", "Inactive"], "BackgroundNormal", "32,35,38"], [["WM"], "activeBackground", "-0.5"]] }
        T.eq(A.kdeRestoreCommands(backup, changed),
             [del(["General"], "AccentColor"), write(["Colors:Button"], "DecorationFocus", "61,174,233"), write(["ColorEffects:Disabled"], "Enable", ""),
              write(["General"], "ColorSchemeHash", "0efb"), write(["WM"], "activeBackground", "39,44,49"), A.NOTIFY_COMMAND],
             "restore deletes added entries, writes changed and missing ones, then notifies")
        T.eq(A.kdeRestoreCommands(null, changed), [], "no backup, no kwriteconfig6")

        // Accent only: the current scheme keeps, only the accent is applied.
        const accentOpts = (accent, followTheme, dark) => ({ followTheme: followTheme === true, accentEnabled: true, accent: accent, dark: dark !== false, restoreOnLogout: true })
        const a1 = A.plan(accentOpts("#E7B43C"), plasma, A.emptyState())
        T.eq([a1.action, a1.commands, a1.error], ["apply", [["plasma-apply-colorscheme", "--accent-color", "#e7b43c"], A.NOTIFY_COMMAND], ""], "accent on: accent for the current scheme")
        T.eq([a1.state.applied, a1.state.saved.colorScheme, a1.state.saved.accentColor, a1.state.saved.kdeColors], [true, "BreezeDark", "", backup], "accent on: backup saved first")
        T.ok(a1.state.restore.every(command => command[0] === "gsettings"), "with a backup the state lists no scheme restore")
        const afterA1 = A.afterCommands(plasma, a1.commands, a1.state.saved)
        T.eq([afterA1.colorScheme, afterA1.accentColor], ["BreezeDark", "#e7b43c"], "simulated accent")
        T.eq(A.plan(accentOpts("#e7b43c"), afterA1, a1.state).commands, [], "same accent: nothing to run")
        const a2 = A.plan(accentOpts("#62d394"), afterA1, a1.state)
        T.eq([a2.commands, a2.state.saved], [[["plasma-apply-colorscheme", "--accent-color", "#62d394"], A.NOTIFY_COMMAND], a1.state.saved], "accent change keeps the first backup")
        T.eq(A.plan(accentOpts("blue"), plasma, A.emptyState()).action, "none", "invalid accent counts as off")

        // An unknown scheme must not swallow the accent, and a missing
        // plasma-apply-colorscheme has to say so instead of doing nothing.
        const noScheme = Object.assign({}, plasma, { colorScheme: "", schemes: [] })
        T.eq(A.plan(accentOpts("#e7b43c"), noScheme, A.emptyState()).commands,
             [["plasma-apply-colorscheme", "--accent-color", "#e7b43c"], A.NOTIFY_COMMAND],
             "no known scheme: the accent alone is applied")
        const followNoScheme = A.plan(accentOpts("#e7b43c", true, false), noScheme, A.emptyState())
        T.ok(followNoScheme.commands.some(command => command[1] === "--accent-color"),
             "theme without a matching scheme still applies the accent")
        const noPlasma = Object.assign({}, plasma, { plasma: false })
        const missing = A.plan(accentOpts("#e7b43c"), noPlasma, A.emptyState())
        T.eq([missing.commands.length, missing.error.length > 0], [0, true], "without plasma-apply-colorscheme the plan explains itself")

        // Accent with the theme: one command for scheme and accent.
        const a3 = A.plan(accentOpts("#e7b43c", true, false), afterA1, a1.state)
        T.eq(a3.commands[0], ["plasma-apply-colorscheme", "--accent-color", "#e7b43c", "BreezeLight"], "theme and accent together")
        T.eq(a3.commands.length, 4, "light: plus both GNOME keys and the notify signal")
        const afterA3 = A.afterCommands(afterA1, a3.commands, a3.state.saved)

        // Accent off while the theme still follows: Plasma had no accent, so the
        // backup comes back first, then the followed scheme without an accent.
        const a4 = A.plan(follow(false, true), afterA3, a3.state)
        T.eq(a4.commands, [del(["General"], "ColorScheme"), del(["General"], "AccentColor"), A.NOTIFY_COMMAND,
                           ["plasma-apply-colorscheme", "BreezeLight"], A.NOTIFY_COMMAND], "accent off: restore the backup, then the scheme")
        const afterA4 = A.afterCommands(afterA3, a4.commands, a4.state.saved)
        T.eq([afterA4.colorScheme, afterA4.accentColor], ["BreezeLight", ""], "simulated after accent off")

        // Everything off: exactly the backup and the GNOME keys come back.
        const a5 = A.plan(off(true), afterA3, a3.state)
        T.eq(a5.action, "restore", "all off: restore")
        T.eq(a5.commands, [del(["General"], "ColorScheme"), del(["General"], "AccentColor"), A.NOTIFY_COMMAND,
                           ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"],
                           ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "Breeze-Dark"]], "all off: backup and GNOME keys")
        T.eq([a5.state.applied, a5.state.saved], [false, null], "all off: forgotten")
        const afterA5 = A.afterCommands(afterA3, a5.commands, a3.state.saved)
        T.eq([afterA5.colorScheme, afterA5.accentColor, afterA5.kdeColors], ["BreezeDark", "", backup], "simulated restore gives the saved values")

        // A Plasma accent of its own is kept when only the theme follows.
        const ownAccent = A.parseQuery(plasmaText.replace("[accentColor]\n\n", "[accentColor]\n233,100,60\n"))
        T.eq(A.plan(follow(false, true), ownAccent, A.emptyState()).commands[0],
             ["plasma-apply-colorscheme", "--accent-color", "#e9643c", "BreezeLight"], "theme keeps Plasma's accent")

        // No backup: the accent is not applied.
        const noBackup = A.parseQuery(plasmaText.replace(/\[kdeColors\]\n.*\n/, "[kdeColors]\n\n"))
        const a6 = A.plan(accentOpts("#e7b43c"), noBackup, A.emptyState())
        T.eq([a6.commands, a6.error.length > 0], [[], true], "no backup: accent refused")

        // State file with a backup.
        const withBackup = A.parseState(A.stateText(a1.state))
        T.eq(withBackup, a1.state, "backup state round trip")
        T.eq(A.parseState(JSON.stringify({ applied: true, saved: Object.assign({}, a1.state.saved, { kdeColors: { entries: [[["General"], "BrowserApplication", "x"]] } }) })).saved.kdeColors,
             { entries: [] }, "backup entries validated on load")

        // Plasma autostart safety net.
        const entry = A.autostartEntry("/home/u/.local/share/buchhwin-shell/scripts/apptheme-restore.py")
        T.ok(entry.indexOf("\nOnlyShowIn=KDE;\n") >= 0 && entry.indexOf("\nExec=python3 \"/home/u/.local/share/buchhwin-shell/scripts/apptheme-restore.py\"\n") >= 0,
             "autostart entry only for Plasma")
        T.eq(A.execQuote("/a b/$x\"`\\"), "\"/a b/\\$x\\\"\\`\\\\\"", "Exec quoting")

        // GTK apps (round 12): GTK 3 takes the dark variant from
        // settings.ini, not from gsettings, and the Breeze theme draws with
        // the colours of the user's gtk.css, which Plasma's kded wrote for
        // BreezeDark and nothing rewrites here - GTK apps stayed dark when
        // the shell went light. The live files of this machine, as
        // --gtk-snapshot prints them.
        const gtkNow = { "gtk-3.0": { preferDark: "true", iconTheme: "breeze-dark", colorsImport: true, colorsDark: true },
                         "gtk-4.0": { preferDark: "true", iconTheme: "breeze-dark", colorsImport: true, colorsDark: true } }
        const gtkText = plasmaText + "[iconTheme]\n'breeze-dark'\n[icons]\n/usr/share/icons/breeze/index.theme\n/usr/share/icons/breeze-dark/index.theme\n"
            + "/usr/share/icons/Adwaita/index.theme\n[gtk]\n" + JSON.stringify(gtkNow) + "\n"
        const gtkQuery = A.parseQuery(gtkText)
        T.eq([gtkQuery.iconTheme, gtkQuery.icons, gtkQuery.gtk], ["breeze-dark", ["breeze", "breeze-dark", "Adwaita"], gtkNow],
             "query: the icon theme, the installed ones and the GTK files")
        T.eq(A.parseGtk(JSON.stringify({ "gtk-3.0": { preferDark: "a\nb", iconTheme: null, colorsImport: "yes" }, "gtk-5.0": { preferDark: "true" } })),
             { "gtk-3.0": { iconTheme: null } }, "GTK snapshot validated: no other folders, no multi-line values")
        T.eq([A.parseGtk(""), A.parseGtk("{}"), A.parseGtk("{")], [null, null, null], "no GTK files")
        T.eq([A.iconThemeTarget("breeze-dark", false, ["breeze", "breeze-dark"]), A.iconThemeTarget("breeze", true, ["breeze", "breeze-dark"]),
              A.iconThemeTarget("Papirus", true, ["breeze-dark"]), A.iconThemeTarget("breeze-dark", false, []), A.iconThemeTarget("", true, ["breeze-dark"])],
             ["breeze", "breeze-dark", "Papirus", "breeze-dark", ""], "an icon theme follows only to its own other variant")
        T.eq([A.preferDarkValue("true"), A.preferDarkValue("1"), A.preferDarkValue("false"), A.preferDarkValue(null)], [true, true, false, false],
             "settings.ini's dark variant")
        const helper = (dir, values) => [A.GTK_HELPER, "--gtk", dir, JSON.stringify(values)]
        const lightGtk = A.plan(follow(false, true), gtkQuery, A.emptyState())
        T.eq(lightGtk.commands.filter(command => command[0] === A.GTK_HELPER || command[3] === "icon-theme"),
             [["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "breeze"],
              helper("gtk-3.0", { preferDark: "false", iconTheme: "breeze", colorsImport: false }),
              helper("gtk-4.0", { preferDark: "false", iconTheme: "breeze", colorsImport: false })],
             "light: the light icons, no dark variant, and the dark colors.css left out")
        T.eq([lightGtk.state.saved.iconTheme, lightGtk.state.saved.gtk], ["breeze-dark", gtkNow], "the GTK values saved before they change")
        T.ok(A.sameCommand(lightGtk.commands[lightGtk.commands.length - 1], A.NOTIFY_COMMAND), "the palette signal still comes last")
        const afterLight = A.afterCommands(gtkQuery, lightGtk.commands, lightGtk.state.saved)
        T.eq([afterLight.iconTheme, afterLight.gtk["gtk-3.0"]],
             ["breeze", { preferDark: "false", iconTheme: "breeze", colorsImport: false, colorsDark: true }], "simulated GTK values")
        T.eq(A.plan(follow(false, true), afterLight, lightGtk.state).commands.filter(command => command[0] === A.GTK_HELPER), [],
             "light again: nothing left to change")
        const darkAgain = A.plan(follow(true, true), afterLight, lightGtk.state)
        T.eq(darkAgain.commands.filter(command => command[0] === A.GTK_HELPER),
             [helper("gtk-3.0", { preferDark: "true", iconTheme: "breeze-dark", colorsImport: true }),
              helper("gtk-4.0", { preferDark: "true", iconTheme: "breeze-dark", colorsImport: true })],
             "dark: the dark colors.css is the theme's again")
        const gtkOff = A.plan(off(true), afterLight, lightGtk.state)
        T.eq(gtkOff.commands.filter(command => command[0] === A.GTK_HELPER || command[3] === "icon-theme"),
             [["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "breeze-dark"],
              helper("gtk-3.0", { preferDark: "true", iconTheme: "breeze-dark", colorsImport: true }),
              helper("gtk-4.0", { preferDark: "true", iconTheme: "breeze-dark", colorsImport: true })],
             "off: exactly the saved GTK values come back")
        // A light colors.css (Plasma in BreezeLight) is left out for dark, and
        // a gtk.css that never imported one is not given an import.
        const lightPalette = A.parseQuery(gtkText.replace(JSON.stringify(gtkNow), JSON.stringify({
            "gtk-3.0": { preferDark: null, iconTheme: "breeze", colorsImport: true, colorsDark: false },
            "gtk-4.0": { preferDark: "false", colorsImport: false, colorsDark: true } })).replace("'breeze-dark'", "'breeze'"))
        T.eq(A.plan(follow(true, true), lightPalette, A.emptyState()).commands.filter(command => command[0] === A.GTK_HELPER),
             [helper("gtk-3.0", { preferDark: "true", iconTheme: "breeze-dark", colorsImport: false }), helper("gtk-4.0", { preferDark: "true" })],
             "dark over a light palette; no import where there was none; a missing key is set, a missing file left alone")
        T.eq(A.plan(follow(false, true), lightPalette, A.emptyState()).commands.filter(command => command[0] === A.GTK_HELPER), [],
             "light over a light palette: nothing to change")
        // A state from before GTK followed: an older shell never changed the
        // GTK files, so what is there now is saved before anything changes.
        const oldState = A.parseState(JSON.stringify({ version: 2, applied: true, restoreOnLogout: true,
            saved: { colorScheme: "BreezeDark", accentColor: "", kdeColors: backup, gtkColorScheme: "prefer-dark", gtkTheme: "Breeze-Dark" } }))
        T.eq([oldState.saved.iconTheme, oldState.saved.gtk], ["", null], "an older state has no GTK values")
        const upgraded = A.plan(follow(false, true), gtkQuery, oldState)
        T.eq([upgraded.state.saved.iconTheme, upgraded.state.saved.gtk, upgraded.state.saved.colorScheme], ["breeze-dark", gtkNow, "BreezeDark"],
             "completed from now, the rest kept")
        T.ok(upgraded.commands.some(command => command[0] === A.GTK_HELPER), "and the GTK files follow")
        T.ok(upgraded.state.restore.some(command => command[3] === "icon-theme" && command[4] === "breeze-dark"),
             "the icon theme is in the logout restore")
        T.eq(A.parseState(A.stateText(lightGtk.state)), lightGtk.state, "GTK state round trip")
        T.eq(A.parseState(JSON.stringify({ applied: true, saved: { gtk: gtkNow } })).applied, true, "GTK values alone are worth restoring")
        T.finish("AppTheme")
    }
}
