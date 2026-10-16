.pragma library

// A device's name the way a row has room for it. PipeWire names an ALSA
// device "<card> <port>" - "Ryzen HD Audio Controller Speaker", "Ryzen HD
// Audio Controller Digital Microphone" - and a row elides at the right, so
// the part that told two devices apart was always the part cut off: two
// microphones read "Ryzen HD Audio Controller…" and only the selection tint
// said which was which. The row's title is the port now, the card the line
// under it.

function words(text) {
    return String(text || "").trim().split(/\s+/).filter(word => word.length > 0)
}

// How many leading words two word lists share.
function sharedWords(first, second) {
    let count = 0
    while (count < first.length && count < second.length && first[count] === second[count]) count += 1
    return count
}

// → { title, subtitle } for `label` (the node's description). `port` is the
// node's `device.profile.description` when PipeWire gave one (it does once
// the node is bound): the label ends with it, and the rest is the card. For
// a node without one, the words it shares with another device of the same
// list (`others`, their labels) are the card. A label that is all card, or
// one that shares nothing, stays whole.
function split(label, port, others) {
    const full = words(label).join(" ")
    const tail = words(port).join(" ")
    if (tail.length && full.length > tail.length + 1 && full.endsWith(" " + tail))
        return { title: tail, subtitle: full.slice(0, full.length - tail.length - 1) }
    const own = words(full)
    let shared = 0
    for (const other of Array.prototype.slice.call(others || []))
        shared = Math.max(shared, sharedWords(own, words(other)))
    if (shared > 0 && shared < own.length)
        return { title: own.slice(shared).join(" "), subtitle: own.slice(0, shared).join(" ") }
    return { title: full, subtitle: "" }
}

// The device in a line that says something else first ("In use · …", the
// volume popup's microphone): the title where the card goes without saying -
// the only device, or another of the list has the same card - else the
// whole label. A USB headset's port is its profile ("Jabra Evolve2 65
// Mono"): beside the laptop's microphones its title alone read "In use ·
// Mono", with the headset's name dropped.
function shortName(label, port, others) {
    const parts = split(label, port, others)
    const list = Array.prototype.slice.call(others || [])
    if (!parts.subtitle.length || !list.length) return parts.title
    const card = words(parts.subtitle)
    const sibling = list.some(other => {
        const otherWords = words(other)
        return otherWords.length > card.length && sharedWords(card, otherWords) === card.length
    })
    return sibling ? parts.title : words(label).join(" ")
}
