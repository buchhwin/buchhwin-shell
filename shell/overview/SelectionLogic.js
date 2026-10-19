.pragma library
.import "../../services/overview/OverviewLogic.js" as Overview

// What the overview's keys have selected, as an index into its stops
// (`stops` below): the windows the search leaves and, while nothing is typed,
// the workspace cards too. Kept beside the overview rather than in
// services/overview: it is the panel's own key handling, not a fact about the
// compositor.
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

// The stops the keys walk, in the order the overview draws them: row by row
// (one per monitor), card by card, each card's windows in reading order and
// then the card itself, a row's "New workspace" card last. Only windows were
// stops before, so an empty workspace - most cards with "Keep empty
// workspaces open" - could not be reached, switched to or closed without the
// mouse. While a search is typed only the windows that match are stops: the
// question is then about windows, and a card cannot match a query.
//
// `rows` is OverviewLogic.groups(). Each stop is { kind: "window" | "card" |
// "new", key, row, card, workspace } with `window` (a window's entry) or
// `entry` (the card's) and `closable` (whether Delete may close the card).
function stops(rows, query) {
    const typed = String(query || "").trim().length > 0
    const result = []
    const list = rows || []
    list.forEach((row, rowIndex) => {
        const cards = (row.workspaces || []).concat(row.newCard ? [row.newCard] : [])
        cards.forEach((card, cardIndex) => {
            const windows = (card.windows || []).filter(window => Overview.matches(window, query))
                .sort((a, b) => a.y - b.y || a.x - b.x)
            for (const window of windows)
                result.push({ kind: "window", key: "w:" + window.address, row: rowIndex, card: cardIndex,
                              workspace: card.id, window: window })
            if (typed) return
            const fresh = card.placeholder === true
            result.push({ kind: fresh ? "new" : "card", key: fresh ? "n:" + row.monitor : "c:" + card.id,
                          row: rowIndex, card: cardIndex, workspace: card.id, entry: card,
                          closable: Overview.closable(card, row) })
        })
    })
    return result
}

// The stop the overview opens on: the first window, as before there were
// cards to select - Enter right after Super+W still focuses it - else the
// first stop.
function openingIndex(list) {
    const found = (list || []).findIndex(stop => stop.kind === "window")
    return found >= 0 ? found : 0
}

// Where the selection is once the stops changed: on the same stop when it is
// still there (a window opened or closed elsewhere moves every index after
// it), else at the index it had, held inside the list.
function indexOf(list, key, fallback) {
    const found = key ? (list || []).findIndex(stop => stop.key === key) : -1
    return found >= 0 ? found : clamp(fallback, (list || []).length)
}

// Up (-1) and Down (+1): the nearest card one line above or below, on the
// grid the cards are drawn on - `columns` cards a line, and every monitor's
// row starting a line of its own, so from the last line of one row they reach
// the other monitor's. From a window they go by the card it is on. Where there
// is no line that way (a single line of cards, the first or the last line, or
// a search that leaves windows only) they step like Left and Right, as they
// always did, so the arrows never go dead.
function vertical(list, selected, delta, columns) {
    const all = list || []
    const current = clamp(selected, all.length)
    const here = all[current]
    const width = Math.max(1, Math.floor(Number(columns)) || 1)
    const lines = []
    all.forEach((stop, index) => {
        if (stop.kind === "window") return
        const line = Math.floor(stop.card / width)
        let last = lines[lines.length - 1]
        if (!last || last.row !== stop.row || last.line !== line) {
            last = { row: stop.row, line: line, cards: [] }
            lines.push(last)
        }
        last.cards.push({ column: stop.card % width, index: index })
    })
    const at = here ? lines.findIndex(line => line.row === here.row && line.line === Math.floor(here.card / width)) : -1
    const target = at >= 0 ? lines[at + (delta < 0 ? -1 : 1)] : null
    if (!target) return step(current, delta < 0 ? -1 : 1, all.length)
    const column = here.card % width
    let best = target.cards[0]
    for (const card of target.cards)
        if (Math.abs(card.column - column) < Math.abs(best.column - column)) best = card
    return best.index
}
