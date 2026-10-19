import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/session/IconThemeLogic.js" as I

// The icon theme the shell started with against the one its panels want
// now (services/session/IconThemeLogic.js, scripts/start-shell.sh).
ShellRoot {
    Component.onCompleted: {
        // SessionService loads only when something first asks it - the lock
        // button, the lid - so a mistake in it would show there first. It
        // is read here and nothing is run.
        T.eq(typeof SessionService.iconThemeStale, "boolean", "SessionService loads and says whether the icons are stale")
        T.eq(SessionService.allowed.indexOf("lock") >= 0, true, "and still knows its actions")

        T.eq([I.wanted(true), I.wanted(false)], ["breeze-dark", "breeze"], "dark panels take the dark theme's icons, light ones the light theme's")

        // The panels chose (BUCHHWIN_ICON_THEME_AUTO=1): stale once they want the other.
        T.eq(I.stale("breeze-dark", "1", false), true, "started dark, the panels turned light: stale")
        T.eq(I.stale("breeze", "1", true), true, "started light, the panels turned dark: stale")
        T.eq([I.stale("breeze-dark", "1", true), I.stale("breeze", "1", false)], [false, false], "the theme that fits is not stale")

        // A theme of the user's own (kdeglobals) or one the script did not
        // pick by brightness is never stale, whatever the panels are.
        T.eq([I.stale("breeze-dark", "", false), I.stale("breeze-dark", undefined, false), I.stale("breeze", null, true)],
             [false, false, false], "the panels did not choose: never stale")
        T.eq([I.stale("Papirus", "1", false), I.stale("", "1", false), I.stale(undefined, "1", true)],
             [false, false, false], "a theme the script does not pick by brightness: never stale")
        T.eq(I.stale("breeze-dark", 1, false), true, "the marker as a number reads the same")

        T.finish("IconThemeTest")
    }
}
