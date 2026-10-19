import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/tray/TrayLogic.js" as Tray

// The tray widget's decisions: which background apps it shows, what each
// click does, and where a menu opened out of an icon goes - from the window
// the widget sits in, placed as wlr-layer-shell places it.
ShellRoot {
    Component.onCompleted: {
        const items = [{ id: "kdeconnect", status: Tray.PASSIVE }, { id: "steam", status: Tray.ACTIVE },
                       { id: "nm-applet", status: Tray.ACTIVE }, { id: "citrix", status: Tray.NEEDS_ATTENTION }, null]
        T.eq(Tray.shownIds(items, ["nm-applet"]), ["steam", "citrix"],
             "not the passive ones, not the hidden ones")
        T.eq(Tray.shownIds([], []), [], "no apps, no icons")
        T.eq([Tray.attention(Tray.NEEDS_ATTENTION), Tray.attention(Tray.ACTIVE)], [true, false], "the dot")
        T.eq([Tray.label({ id: "a", title: "B", tooltipTitle: "C" }), Tray.label({ id: "a", title: "B" }),
              Tray.label({ id: "a" }), Tray.label(null)], ["C", "B", "a", ""], "an app by its tooltip, title or id")

        // ---- clicks -------------------------------------------------------
        T.eq([Tray.clickAction("left", false, true), Tray.clickAction("middle", false, true), Tray.clickAction("right", false, true)],
             ["activate", "secondary", "menu"], "left activates, middle is the second action, right opens the menu")
        T.eq([Tray.clickAction("left", true, true), Tray.clickAction("left", true, false)], ["menu", ""],
             "an app that has only a menu opens it on a left click too")
        T.eq(Tray.clickAction("right", false, false), "activate", "a right click without a menu is the app's own")

        // ---- where the menu goes ---------------------------------------------
        const screen = { width: 1920, height: 1200 }
        T.eq(Tray.surfaceOrigin({ top: true, left: true, right: true }, { left: 6, top: 6 }, { width: 1908, height: 44 }, screen),
             { x: 6, y: 6 }, "a floating top bar: at its margins")
        T.eq(Tray.surfaceOrigin({ bottom: true, left: true, right: true }, {}, { width: 1920, height: 44 }, screen),
             { x: 0, y: 1156 }, "a bottom bar: at the bottom, not at the top of the screen")
        T.eq(Tray.surfaceOrigin({ top: true }, {}, { width: 820, height: 600 }, screen), { x: 550, y: 0 },
             "the notch: centred along the top")
        T.eq(Tray.surfaceOrigin({ right: true, top: true, bottom: true }, { right: 0 }, { width: 44, height: 1200 }, screen),
             { x: 1876, y: 0 }, "a bar down the right edge")
        T.eq(Tray.surfaceOrigin(undefined, undefined, undefined, undefined), { x: 0, y: 0 }, "nothing known: the corner")

        T.eq([Tray.surfaceEdge({ top: true, left: true, right: true }), Tray.surfaceEdge({ bottom: true, left: true, right: true }),
              Tray.surfaceEdge({ left: true, top: true, bottom: true }), Tray.surfaceEdge({ right: true, top: true, bottom: true }),
              Tray.surfaceEdge({ top: true }), Tray.surfaceEdge({ top: true, bottom: true, left: true, right: true }), Tray.surfaceEdge(null)],
             ["top", "bottom", "left", "right", "top", "", ""], "the edge a surface hangs from")

        const free = Tray.menuArgs({ x: 1700, y: 300, width: 16, height: 16 }, 1200, 8, "eDP-1", "")
        T.eq([free.anchorX, free.anchorTop, free.anchorBottom, free.onScreen], [1708, 324, undefined, "eDP-1"],
             "from the desktop the menu opens below the icon, on the icon's screen")
        T.eq([free.originX, free.originY, free.originWidth, free.originHeight], [1700, 300, 16, 16], "growing out of it")
        const low = Tray.menuArgs({ x: 900, y: 1000, width: 16, height: 16 }, 1200, 8, "", "")
        T.eq([low.anchorBottom, low.anchorTop, low.onScreen], [992, undefined, undefined],
             "from the lower half above it, and a screen it does not know is left to the panel")
        const bar = Tray.menuArgs({ x: 1700, y: 14, width: 16, height: 16 }, 1200, 8, "eDP-1", "top", true)
        T.eq([bar.anchorX, bar.anchorTop, bar.anchorBottom], [1708, undefined, undefined],
             "from a bar along the top (or the notch) the panel keeps its place under it")
        const bottom = Tray.menuArgs({ x: 1700, y: 1170, width: 16, height: 16 }, 1200, 8, "", "bottom", true)
        T.eq([bottom.anchorX, bottom.anchorTop, bottom.anchorBottom], [1708, undefined, undefined], "and above a bottom bar")
        const dock = Tray.menuArgs({ x: 900, y: 1150, width: 16, height: 16 }, 1200, 8, "", "bottom", false)
        T.eq([dock.anchorX, dock.anchorBottom], [908, 1142], "a dock with no bar on its edge: above the icon")
        const side = Tray.menuArgs({ x: 14, y: 600, width: 16, height: 16 }, 1200, 8, "", "left")
        T.eq([side.anchorY, side.anchorX], [608, undefined], "beside a side bar, level with the icon")
        T.finish("TrayWidgetTest")
    }
}
