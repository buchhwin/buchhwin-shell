import Quickshell
import QtQuick
import "Harness.js" as T
import "../../session/sddm/buchhwin/Logic.js" as L
import "../../session/sddm/buchhwin/Style.js" as S
import qs.theme

ShellRoot {
    Component.onCompleted: {
        // The greeter cannot import the theme singletons, so Style.js is a copy
        // of them kept by hand. It had drifted: two control heights, a clock
        // tracking with the wrong sign and an open duration the shell had
        // explicitly rejected as too short. These assertions are the only thing
        // that keeps the copy honest.
        T.eq(S.spaceSm, Metrics.spaceSm, "space step sm")
        T.eq(S.spaceMd, Metrics.spaceMd, "space step md")
        T.eq(S.spaceLg, Metrics.spaceLg, "space step lg")
        T.eq(S.spaceXl, Metrics.spaceXl, "space step xl")
        T.eq(S.borderWidth, Metrics.borderWidth, "border width")
        T.eq(S.controlHeight, Metrics.controlHeight, "control height")
        T.eq(S.controlHeightSm, Metrics.controlHeightSm, "small control height")
        T.eq(S.iconSm, Metrics.iconSm, "icon size sm")
        T.eq(S.iconMd, Metrics.iconMd, "icon size md")
        T.eq(S.captionSize, Typography.captionSize, "caption size")
        T.eq(S.smallSize, Typography.smallSize, "small size")
        T.eq(S.bodySize, Typography.bodySize, "body size")
        T.eq(S.clockSize, Typography.lockClockSize, "lock clock size")
        T.eq(S.clockTracking, Typography.clockTracking, "clock tracking")
        T.eq(S.popupOpen, 220, "a menu opens at the duration the shell settled on")

        // theme.conf values.
        T.eq([L.configString(undefined, "x"), L.configString("  ", "x"), L.configString(" a ", "x")], ["x", "x", "a"], "strings")
        T.eq(L.configString(["dddd", "d MMMM"], ""), "dddd, d MMMM", "QSettings lists joined back")
        T.eq([L.configBool("true", false), L.configBool("Off", true), L.configBool("1", false), L.configBool("maybe", true), L.configBool(false, true)],
             [true, false, true, true, false], "booleans")
        T.eq([L.configColor("#4F8FF7", "#000000"), L.configColor("blue", "#000000"), L.configColor("#fff", "#000000")],
             ["#4F8FF7", "#000000", "#000000"], "colours")
        T.eq([L.imageUrl("background.webp"), L.imageUrl("/usr/share/w.png"), L.imageUrl("file:///x.png"), L.imageUrl("")],
             ["background.webp", "file:///usr/share/w.png", "file:///x.png", ""], "image urls")

        // Models.
        T.eq([L.clampIndex(2, 3), L.clampIndex(3, 3), L.clampIndex(-1, 3), L.clampIndex(undefined, 3), L.clampIndex(0, 0)],
             [2, 0, 0, 0, -1], "clamped rows")
        T.eq([L.nextIndex(0, 2), L.nextIndex(1, 2), L.nextIndex(5, 2), L.nextIndex(0, 0)], [1, 0, 1, -1], "next layout")
        T.eq([L.displayName("Jan B", "jan"), L.displayName("", "jan"), L.displayName(undefined, undefined)], ["Jan B", "jan", ""], "display name")
        T.eq([L.initial("jan"), L.initial("  élise"), L.initial("_1x"), L.initial("")], ["J", "É", "1", "?"], "initials")
        T.eq([L.hasOwnFace("/usr/share/sddm/faces/.face.icon"), L.hasOwnFace("/usr/share/sddm/faces/jan.face.icon"),
              L.hasOwnFace("/home/jan/.face.icon"), L.hasOwnFace("/var/lib/AccountsService/icons/jan"), L.hasOwnFace("")],
             [false, true, true, true, false], "own faces")
        T.eq([L.sessionLabel("Plasma (Wayland)", "plasma.desktop"), L.sessionLabel("", "buchhwin-shell.desktop"), L.sessionLabel("", "")],
             ["Plasma (Wayland)", "buchhwin-shell", "Session"], "session labels")
        T.eq([L.layoutLabel([{ shortName: "de", longName: "German" }, { shortName: "us" }], 1), L.layoutLabel([{ longName: "German" }], 0),
              L.layoutLabel([], 0), L.layoutLabel(undefined, 0)], ["US", "GERMAN", "", ""], "layout labels")

        // Staggered entrance: later steps start later and all reach 1.
        T.eq([L.stagger(0, 1, 3, 120, 720, false), L.stagger(1, 1, 3, 120, 720, false), L.stagger(1, 3, 3, 120, 720, false)], [0, 1, 1], "stagger ends")
        T.ok(L.stagger(0.3, 1, 3, 120, 720, false) > L.stagger(0.3, 3, 3, 120, 720, false), "later step lags behind")
        T.eq(L.stagger(0.3, 1, 3, 120, 720, true), L.stagger(0.3, 3, 3, 120, 720, true), "leaving moves together")
        T.eq(L.stagger(0.5, 2, 3, 120, 0, false), 0.5, "no animation time")

        // Caps Lock guess and status.
        T.eq([L.capsGuess(null, "A", false, false), L.capsGuess(null, "a", false, false), L.capsGuess(null, "A", true, false),
              L.capsGuess(false, "a", true, false)], [true, false, false, true], "letters tell the state")
        T.eq([L.capsGuess(true, "1", false, false), L.capsGuess(null, "", false, false), L.capsGuess(false, "ab", false, false)],
             [true, null, false], "non-letters keep the state")
        T.eq([L.capsGuess(true, "", false, true), L.capsGuess(false, "", false, true), L.capsGuess(null, "", false, true)],
             [false, true, null], "Caps Lock key flips a known state")
        T.eq([L.statusText("Login failed", true), L.statusText("", true), L.statusText("", false)],
             ["Login failed", "Caps Lock is on", ""], "status text")

        T.finish("SddmThemeTest")
    }
}
