import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/LayoutLogic.js" as L
import "../../services/launcher/LauncherCatalogue.js" as C

// The launcher's layout: a grid of four columns and eight rows, on the same
// operations as the control center's tiles and the dashboard's cards.
//
// The acceptance test is the first one: **the default is today's picture.**
// It was a column of stacked blocks with two hand-written pairing rules until
// the user asked twice for the grid the rest of the shell has; the rules are
// gone and the picture has to survive them going.
ShellRoot {
    Component.onCompleted: {
        const fresh = L.defaultLauncher()
        const idOf = type => L.launcherItems(fresh).find(item => item.type === type).id
        const cells = launcher => L.launcherItems(launcher)
            .map(item => item.type + " " + item.w + "x" + item.h)

        // ---- the default is what the launcher looks like now ------------

        T.eq(L.launcherTypes(fresh), ["search", "modes", "pinned", "categories", "results"],
            "five blocks, in the order the packer fills the grid in")
        T.eq(cells(fresh), ["search 3x1", "modes 1x1", "pinned 4x1", "categories 1x6", "results 3x6"],
            "and the sizes are the picture: the field with the switch beside it, "
            + "the pinned row under them, the categories down the left of the results")

        // Four columns wide, eight rows tall, and the default fills it exactly
        // once: 3+1 across the first row, 4 across the second, 1+3 for the
        // rest. Nothing wraps, nothing is left over.
        T.eq(C.columns, 4, "four columns")
        T.eq(C.rows, 8, "eight rows")
        const tall = L.launcherItems(fresh).reduce((most, item) => Math.max(most, item.h), 0)
        T.eq(tall <= C.rows, true, "and nothing starts taller than the grid")

        const ids = L.launcherItems(fresh).map(item => item.id)
        T.eq(ids.filter((id, index) => ids.indexOf(id) !== index), [], "five different ids")

        // ---- the one block that may not be taken off --------------------

        // Only the search field. A launcher with no field to type in cannot be
        // got out of again; one with no result list still answers the next
        // keystroke and says so, which is why the result list is removable and
        // was asked to be.
        T.eq(C.fixed("search"), true, "the search field is fixed")
        T.eq([C.fixed("results"), C.fixed("categories"), C.fixed("modes"), C.fixed("pinned")],
            [false, false, false, false], "and nothing else is")
        T.eq(L.launcherTypes(L.removeLauncherBlock(fresh, idOf("search"))),
            ["search", "modes", "pinned", "categories", "results"], "so the field cannot be removed")
        T.eq(L.launcherTypes(L.removeLauncherBlock(fresh, idOf("results"))),
            ["search", "modes", "pinned", "categories"], "the result list can")

        // The two used to be one block - the categories were drawn inside the
        // result block - so taking one meant taking both.
        const noResults = L.removeLauncherBlock(fresh, idOf("results"))
        T.eq(L.launcherTypes(noResults).indexOf("categories") >= 0, true,
            "removing the results leaves the categories")
        const noCats = L.removeLauncherBlock(fresh, idOf("categories"))
        T.eq(L.launcherTypes(noCats).indexOf("results") >= 0, true,
            "and removing the categories leaves the results")

        // ---- moved and sized like any other tile ------------------------

        T.eq(L.launcherTypes(L.moveLauncherBlockTo(fresh, idOf("search"), 4)),
            ["modes", "pinned", "categories", "results", "search"],
            "a block goes where it is put, the search field included")

        // **The search field can sit to the right of the modes**, which is the
        // thing the stacked version could not do and the reason for the grid.
        const swapped = L.moveLauncherBlockTo(fresh, idOf("modes"), 0)
        T.eq(L.launcherTypes(swapped), ["modes", "search", "pinned", "categories", "results"],
            "the mode switch in front of the search field")

        const wide = L.setLauncherBlockSize(fresh, idOf("categories"), 4, 1)
        T.eq(cells(wide)[3], "categories 4x1", "the categories can be a wide short row")
        const narrow = L.setLauncherBlockSize(fresh, idOf("results"), 1, 2)
        T.eq(cells(narrow)[4], "results 1x2", "and the results can be made small, if that is wanted")

        // The bounds are the grid's. Eight rows here, where the control
        // centre and the dashboard stop at six.
        T.eq(cells(L.setLauncherBlockSize(fresh, idOf("results"), 9, 9))[4], "results 4x8",
            "nothing may be dragged past the grid")
        T.eq(cells(L.setLauncherBlockSize(fresh, idOf("results"), 0, 0))[4], "results 1x2",
            "nor below what the block needs - a result list of one row is not a shorter list, it is none")

        // ---- the picker --------------------------------------------------

        T.eq(C.missing(L.launcherTypes(fresh)), [], "nothing to add while every block is there")
        const without = L.removeLauncherBlock(L.removeLauncherBlock(fresh, idOf("pinned")), idOf("modes"))
        T.eq(C.missing(L.launcherTypes(without)).map(block => block.type), ["modes", "pinned"],
            "what was taken off is what the picker offers")
        T.eq(C.label("modes"), "Modes", "with a name on it")
        T.eq(L.launcherTypes(L.addLauncherBlock(without, "modes")).indexOf("modes") >= 0, true,
            "and it comes back")
        T.eq(L.launcherTypes(L.addLauncherBlock(fresh, "pinned")),
            ["search", "modes", "pinned", "categories", "results"], "nothing is added twice")
        T.eq(L.launcherTypes(L.addLauncherBlock(fresh, "clock")),
            ["search", "modes", "pinned", "categories", "results"],
            "and no desktop widget: a search surface is at heart its result list")

        // ---- what a file may contain ------------------------------------

        T.eq(L.launcherTypes(L.sanitizeLauncher(null)), ["search", "modes", "pinned", "categories", "results"],
            "no launcher at all is the default")
        T.eq(L.launcherTypes(L.sanitizeLauncher({ launcher: [] })),
            ["search", "modes", "pinned", "categories", "results"],
            "and an empty one is too - an empty launcher is not a choice anybody made")
        const doubled = L.sanitizeLauncher({ launcher: [
            { id: "a", items: [{ type: "search", w: 3, h: 1 }] },
            { id: "b", items: [{ type: "nonsense", w: 1, h: 1 }] },
            { id: "c", items: [{ type: "results", w: 3, h: 6 }] }] })
        T.eq(L.launcherTypes(doubled), ["search", "results"], "a type the launcher never had is dropped")
        // The search field may not be taken off (removeLauncherBlock refuses),
        // and a file that lost it anyway gets it back in front - with a fresh
        // id, and the rest as they were.
        const fieldless = L.sanitizeLauncher({ launcher: [
            { id: "launcher-search", items: [{ type: "results", w: 3, h: 6 }] },
            { id: "b", items: [{ type: "modes", w: 1, h: 1 }] }] })
        T.eq(L.launcherTypes(fieldless), ["search", "results", "modes"], "a file without the search field gets it back")
        T.eq(fieldless.launcher.map(pill => pill.id), ["launcher-search-2", "launcher-search", "b"],
             "under an id nothing else on the surface has")
        T.eq(L.launcherItems(fieldless)[0].w, C.size("search").w, "at its catalogue size")
        // The catalogue's floor holds for the file, not only for a drag.
        const shallow = L.sanitizeLauncher({ launcher: [
            { id: "a", items: [{ type: "search", w: 3, h: 1 }] },
            { id: "r", items: [{ type: "results", w: 2, h: 1 }] }] })
        T.eq(L.launcherItems(shallow).map(item => [item.w, item.h]), [[3, 1], [2, 2]],
             "a result list written one row tall loads at its two")
        T.eq(L.launcherTypes(L.emptyMode().launcher), ["search", "modes", "pinned", "categories", "results"],
             "a mode nobody has touched carries the default launcher, like its other surfaces")

        // A file written while the launcher stacked its blocks had them under
        // `stack`, with no sizes at all. There is nothing to recover from that
        // - the zone name is different and a stacked block has no cell - so it
        // reads as an empty surface and comes back as the default, which is
        // the picture it had anyway.
        const stacked = L.sanitizeLauncher({ stack: [{ id: "a", items: [{ type: "search" }] }] })
        T.eq(L.launcherTypes(stacked), ["search", "modes", "pinned", "categories", "results"],
            "a layout from the stacked version comes back as the default")

        // ---- and the mode carries it ------------------------------------

        const mode = L.sanitize({ profiles: { default: { modes: { laptop: { desktopMode: "widgets" } } } },
                                  activeProfile: "default", activeMode: "laptop" })
        const laptop = mode.profiles.default.modes.laptop
        T.eq(L.launcherTypes(laptop.launcher), ["search", "modes", "pinned", "categories", "results"],
            "a mode without a launcher is given the default one")
        T.eq(laptop.desktopMode, "widgets", "and keeps what it did say")

        T.finish("LauncherLayoutTest")
    }
}
