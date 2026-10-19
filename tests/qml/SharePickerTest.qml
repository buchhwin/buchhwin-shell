import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/sharepicker/SharePickerLogic.js" as S

// The share picker's half of xdg-desktop-portal-hyprland's custom picker
// contract (services/sharepicker/SharePickerLogic.js): the portal's window
// list, the lines it reads back, the private request directory, the order
// and the keys, and the portal's configuration as Settings reads it.
ShellRoot {
    Component.onCompleted: {
        // ---- addresses: 64 bits in decimal, Hyprland's in hex ---------------------
        T.eq([S.decimalToHex("93968578707456"), S.decimalToHex("255"), S.decimalToHex("16"), S.decimalToHex("1")],
             ["5576c3c10000", "ff", "10", "1"], "decimal to hex")
        T.eq(S.decimalToHex("18446744073709551615"), "ffffffffffffffff", "all 64 bits, past a JS number's 53")
        T.eq(S.decimalToHex("0093968578707456"), "5576c3c10000", "leading zeros")
        T.eq([S.decimalToHex("0"), S.decimalToHex(""), S.decimalToHex("12a"), S.decimalToHex("-5"), S.decimalToHex(undefined)],
             ["", "", "", "", ""], "0 (not mapped) and anything else is no address")
        T.eq([S.addressKey("0x5576C3C10000"), S.addressKey("5576c3c10000"), S.addressKey("0x00ab"), S.addressKey(null)],
             ["5576c3c10000", "5576c3c10000", "ab", ""], "one key for hyprctl's and Quickshell's spelling")

        // ---- the window list ----------------------------------------------------------
        const list = "305419896[HC>]brave-teams[HT>]Meeting | Microsoft Teams[HE>]93968578707456[HA>]"
            + "17[HC>]Alacritty[HT>]~ [HE>]0[HA>]"
            + "x9[HC>]bad[HT>]no handle[HE>]1[HA>]"
            + "42[HC>]code[HT>]a[b]c > d[HE>]255[HA>]"
        T.eq(S.parseWindowList(list), [
            { handle: "305419896", appClass: "brave-teams", title: "Meeting | Microsoft Teams", address: "5576c3c10000" },
            { handle: "17", appClass: "Alacritty", title: "~", address: "" },
            { handle: "42", appClass: "code", title: "a[b]c > d", address: "ff" }
        ], "handles, classes, titles and addresses; an entry without a numeric handle left out")
        T.eq(S.parseWindowList("1[HC>]old[HT>]portal[HE>]2[HC>]two[HT>]t[HE>]"), [
            { handle: "1", appClass: "old", title: "portal", address: "" },
            { handle: "2", appClass: "two", title: "t", address: "" }
        ], "an older portal's list without addresses")
        T.eq(S.parseWindowList("1[HC>]ok[HT>]fine[HE>]0[HA>]2[HC>]broken"), [{ handle: "1", appClass: "ok", title: "fine", address: "" }],
             "a broken tail ends the list")
        T.eq([S.parseWindowList(""), S.parseWindowList(undefined), S.parseWindowList("99999999999[HC>]a[HT>]b[HE>]0[HA>]")],
             [[], [], []], "nothing, and a handle past 32 bits")

        // ---- the answer lines -----------------------------------------------------------
        T.eq(S.answerFor({ kind: "screen", name: "eDP-1" }, false), "[SELECTION]/screen:eDP-1", "a screen")
        T.eq(S.answerFor({ kind: "screen", name: "HDMI-A-1" }, true), "[SELECTION]r/screen:HDMI-A-1", "with the token flag")
        T.eq(S.answerFor({ kind: "window", handle: "305419896" }, false), "[SELECTION]/window:305419896", "a window by its handle")
        T.eq([S.answerFor({ kind: "region" }, false), S.answerFor({ kind: "region" }, true)], ["region", "region r"],
             "a region is the script's to ask slurp for")
        T.eq([S.answerFor({ kind: "screen", name: "eDP-1\n[SELECTION]/screen:x" }), S.answerFor({ kind: "screen", name: "" }),
              S.answerFor({ kind: "window", handle: "12; rm" }), S.answerFor({ kind: "other" }), S.answerFor(null)],
             ["", "", "", "", ""], "nothing the portal could misread")
        T.eq(["[SELECTION]/screen:eDP-1", "[SELECTION]r/window:17", "[SELECTION]/region:DP-1@0,0,1920,1080",
              "[SELECTION]r/region:eDP-1@-5,10,300,200"].map(S.validSelection), [true, true, true, true], "the portal's three forms")
        T.eq(["[SELECTION]/screen:", "[SELECTION]x/screen:a", "[SELECTION]/window:abc", "[SELECTION]/screen:a b",
              "screen:eDP-1", "[SELECTION]/region:DP-1@0,0,1920", "[SELECTION]/screen:eDP-1\n", "", undefined].map(S.validSelection),
             [false, false, false, false, false, false, false, false, false], "anything else is not a choice")
        T.eq(S.validSelection(S.answerFor({ kind: "screen", name: "BUCHTEST" }, true)), true, "what the shell answers passes the script's check")
        T.eq([S.CANCEL, S.REGION, S.FALLBACK], ["cancel", "region", "fallback"], "the other three answers the script knows")

        // ---- the request directory --------------------------------------------------------
        const runtime = "/run/user/1000/buchhwin-shell"
        T.eq([S.requestDirOk(runtime + "/share-picker/req.Ab12Cd34", runtime), S.requestDirOk(runtime + "/share-picker/req.abcdef", runtime + "/")],
             [true, true], "the script's own directory")
        T.eq([S.requestDirOk(runtime + "/share-picker/req.Ab12Cd34/../../x", runtime), S.requestDirOk(runtime + "/share-picker/other", runtime),
              S.requestDirOk("/tmp/share-picker/req.Ab12Cd34", runtime), S.requestDirOk(runtime + "/share-picker/req.ab", runtime),
              S.requestDirOk(runtime + "/share-picker/req.Ab12Cd34", "relative"), S.requestDirOk(runtime + "/share-picker/req.Ab12Cd34", "/a/../b"),
              S.requestDirOk("", runtime), S.requestDirOk(undefined, undefined)],
             [false, false, false, false, false, false, false, false], "nowhere else")

        // ---- order, stops and keys ----------------------------------------------------------
        const windows = [
            { handle: "1", address: "a1" }, { handle: "2", address: "a2" }, { handle: "3", address: "" },
            { handle: "4", address: "a4" }, { handle: "5", address: "a5" }
        ]
        const info = { a1: { workspace: 3, shown: false }, a2: { workspace: 1, shown: true },
                       a4: { workspace: -98, shown: false }, a5: { workspace: 2, shown: false } }
        T.eq(S.orderWindows(windows, info).map(entry => entry.handle), ["2", "5", "1", "4", "3"],
             "shown first, then by workspace, special ones after, unknown last")
        T.eq(S.orderWindows(windows, {}).map(entry => entry.handle), ["1", "2", "3", "4", "5"], "unknown to Hyprland: the portal's order")

        const screens = [{ name: "eDP-1" }, { name: "DP-1" }, { name: "bad name" }]
        const all = S.stops(screens, windows, true)
        T.eq(all.map(stop => stop.key), ["screen:eDP-1", "screen:DP-1", "window:1", "window:2", "window:3", "window:4", "window:5", "region"],
             "screens, windows, the region")
        T.eq(S.stops(screens, [], false).map(stop => stop.kind), ["screen", "screen"], "no region without slurp")
        T.eq([S.openingIndex(all, "DP-1"), S.openingIndex(all, "gone"), S.openingIndex([], "x")], [1, 0, 0],
             "the selection starts on the screen the picker opened on")
        const cols = { screens: 2, windows: 3, region: 1 }
        T.eq([S.move(all, 0, "right", cols), S.move(all, 1, "right", cols), S.move(all, 7, "right", cols), S.move(all, 0, "left", cols)],
             [1, 2, 7, 0], "left and right walk the whole list")
        // Windows 1-5 in rows of three: [1 2 3] [4 5].
        T.eq([S.move(all, 2, "down", cols), S.move(all, 4, "down", cols), S.move(all, 5, "up", cols)], [5, 6, 2],
             "down and up within the windows, to the last of a shorter row")
        T.eq([S.move(all, 1, "down", cols), S.move(all, 0, "down", cols), S.move(all, 3, "up", cols)], [3, 2, 1],
             "from the screens into the windows' first row and back, by column")
        T.eq([S.move(all, 6, "down", cols), S.move(all, 7, "up", cols), S.move(all, 7, "down", cols), S.move(all, 0, "up", cols)],
             [7, 5, 7, 0], "into the region and back up into the windows' last row; the ends stay")
        T.eq([S.move([], 0, "down", cols), S.move(all, 99, "left", cols), S.move(all, 3, "nowhere", cols)], [-1, 6, 3], "edges")

        T.eq([S.fitInside(1920, 1080, 320, 200), S.fitInside(1080, 1920, 320, 200), S.fitInside(0, 0, 320, 200)],
             [{ width: 320, height: 180 }, { width: 113, height: 200 }, { width: 320, height: 200 }], "thumbnails keep their shape")
        T.eq([S.screenLabel({ name: "eDP-1", width: 1920, height: 1200 }), S.screenLabel({ name: "X" }), S.screenLabel(null)],
             ["eDP-1 · 1920 × 1200", "X", ""], "screen labels")
        T.eq([S.screenLabel({ name: "eDP-1", width: 1920, height: 1200 }, { make: "Sample", model: "Panel 14" }, true),
              S.screenLabel({ name: "DP-8", width: 2304, height: 1296 }, { make: "Sample", model: "View 27" }, false),
              S.screenLabel({ name: "DP-9", width: 1920, height: 1080 }, { make: "", model: "" }, false)],
             ["Built-in display · 1920 × 1200", "Sample View 27 · 2304 × 1296", "DP-9 · 1920 × 1080"],
             "named as Settings > Displays names them: the panel, a screen's make and model, else its connector")
        T.eq([S.windowLabel({ title: "T", appClass: "c" }), S.windowLabel({ title: "", appClass: "c" }), S.windowLabel({})],
             ["T", "c", "Window"], "window labels")

        // ---- the portal's configuration -------------------------------------------------------
        T.eq(S.configuredPicker("screencopy {\n    max_fps = 60\n    custom_picker_binary = /home/u/.local/share/buchhwin-shell/scripts/share-picker.sh # ours\n}\n"),
             "/home/u/.local/share/buchhwin-shell/scripts/share-picker.sh", "the block form, comment dropped")
        T.eq(S.configuredPicker("screencopy:custom_picker_binary = /opt/picker"), "/opt/picker", "the flat form")
        T.eq([S.configuredPicker("# screencopy:custom_picker_binary = x"), S.configuredPicker("other {\n custom_picker_binary = y\n}"),
              S.configuredPicker(""), S.configuredPicker(undefined)], ["", "", "", ""], "a comment, another block, nothing")
        T.eq([S.isShellPicker("/home/u/.local/share/buchhwin-shell/scripts/share-picker.sh"), S.isShellPicker("scripts/share-picker.sh"),
              S.isShellPicker("/usr/bin/hyprland-share-picker"), S.isShellPicker("/x/scripts/share-picker.sh.bak"), S.isShellPicker("")],
             [true, true, false, false, false], "the shell's picker from any tree")
        T.eq(S.configSnippet("/p/scripts/share-picker.sh"), "screencopy {\n    custom_picker_binary = /p/scripts/share-picker.sh\n}\n",
             "the lines to add")
        T.eq(S.isShellPicker(S.configuredPicker(S.configSnippet("/p/scripts/share-picker.sh"))), true, "and they read back as the shell's")

        T.finish("SharePickerTest")
    }
}
