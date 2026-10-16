import Quickshell
import QtQuick
import qs.shell.wallpaper
import "Harness.js" as T

// The picker's selection through a star (shell/wallpaper/PickerSelection.qml),
// on a real GridView bound the way WallpaperPicker binds its grid: the model
// is a new array on every change, the view owns the index, and it does not
// follow its current item. Favourites come first, so a star moves the image.
ShellRoot {
    id: root
    property var items: list(20, [])
    property int currentIndex: 0
    property int step: 0

    // `count` images /w/0.png …, the starred ones first, as pickerItems
    // orders them.
    function list(count, starred) {
        const all = []
        for (let index = 0; index < count; ++index) all.push({ path: "/w/" + index + ".png" })
        return all.filter(item => starred.indexOf(item.path) >= 0).concat(all.filter(item => starred.indexOf(item.path) < 0))
    }
    function pathAt(index) { return root.items[index] ? root.items[index].path : "" }

    FloatingWindow {
        visible: true
        implicitWidth: 420
        implicitHeight: 240
        GridView {
            id: grid
            width: 400
            height: 200
            cellWidth: 100
            cellHeight: 100
            model: root.items
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: root.currentIndex = currentIndex
            delegate: Item { width: grid.cellWidth; height: grid.cellHeight }
        }
    }

    PickerSelection { id: keeper; view: grid; items: root.items }

    // What the picker's toggle does: hold, change the list, settle late.
    function star(path, starred, reveal) {
        keeper.hold(path, reveal)
        root.items = root.list(20, starred)
        Qt.callLater(keeper.settle)
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            root.step += 1
            if (root.step === 1) {
                // The key: the fourth tile, starred after one favourite.
                root.items = root.list(20, ["/w/0.png"])
                grid.currentIndex = 3
                T.eq(root.pathAt(root.currentIndex), "/w/3.png", "the fourth tile is selected")
                root.star("/w/3.png", ["/w/0.png", "/w/3.png"], true)
            } else if (root.step === 2) {
                T.eq(root.pathAt(1), "/w/3.png", "the starred image moved up behind the first favourite")
                T.eq([grid.currentIndex, root.pathAt(root.currentIndex)], [1, "/w/3.png"],
                     "and the selection went with it: Enter sets the image that was starred")
                // The pointer: a tile far down, the grid scrolled to it.
                grid.contentY = 300
                grid.currentIndex = 17
                root.star("/w/17.png", ["/w/0.png", "/w/3.png", "/w/17.png"], false)
            } else if (root.step === 3) {
                T.eq(root.pathAt(root.currentIndex), "/w/17.png", "a right click keeps the selection on its image too")
                T.eq(grid.contentY, 300, "and the grid where it was, under the resting pointer")
                // Unstarred under a filter that only shows favourites: the
                // image leaves the list, the old place in range is kept.
                grid.currentIndex = 2
                keeper.hold("/w/17.png", false)
                root.items = root.list(2, ["/w/0.png", "/w/3.png"]).slice(0, 2)
                Qt.callLater(keeper.settle)
            } else if (root.step === 4) {
                T.eq(grid.currentIndex, 1, "an image that left the list: its old place, in range")
                T.ok(!keeper.holding, "nothing is held once settled")
                T.eq(keeper.placeOf("/w/none.png", 99), root.items.length - 1, "placeOf clamps the fallback")
                T.finish("WallpaperPickerTest")
                stop()
            }
        }
    }
}
