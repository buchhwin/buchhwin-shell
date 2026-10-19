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
        if (item !== root && usable(item)) {
            found.push(item)
            // A row's own controls sit inside the row, which is a stop
            // itself (ListRow's `trailing`: a Remove beside a device, a
            // volume's Unmount and Lock): they are stops after it. Anything
            // else a stop holds is part of it.
            const trailing = item.trailing
            if (trailing && trailing.length !== undefined)
                for (let i = 0; i < trailing.length; ++i) walk(trailing[i])
            return
        }
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

// Brings `item` into view in the lists around it. The walk focuses controls
// wherever they are, scrolled out of sight or not, and the ring of a card
// below the fold of the notification center was drawn where nobody could
// see it. Each Flickable it sits in, from the nearest out, is moved just
// enough to show it with `air` around it (as far as the list goes); one the
// item is already shown in stays where it is. Returns how many moved.
function reveal(item, air) {
    const pad = Math.max(0, Number(air) || 0)
    let moved = 0
    let inner = item
    for (let node = item ? item.parent : null; node; node = node.parent) {
        if (node.contentItem === undefined || node.contentY === undefined || node.contentHeight === undefined) continue
        const at = inner.mapToItem(node.contentItem, 0, 0)
        if (node.height > 0 && reveals(node, "y", at.y - pad, inner.height + pad * 2)) moved += 1
        if (node.width > 0 && reveals(node, "x", at.x - pad, inner.width + pad * 2)) moved += 1
        inner = node
    }
    return moved
}

// One axis of `reveal`: the content position that shows [start, start +
// size), inside the list's own bounds (its origin and margins, as a
// ListView keeps them).
function reveals(view, axis, start, size) {
    const vertical = axis === "y"
    const here = vertical ? view.contentY : view.contentX
    const span = vertical ? view.height : view.width
    const content = vertical ? view.contentHeight : view.contentWidth
    if (!(content > span)) return false
    const low = (vertical ? view.originY - view.topMargin : view.originX - view.leftMargin) || 0
    const high = Math.max(low, low + (vertical ? view.topMargin + view.bottomMargin : view.leftMargin + view.rightMargin)
                               + content - span)
    let to = here
    if (start < here) to = start
    else if (start + size > here + span) to = Math.min(start, start + size - span)
    to = Math.max(low, Math.min(high, to))
    if (Math.abs(to - here) < 0.5) return false
    if (vertical) view.contentY = to
    else view.contentX = to
    return true
}
