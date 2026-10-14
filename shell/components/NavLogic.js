.pragma library

// Keyboard navigation inside a panel that has no form of its own (control
// center, dashboard, notification center, popups). Tab walks the controls in
// the order they are declared, the arrow keys move to the nearest control in
// that direction. A control is anything of ours that offers `focusOnTab`
// (ShellButton, ShellToggle, ListRow, QuickTile, ChipButton, the selects,
// sliders and fields) and can be seen and used; it does not have to have
// asked for Tab focus, because a panel that navigates wants all of them.

function usable(item) {
    if (!item || !item.visible || item.width <= 0 || item.height <= 0) return false
    if (item.enabled === false || item.enabledState === false || item.available === false) return false
    return item.activeFocusOnTab === true || item.focusOnTab !== undefined
}

// Every usable control under `root`, in declaration (tree) order. Hidden
// branches are skipped whole: a page that is not shown is not in the walk.
function focusables(root) {
    const found = []
    function walk(item) {
        if (!item || item.visible === false) return
        if (item !== root && usable(item)) { found.push(item); return }
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i])
    }
    walk(root)
    return found
}

// The control `current` sits in, if any: focus can rest on a part of a
// control (a field's text input) rather than on the control itself.
function owner(list, current) {
    for (let item = current; item; item = item.parent)
        if (list.indexOf(item) >= 0) return item
    return null
}

function tabStep(root, current, backwards) {
    const list = focusables(root)
    if (!list.length) return null
    const at = list.indexOf(owner(list, current))
    if (at < 0) return backwards ? list[list.length - 1] : list[0]
    return list[(at + (backwards ? -1 : 1) + list.length) % list.length]
}

function centre(root, item) {
    const point = item.mapToItem(root, item.width / 2, item.height / 2)
    return { x: point.x, y: point.y }
}

// dx/dy: the direction (-1, 0 or 1 each). The nearest control whose centre
// lies that way (inside a cone) wins, a sideways offset counting double, so
// Down from a tile picks the one under it rather than one diagonally beside it.
function arrowStep(root, current, dx, dy) {
    const list = focusables(root)
    if (!list.length) return null
    const from = owner(list, current)
    if (!from) return list[0]
    const origin = centre(root, from)
    let best = null, bestScore = Infinity
    for (const item of list) {
        if (item === from) continue
        const c = centre(root, item)
        const along = (c.x - origin.x) * dx + (c.y - origin.y) * dy
        if (along <= 1) continue
        const across = Math.abs((c.x - origin.x) * dy) + Math.abs((c.y - origin.y) * dx)
        // Only what lies roughly that way: Right from the last tile of a row
        // must not climb to a header button above and beside it.
        if (across > along * 1.5) continue
        const score = along + across * 2
        if (score < bestScore) { best = item; bestScore = score }
    }
    return best
}
