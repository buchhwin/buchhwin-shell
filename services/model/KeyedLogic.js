.pragma library

// Quickshell 0.3.2's ScriptModel with `objectProp` matches rows by their key
// only until it meets an entry whose key it knows but whose object is new:
// that one is updated in place, and from there on rows are handed on by
// position - without looking at the key again - until it meets the very
// same object. A list built anew on every change never has one, so taking an
// entry out of the middle gave every row after it its neighbour's data and
// destroyed the last delegate instead of the one that went (probed offscreen
// on 15.10.; an update of the first entry and an add at the end, which is all
// the first check tried, come out right either way). Handed the previous
// objects wherever nothing changed, the model matches by identity, which it
// gets right taken out, put in, moved and changed.
//
// keep(previous, next, key[, children]): `next`, with every entry whose `key`
// is in `previous` and whose content did not change replaced by the previous
// object. `children` names arrays inside an entry to keep the same way, with
// their own key ({ windows: "address" }): a workspace whose windows changed is
// a new object, but the windows in it that did not are the old ones.
function keep(previous, next, key, children) {
    const before = {}
    for (const entry of previous || [])
        if (entry !== null && typeof entry === "object" && entry[key] !== undefined)
            before[String(entry[key])] = entry
    return (next || []).map(entry => {
        if (entry === null || typeof entry !== "object" || entry[key] === undefined) return entry
        const old = before[String(entry[key])]
        if (!old) return entry
        let candidate = entry
        if (children) {
            candidate = Object.assign({}, entry)
            for (const name of Object.keys(children))
                if (Array.isArray(entry[name]))
                    candidate[name] = keep(old[name], entry[name], children[name])
        }
        return JSON.stringify(old) === JSON.stringify(candidate) ? old : candidate
    })
}
