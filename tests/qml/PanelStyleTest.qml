import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/PanelStyleLogic.js" as P

ShellRoot {
    Component.onCompleted: {
        T.eq(["settings", "controlCenter", "dashboard", "launcher", "clipboard"].map(P.groupFor),
             ["settings", "controlCenter", "dashboard", "launcher", "clipboard"], "panel ids that are group keys")
        T.eq([P.groupFor("notifications"), P.groupFor("powerMenu")], ["notificationCenter", "sessionMenu"], "renamed panel ids")
        T.eq([P.groupFor("wifiPassword"), P.groupFor("pairing"), P.groupFor("wifi"), P.groupFor("media"), P.groupFor(""), P.groupFor(undefined)],
             ["popups", "popups", "popups", "popups", "popups", "popups"], "dialogs, pill popups and unknown ids share a group")
        T.eq([P.groupFor("pillBar"), P.groupFor("osd"), P.groupFor("widgets"), P.groupFor("notificationPopups")],
             ["pillBar", "osd", "widgets", "notificationPopups"], "surface groups")
        T.eq(P.GROUPS.length, 14, "all groups listed")
        T.ok(P.GROUPS.every(group => group.label.length > 0 && P.groupFor(group.key) === group.key), "every group has a label and maps to itself")

        T.near(P.effectiveOpacity("controlCenter", -1, 0.74), 0.74, "default follows the global value")
        T.near(P.effectiveOpacity("controlCenter", 0.5, 0.74), 0.5, "own value wins")
        T.near(P.effectiveOpacity("controlCenter", 0, 0.74), 0.4, "own value is clamped to the minimum")
        T.near(P.effectiveOpacity("settings", 3, 0.74), 1, "own value is clamped to the maximum")
        T.near(P.effectiveOpacity("launcher", "0.5", 0.74), 0.74, "strings are not overrides")
        T.near(P.effectiveOpacity("launcher", -1, 0.1), 0.4, "global value is clamped too")
        T.near(P.effectiveOpacity("launcher", -1, NaN), 1, "invalid global value is opaque")
        T.near(P.effectiveOpacity("pillBar", -1, 0.74), 0.74, "pill bar follows the default")
        T.near(P.effectiveOpacity("osd", -1, 0.5), 0.5, "OSD follows the default")
        T.near(P.effectiveOpacity("pillBar", 0.6, 0.74), 0.6, "pill bar can be set individually")
        T.near(P.effectiveOpacity("powerMenu", 0.8, 0.5), 0.8, "panel ids work directly")
        T.eq([P.isOverride(-1), P.isOverride(0.5), P.isOverride(null), P.isOverride(NaN)], [false, true, false, false], "override detection")

        T.eq(["#1A2B3C", " 1a2b3c ", "#abc", "ABC", "#12345", "#1234567", "red", "", null, undefined, "#ggghhh"].map(P.normalizeHex),
             ["#1a2b3c", "#1a2b3c", "#aabbcc", "#aabbcc", "", "", "", "", "", "", ""], "hex validation")
        T.eq(["auto", "#101218", "nope", "", 12].map(P.colorSetting), ["auto", "#101218", "auto", "auto", "auto"], "stored colour setting")
        T.eq(P.parseHex("#ff8000"), { r: 1, g: 128 / 255, b: 0 }, "parse channels")
        T.eq(P.parseHex("#12"), null, "parse invalid")
        T.eq(P.rgba("#000000", 0.5), { r: 0, g: 0, b: 0, a: 0.5 }, "rgba with alpha")
        T.eq(P.rgba("#ffffff", 2).a, 1, "alpha is clamped")
        T.eq(P.rgba("x", 0.5), null, "rgba of an invalid colour")

        T.near(P.luminance("#000000"), 0, "black luminance")
        T.near(P.luminance("#ffffff"), 1, "white luminance", 1e-6)
        T.near(P.luminance("#808080"), 0.2158605, "grey luminance", 1e-6)
        T.eq(P.luminance("xyz"), -1, "invalid luminance")
        T.eq(["#000000", "#16181d", "#1e2a44", "#ffffff", "#e5e7eb", "#4f8ff7", "#666666"].map(P.isLight),
             [false, false, false, true, true, true, false], "light or dark text")
        T.eq([P.matchesTheme("auto", true), P.matchesTheme("#ffffff", true), P.matchesTheme("#ffffff", false),
              P.matchesTheme("#101010", true), P.matchesTheme("#101010", false)],
             [true, false, true, true, false], "colour fits the theme")
        T.eq([P.themeForColor("auto", true), P.themeForColor("#ffffff", true), P.themeForColor("#ffffff", false),
              P.themeForColor("#141c2e", false), P.themeForColor("#141c2e", true), P.themeForColor("oops", false)],
             ["", "light", "", "dark", "", ""], "theme switch after choosing a colour")

        const hoverDark = P.hoverRgb("#000000")
        const hoverLight = P.hoverRgb("#ffffff")
        T.ok(hoverDark.r > 0 && hoverDark.r < 0.1, "hover lightens dark colours")
        T.ok(hoverLight.r < 1 && hoverLight.r > 0.9, "hover darkens light colours")
        T.eq(P.hoverRgb(""), null, "hover of an invalid colour")
        T.finish("PanelStyleTest")
    }
}
