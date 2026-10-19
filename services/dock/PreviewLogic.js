.pragma library

// Window previews on the dock (`dock.previews`, shell/dock/DockPreview.qml):
// the pointer resting on a running app shows a strip of its windows - live
// captures with their titles - where its name would show. Several Brave or
// Citrix windows behind one icon were told apart by their titles in the
// right-click menu only.
//
// The strip is a surface of its own: the dock's surface keeps room for a
// name above its icons, not for pictures. That surface has one size for as
// long as it is up, whatever the app (a layer surface that changes size can
// show a frame at the old size, testing.md pitfall 57): as wide as the
// widest strip, at most the screen, and the strip itself sits in it next to
// the icon. It stands against the dock's body, the strip a `bridge` off it,
// and the input mask is the strip and the bridge below it: the pointer goes
// from the icon to the strip without ever leaving the two surfaces - over a
// window between them, the focus would follow it there.

// Whether the pointer on `app` shows its windows rather than its name: an app
// with windows - the shell's own Settings has none to show.
function wanted(on, app) {
    return on === true && !!app && !app.special && Array.prototype.slice.call(app.windows || []).length > 0
}

// The strip: `count` cards of `card` { width, height } with `gap` between
// them and `pad` around, at most `maxCards` wide - more scroll.
function stripSize(count, card, gap, pad, maxCards) {
    const n = Math.max(1, Math.min(Math.round(Number(count) || 0), Math.max(1, Math.round(Number(maxCards) || 1))))
    const c = card || { width: 0, height: 0 }
    return { width: n * c.width + (n - 1) * gap + 2 * pad, height: c.height + 2 * pad }
}

function vertical(edge) { return edge === "left" || edge === "right" }

// The surface: the widest strip and the bridge on the dock's side of it,
// never wider than the screen.
function surfaceSize(edge, card, gap, pad, maxCards, screen, bridge) {
    const widest = stripSize(maxCards, card, gap, pad, maxCards)
    const b = Math.max(0, Number(bridge) || 0)
    const room = screen && screen.width > 0 ? screen.width : Infinity
    return vertical(edge) ? { width: Math.min(widest.width + b, room), height: widest.height }
                          : { width: Math.min(widest.width, room), height: widest.height + b }
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(Math.max(low, high), value))
}

// The body a magnifying dock draws its icons into: `grow` past the body at
// rest towards the screen, as far as the dock's own input reaches then
// (Dock.qml). The strip stands off that, or the icon under the pointer -
// the one magnified - would grow under the strip, and its top would be the
// strip's input instead of the dock's.
function grown(edge, body, grow) {
    const g = Math.max(0, Number(grow) || 0)
    if (!body || g === 0) return body || null
    if (edge === "left") return { x: body.x, y: body.y, width: body.width + g, height: body.height }
    if (edge === "right") return { x: body.x - g, y: body.y, width: body.width + g, height: body.height }
    return { x: body.x, y: body.y - g, width: body.width, height: body.height + g }
}

// Where the surface stands on the screen (`x`, `y`, screen-local - its layer
// margins from the top-left corner), where the strip is inside it (`stripX`,
// `stripY`) and the input mask (`mask`: the strip and its bridge). Against
// the dock's body (`body`, screen-local): above a bottom dock, beside a side
// one; centred on the icon (`icon`, screen-local) along the edge, kept on
// the screen (`screen` { width, height }). `surface` is surfaceSize's,
// `strip` stripSize's.
function place(edge, icon, body, surface, strip, screen, bridge) {
    const s = surface || { width: 0, height: 0 }
    const b = Math.max(0, Number(bridge) || 0)
    const side = vertical(edge)
    const t = { width: Math.min(strip ? strip.width : 0, s.width - (side ? b : 0)),
                height: Math.min(strip ? strip.height : 0, s.height - (side ? 0 : b)) }
    const room = screen || { width: s.width, height: s.height }
    const i = icon || { x: 0, y: 0, width: 0, height: 0 }
    const d = body || i
    if (side) {
        const centre = i.y + i.height / 2
        const y = Math.round(clamp(centre - s.height / 2, 0, room.height - s.height))
        const x = Math.round(edge === "left" ? clamp(d.x + d.width, 0, room.width - s.width)
                                             : clamp(d.x - s.width, 0, room.width - s.width))
        const stripX = edge === "left" ? b : s.width - b - t.width
        const stripY = Math.round(clamp(centre - y - t.height / 2, 0, s.height - t.height))
        return { x: x, y: y, stripX: stripX, stripY: stripY,
                 mask: { x: edge === "left" ? 0 : stripX, y: stripY, width: t.width + b, height: t.height } }
    }
    const centre = i.x + i.width / 2
    const x = Math.round(clamp(centre - s.width / 2, 0, room.width - s.width))
    const stripX = Math.round(clamp(centre - x - t.width / 2, 0, s.width - t.width))
    const stripY = s.height - b - t.height
    return { x: x, y: Math.round(Math.max(0, d.y - s.height)), stripX: stripX, stripY: stripY,
             mask: { x: stripX, y: stripY, width: t.width, height: t.height + b } }
}
