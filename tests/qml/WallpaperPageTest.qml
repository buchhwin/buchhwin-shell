import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"

// Settings > Wallpaper's image grid over a folder of 40 pictures in the
// sandbox (one pixel each: the grid reads them by name). The grid is one tab
// stop, taller than the view: the tile the keyboard stands on is the one
// scrolled into view, on arriving and on every arrow, rather than the grid's
// end. And the tiles share their rounding mask, so each carries one layer
// (its picture) instead of two.
ShellRoot {
    id: root
    property int waits: 0
    readonly property string folder: Paths.cacheDir + "/wallpaper-page-test"

    Process {
        id: make
        command: ["sh", "-c", 'mkdir -p "$1" && printf %s "$2" | base64 -d > "$1/image-10.png" && i=11 && '
                  + 'while [ "$i" -lt 50 ]; do cp "$1/image-10.png" "$1/image-$i.png"; i=$((i + 1)); done', "make", root.folder,
                  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="]
        onExited: {
            SettingsService.set("wallpaper.folder", root.folder)
            wait.start()
        }
    }

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 600
        visible: true
        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: loader.item ? loader.item.implicitHeight : 0
            clip: true
            Loader { id: loader; width: 860; active: false; sourceComponent: WallpaperPage {} }
        }
    }

    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }
    function inView(item) {
        const top = item.mapToItem(flick.contentItem, 0, 0).y
        return top >= flick.contentY - 0.5 && top + item.height <= flick.contentY + flick.height + 0.5
    }

    Component.onCompleted: make.running = true

    Timer {
        id: wait
        interval: 50; repeat: true
        onTriggered: {
            root.waits += 1
            if (WallpaperService.images.length !== 40 && root.waits < 100) return
            stop()
            T.eq(WallpaperService.images.length, 40, "the sandbox folder's pictures are listed")
            loader.active = true
            check.start()
        }
    }
    Timer {
        id: check
        interval: 200
        onTriggered: {
            const grid = root.walk(loader.item, item => item.step !== undefined && item.current !== undefined && item.columns !== undefined, [])[0]
            T.ok(grid !== undefined, "the grid is there")
            const tiles = root.walk(grid, item => item.modelData !== undefined && item.focused !== undefined, [])
            T.eq(tiles.length, 40, "a tile per picture")
            T.ok(grid.y + grid.height > flick.height, "the grid is taller than the view")

            // One layer per tile, and two masks for them all.
            const layered = root.walk(grid, item => item.layer && item.layer.enabled, [])
            T.eq(layered.length, tiles.length + 2, "each tile carries its picture's layer and no mask of its own")

            // Tab arrives: the panel would show the grid's end; the tile the
            // ring is on is what shows.
            flick.contentY = flick.contentHeight - flick.height
            grid.forceActiveFocus()
            arrived.start()
        }
    }
    Timer {
        id: arrived
        interval: 100
        onTriggered: {
            const grid = root.walk(loader.item, item => item.step !== undefined && item.current !== undefined && item.columns !== undefined, [])[0]
            const tiles = root.walk(grid, item => item.modelData !== undefined && item.focused !== undefined, [])
            const ringed = tiles.filter(tile => tile.focused)
            T.eq(ringed.length, 1, "one tile wears the ring")
            T.ok(ringed.length === 1 && root.inView(ringed[0]), "and it is in view after Tab")

            // The arrows move only `current`; the view follows it.
            grid.step(grid.columns * 6)
            const down = tiles.filter(tile => tile.focused)
            T.ok(down.length === 1 && root.inView(down[0]), "down six rows, the tile is in view")
            grid.step(-grid.columns * 6)
            const up = tiles.filter(tile => tile.focused)
            T.ok(up.length === 1 && root.inView(up[0]), "and back up again")
            T.finish("WallpaperPageTest")
        }
    }
}
