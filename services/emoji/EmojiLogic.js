.pragma library

// Searching and ranking for the emoji picker, and the small store of the ones
// that were used before. The list itself is config/emoji.json, built once from
// the Unicode and CLDR data by scripts/build-emoji-data.py.

var MAX_RECENT = 48
var TONES = ["", "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]
var TONE_LABELS = ["Default", "Light", "Medium light", "Medium", "Medium dark", "Dark"]

// A skin tone is written straight after the emoji, and only where Unicode says
// one belongs: everything else is returned untouched.
function withTone(entry, tone) {
    if (!entry) return ""
    const index = Math.max(0, Math.min(TONES.length - 1, Math.floor(Number(tone) || 0)))
    if (!index || entry.m !== 1) return entry.e
    return entry.e + TONES[index]
}

// The base emoji of something that may already carry a tone, so a remembered
// one still matches the list.
function withoutTone(text) {
    let value = String(text || "")
    for (const tone of TONES)
        if (tone.length && value.endsWith(tone)) value = value.slice(0, -tone.length)
    return value
}

function score(name, keywords, query) {
    if (name === query) return 100
    if (name.indexOf(query) === 0) return 80
    // A word of the name, so "smiling face with heart" is found by "heart".
    if (name.split(" ").some(word => word.indexOf(query) === 0)) return 60
    if (name.indexOf(query) >= 0) return 40
    for (const word of keywords) {
        if (word === query) return 50
        if (word.indexOf(query) === 0) return 30
    }
    return 0
}

// → the entries of `list` that match, best first. An empty query keeps the
// list's own order, which is the group order the file was built in.
function search(list, query, group, limit) {
    const text = String(query || "").trim().toLowerCase()
    const wanted = String(group || "")
    const max = limit > 0 ? limit : 500
    const rows = []
    for (const entry of list || []) {
        if (wanted.length && wanted !== "recent" && entry.g !== wanted) continue
        if (!text.length) {
            rows.push({ entry: entry, score: 0 })
            if (rows.length >= max && !wanted.length) break
            continue
        }
        const value = score(entry.n, entry.k, text)
        if (value > 0) rows.push({ entry: entry, score: value })
    }
    if (text.length)
        rows.sort((a, b) => b.score - a.score || (a.entry.n < b.entry.n ? -1 : a.entry.n > b.entry.n ? 1 : 0))
    return rows.slice(0, max).map(row => row.entry)
}

// ---- what was used before -------------------------------------------------

function parseRecent(text) {
    let data = null
    try { data = JSON.parse(text) } catch (error) { return [] }
    if (!data || data.version !== 1 || !Array.isArray(data.recent)) return []
    return data.recent.filter(value => typeof value === "string" && value.length > 0 && value.length <= 32)
                      .slice(0, MAX_RECENT)
}

function serializeRecent(recent) {
    return JSON.stringify({ version: 1, recent: (recent || []).slice(0, MAX_RECENT) }, null, 2) + "\n"
}

// Most recent first, each emoji once.
function remember(recent, text) {
    const value = String(text || "")
    if (!value.length) return (recent || []).slice()
    return [value].concat((recent || []).filter(entry => entry !== value)).slice(0, MAX_RECENT)
}

// The remembered emoji as list entries, so the grid can show them like the
// rest. One that is no longer in the list (an older build) is dropped.
function recentEntries(recent, list) {
    const byText = {}
    for (const entry of list || []) byText[entry.e] = entry
    const rows = []
    for (const value of recent || []) {
        const base = byText[withoutTone(value)]
        if (base) rows.push({ e: value, n: base.n, k: base.k, g: "recent", m: base.m })
    }
    return rows
}
