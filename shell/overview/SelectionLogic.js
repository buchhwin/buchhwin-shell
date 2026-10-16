.pragma library

// Which window thumbnail the overview's keys have selected, as an index into
// the windows the search leaves (`flat`). Kept beside the overview rather
// than in services/overview: it is the panel's own key handling, not a
// fact about the compositor.
//
// The index never goes below zero. Down or Right with nothing to select used
// to compute `Math.min(count - 1, selected + 1)` = -1, the list's next change
// kept the -1, and `flat[-1]` - undefined - then threw in every thumbnail's
// binding ("Cannot read property address of undefined"): no thumbnail was
// highlighted and Enter did nothing until Up or Right was pressed.

// The selection after the list changed to `count` entries.
function clamp(selected, count) {
    const last = Math.max(0, (Number(count) || 0) - 1)
    const index = Math.floor(Number(selected) || 0)
    return Math.max(0, Math.min(index, last))
}

// One step back (-1) or on (+1), held at both ends.
function step(selected, delta, count) {
    return clamp(clamp(selected, count) + delta, count)
}
