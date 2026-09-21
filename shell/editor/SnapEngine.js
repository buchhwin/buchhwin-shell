.pragma library

// Snap a dragged rectangle to screen edges, the screen centre, other widgets
// and an optional grid. Returns the adjusted position plus guide lines.
//   rect:   { x, y, width, height }
//   others: [{ x, y, width, height }]
//   opts:   { screenWidth, screenHeight, threshold, grid, gridSize, margin, disabled }
function snap(rect, others, opts) {
    if (opts.disabled) return { x: rect.x, y: rect.y, guides: [] }
    const threshold = opts.threshold
    const margin = opts.margin || 0

    const vertical = [
        { line: margin, kind: "edge" },
        { line: opts.screenWidth / 2, kind: "center" },
        { line: opts.screenWidth - margin, kind: "edge" }
    ]
    const horizontal = [
        { line: margin, kind: "edge" },
        { line: opts.screenHeight / 2, kind: "center" },
        { line: opts.screenHeight - margin, kind: "edge" }
    ]
    for (const other of others) {
        vertical.push({ line: other.x, kind: "widget" }, { line: other.x + other.width / 2, kind: "widget" },
                      { line: other.x + other.width, kind: "widget" })
        horizontal.push({ line: other.y, kind: "widget" }, { line: other.y + other.height / 2, kind: "widget" },
                        { line: other.y + other.height, kind: "widget" })
    }

    function best(start, size, candidates) {
        const edges = [start, start + size / 2, start + size]
        let result = null
        for (const candidate of candidates) {
            for (let i = 0; i < edges.length; ++i) {
                const distance = Math.abs(edges[i] - candidate.line)
                if (distance <= threshold && (!result || distance < result.distance))
                    result = { distance: distance, offset: candidate.line - edges[i], line: candidate.line }
            }
        }
        return result
    }

    let x = rect.x
    let y = rect.y
    const guides = []
    const snapX = best(rect.x, rect.width, vertical)
    const snapY = best(rect.y, rect.height, horizontal)
    if (snapX) { x += snapX.offset; guides.push({ orientation: "vertical", position: snapX.line }) }
    else if (opts.grid && opts.gridSize > 0) x = Math.round(x / opts.gridSize) * opts.gridSize
    if (snapY) { y += snapY.offset; guides.push({ orientation: "horizontal", position: snapY.line }) }
    else if (opts.grid && opts.gridSize > 0) y = Math.round(y / opts.gridSize) * opts.gridSize

    x = Math.max(0, Math.min(opts.screenWidth - rect.width, x))
    y = Math.max(0, Math.min(opts.screenHeight - rect.height, y))
    return { x: x, y: y, guides: guides }
}
