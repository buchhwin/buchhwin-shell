.pragma library

// One edit of the layout as one undo step, written to layout.json - or, when
// it changed nothing, no step and no write: a group of fewer than two plain
// widgets, a member moved past the end of its group, a style, a size or a
// visibility it has already. Such a step was a Ctrl+Z that seemed to do
// nothing, and it pushed a real one out of the thirty. The editor's own
// changes (EditLayer) and Settings > Widgets go through it.
//   layout:   LayoutService (config, undoStack, beginChange, save)
//   callback: the edit, through the service's own operations
// Returns whether the layout changed.
function change(layout, callback) {
    const before = JSON.stringify(layout.config)
    const steps = layout.undoStack
    layout.beginChange()
    callback()
    if (JSON.stringify(layout.config) === before) {
        // The list as it was before: with thirty steps in it, the one taken
        // had pushed the oldest out.
        layout.undoStack = steps
        return false
    }
    layout.save()
    return true
}
