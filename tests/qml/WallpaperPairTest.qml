import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/wallpaper/WallpaperLogic.js" as W

// A wallpaper for each theme (Settings > Wallpaper): which picture the
// desktop is given and which setting a pick goes into.
ShellRoot {
    Component.onCompleted: {
        // Off: the shared wallpaper, whatever the two sides say.
        T.eq(W.themePath(false, true, "/w/light.png", "/w/dark.png", "/w/shared.png"), "/w/shared.png", "off: the shared one")
        T.eq(W.themePath(undefined, false, "/w/light.png", "", "/w/shared.png"), "/w/shared.png", "unset is off")
        // On: the theme's own side.
        T.eq(W.themePath(true, true, "/w/light.png", "/w/dark.png", "/w/shared.png"), "/w/dark.png", "dark theme, dark side")
        T.eq(W.themePath(true, false, "/w/light.png", "/w/dark.png", "/w/shared.png"), "/w/light.png", "light theme, light side")
        // A side with nothing yet shows the shared one: turning the pair on
        // changes nothing until a picture is picked for a side.
        T.eq(W.themePath(true, true, "/w/light.png", "", "/w/shared.png"), "/w/shared.png", "an empty dark side")
        T.eq(W.themePath(true, false, "", "", "/w/shared.png"), "/w/shared.png", "both empty")
        T.eq(W.themePath(true, false, undefined, undefined, undefined), "", "nothing set at all")
        T.eq(W.themePath(true, false, 5, "/w/dark.png", "/w/shared.png"), "/w/shared.png", "a side that is no path")

        // Which side shows.
        T.eq([W.themeSide(false, true, "/w/l.png", "/w/d.png"), W.themeSide(true, true, "/w/l.png", "/w/d.png"),
              W.themeSide(true, false, "/w/l.png", "/w/d.png"), W.themeSide(true, true, "/w/l.png", "")],
             ["shared", "dark", "light", "shared"], "the side on the desktop")

        // Where a pick goes.
        T.eq(W.pickKey(false, true), "wallpaper.path", "off: the shared setting")
        T.eq(W.pickKey(true, true), "wallpaper.darkPath", "on, dark theme: the dark side")
        T.eq(W.pickKey(true, false), "wallpaper.lightPath", "on, light theme: the light side")
        T.eq(W.pickKey("yes", false), "wallpaper.path", "only true turns it on")

        T.finish("WallpaperPairTest")
    }
}
