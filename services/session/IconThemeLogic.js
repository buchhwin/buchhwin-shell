.pragma library

// The icon theme the shell runs with, and the one its panels want now.
//
// scripts/start-shell.sh picks QS_ICON_THEME once, before quickshell starts:
// kdeglobals' [Icons] Theme when the user has one, else by what the panels
// are (theme/Colors.qml's surfaceDark) - the dark theme's light symbolic
// icons on dark panels, the light theme's dark ones on light panels - and
// BUCHHWIN_ICON_THEME_AUTO=1 then says that the panels chose. Qt reads the
// theme at the start and has no way to change it in a running process, so
// when the panels change brightness under a running shell (the theme
// switched, a panel colour chosen, another profile) its symbolic icons stay
// as they were until the shell starts again: light grey on light cards,
// 1.2:1 in the launcher's and the start menu's rows. A restart picks the
// right one; restarting by itself would end a recording, a picker and every
// popup on the screen, so the shell offers it rather than doing it.

var DARK_PANELS = "breeze-dark"
var LIGHT_PANELS = "breeze"

// The theme start-shell.sh picks for panels of this brightness.
function wanted(surfaceDark) {
    return surfaceDark ? DARK_PANELS : LIGHT_PANELS
}

// True when a restart would give the shell other icons: the panels chose
// the running theme, and they want the other one now. A theme of the user's
// own (kdeglobals) is theirs whatever the panels are, and so is one the
// script does not pick by brightness.
function stale(running, chosenByPanels, surfaceDark) {
    if (String(chosenByPanels) !== "1") return false
    const name = String(running === undefined || running === null ? "" : running)
    if (name !== DARK_PANELS && name !== LIGHT_PANELS) return false
    return name !== wanted(Boolean(surfaceDark))
}
