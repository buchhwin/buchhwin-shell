.pragma library

// Launch history for ranking apps by frecency (how often and how recently
// they were started). Stored in the state directory as launcher.json. Unit
// tested.

var HALF_LIFE_DAYS = 14
var MAX_ENTRIES = 200

function parse(text) {
    let data = null
    try { data = JSON.parse(text) } catch (error) { return {} }
    const result = {}
    if (!data || data.version !== 1 || typeof data.apps !== "object" || data.apps === null) return result
    for (const id of Object.keys(data.apps)) {
        const entry = data.apps[id]
        if (!/^[A-Za-z0-9._-]+$/.test(id) || !entry) continue
        const count = Math.max(0, Math.floor(Number(entry.count) || 0))
        const last = Number(entry.last) || 0
        if (count > 0 && last > 0) result[id] = { count: count, last: last }
    }
    return result
}

function serialize(usage) {
    return JSON.stringify({ version: 1, apps: usage }, null, 2) + "\n"
}

function record(usage, id, now) {
    const next = Object.assign({}, usage)
    const previous = next[id] || { count: 0, last: 0 }
    next[id] = { count: previous.count + 1, last: now }
    const ids = Object.keys(next)
    if (ids.length > MAX_ENTRIES) {
        ids.sort((a, b) => next[a].last - next[b].last)
        for (const old of ids.slice(0, ids.length - MAX_ENTRIES)) delete next[old]
    }
    return next
}

// Frecency score: launch count decayed by age (half-life in days).
function frecency(usage, id, now) {
    const entry = usage[id]
    if (!entry) return 0
    const days = Math.max(0, (now - entry.last) / 86400000)
    return entry.count * Math.pow(0.5, days / HALF_LIFE_DAYS)
}

// Small boost for matching apps so often used ones win ties, never enough to
// beat a clearly better text match (match scores step by 20).
function boost(usage, id, now) {
    const value = frecency(usage, id, now)
    return value > 0 ? Math.min(15, 5 * Math.log(1 + value)) : 0
}
