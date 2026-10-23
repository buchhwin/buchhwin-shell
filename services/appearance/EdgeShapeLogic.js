.pragma library

// A body that hangs from a screen edge the way the notch hangs from the top
// one: concave ears where it meets the edge, convex corners on the side away
// from it (shell/notch/Notch.qml draws the top edge's). The dock "on the
// edge" (dock.shape "attached") draws it on the bottom, left or right edge
// with the notch's colour, ear and radius. Unit tested in EdgeShapeTest.qml.
//
// Worked out in the edge's own terms - `u` along the edge, `v` away from it -
// and mapped onto the surface. The top edge is the notch's own picture; the
// bottom and the left one are mirror images of it, so every arc turns the
// other way; the right one is the top one turned, which keeps them.

// The parts that fit: the ear no wider than the room beside the body on the
// edge, the corners no rounder than half the body's depth or length.
function fit(start, end, depth, ear, radius, extent) {
    const length = Math.max(0, end - start)
    const room = Math.max(0, Math.min(start, extent - end))
    return {
        ear: Math.max(0, Math.min(Number(ear) || 0, room, depth / 2)),
        radius: Math.max(0, Math.min(Number(radius) || 0, depth / 2, length / 2))
    }
}

// The outline as the seven segments a ShapePath takes: a start point, then
// ear, side, corner, far side, corner, side, ear - lines and arcs, each arc
// with its turn. `edge`: "top" | "bottom" | "left" | "right"; `start`/`end`:
// the body along the edge; `depth`: how far it reaches from the edge;
// `width`/`height`: the surface, whose edge it is. Never closed: the fill
// closes it along the edge.
function outline(edge, start, end, depth, ear, radius, width, height) {
    const vertical = edge === "left" || edge === "right"
    const extent = vertical ? height : width
    const sized = fit(start, end, depth, ear, radius, extent)
    const e = sized.ear, r = sized.radius
    // Along the edge, away from it -> the surface.
    const at = (u, v) => edge === "bottom" ? { x: u, y: height - v }
        : edge === "left" ? { x: v, y: u }
        : edge === "right" ? { x: width - v, y: u }
        : { x: u, y: v }
    // The notch's arcs: a concave ear turns clockwise, a convex corner the
    // other way, on the top edge and its turned copy on the right.
    const mirrored = edge === "bottom" || edge === "left"
    const concave = !mirrored
    const convex = mirrored
    const point = (u, v) => at(u, v)
    const arc = (u, v, size, clockwise) => Object.assign(point(u, v), { arc: true, radius: size, clockwise: clockwise })
    const line = (u, v) => Object.assign(point(u, v), { arc: false, radius: 0, clockwise: false })
    return {
        ear: e, radius: r,
        start: point(start - e, 0),
        segments: [
            arc(start, e, e, concave),
            line(start, depth - r),
            arc(start + r, depth, r, convex),
            line(end - r, depth),
            arc(end, depth - r, r, convex),
            line(end, e),
            arc(end + e, 0, e, concave)
        ]
    }
}
