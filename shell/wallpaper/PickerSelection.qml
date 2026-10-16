import QtQuick

// Keeps the wallpaper picker's selection on an image while the list under it
// changes order (shell/wallpaper/WallpaperPicker.qml).
//
// Starring an image moves it: favourites come first. The selection was a
// number, so after Ctrl+F on the fourth tile the highlight stood on whatever
// had moved into fourth place, and Enter set that one - or, worse, on the
// first tile: the grid's model is a new array, a view resets its current
// index to 0 on a new model, and the view's index is the one the picker
// follows. A right click on a tile far down also put the grid back at the top
// under a resting pointer. So the toggle holds the image (its path), and once
// the new list is in, the selection goes back to it: revealed for the key, the
// grid left where it was for the pointer.
QtObject {
    id: root
    // The GridView, and the list it shows.
    property var view: null
    property var items: []
    // What the next change has to come back to: { path, index, reveal,
    // contentY }, null while nothing is held.
    property var held: null
    readonly property bool holding: held !== null

    // Where `path` is in the list now, else the old index in range.
    function placeOf(path, fallback) {
        const list = Array.prototype.slice.call(items || [])
        const index = list.findIndex(item => item && item.path === path)
        if (index >= 0) return index
        return Math.max(0, Math.min(Math.round(Number(fallback) || 0), list.length - 1))
    }

    // Before the list changes. `reveal`: scroll the image into view where it
    // lands (the keyboard); otherwise the grid keeps its place (the pointer).
    function hold(path, reveal) {
        held = { path: String(path || ""), index: view ? view.currentIndex : 0, reveal: reveal === true,
                 contentY: view ? view.contentY : 0 }
    }

    // After it changed. Called late (Qt.callLater), once the view has taken
    // the new model and reset itself.
    function settle() {
        const kept = held
        held = null
        if (!kept || !view) return
        if (!(items || []).length) return
        const index = placeOf(kept.path, kept.index)
        view.currentIndex = index
        if (kept.reveal) {
            view.positionViewAtIndex(index, GridView.Contain)
        } else {
            const top = Math.max(0, view.contentHeight - view.height)
            view.contentY = Math.max(0, Math.min(kept.contentY, top))
        }
    }
}
