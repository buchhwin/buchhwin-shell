.pragma library

// Per-app output routing through PipeWire's "default" metadata. WirePlumber
// links a stream to the node named by its `target.object` entry and, unless
// the stream opts out, remembers that choice per app (state-stream.lua only
// resolves `object.serial` values, so moves write the sink's serial as
// `Spa:Id`, exactly like WirePlumber itself). Deleting the entry sends the
// stream back to the default output and forgets the choice.

// node.name of the Settings level meter stream (scripts/audio-level.py).
var METER_NODE = "buchhwin-shell-level-meter"

// One line of `pw-metadata [-m] -n default` output:
//   update: id:90 key:'target.object' value:'973' type:'Spa:Id'
//   remove: id:90 key:'target.object'
//   remove: id:90 all keys
// Returns null for everything else ("Found …", set/delete confirmations).
function parseLine(line) {
    const text = String(line || "").replace(/\r?\n$/, "")
    let match = /^update: id:(\d+) key:'(.*?)' value:'(.*)' type:'(.*)'$/.exec(text)
    if (match) {
        return { action: "update", subject: Number(match[1]), key: match[2],
                 value: match[3] === "(null)" ? null : match[3], type: match[4] === "(null)" ? "" : match[4] }
    }
    match = /^remove: id:(\d+) key:'(.*)'$/.exec(text)
    if (match) return { action: "remove", subject: Number(match[1]), key: match[2] }
    match = /^remove: id:(\d+) all keys$/.exec(text)
    if (match) return { action: "removeAll", subject: Number(match[1]) }
    return null
}

// Entries are { "<subject id>": { "<key>": { value, type } } }. Returns a new
// object when the line changes something, otherwise the same one.
function applyLine(entries, line) {
    const item = parseLine(line)
    const current = entries || {}
    if (!item) return current
    const subject = String(item.subject)
    const next = Object.assign({}, current)
    if (item.action === "removeAll") {
        if (!(subject in current)) return current
        delete next[subject]
        return next
    }
    const keys = Object.assign({}, current[subject] || {})
    if (item.action === "remove" || item.value === null) {
        if (!(item.key in keys)) return current
        delete keys[item.key]
    } else {
        keys[item.key] = { value: item.value, type: item.type }
    }
    if (Object.keys(keys).length) next[subject] = keys
    else delete next[subject]
    return next
}

function parseMetadata(text) {
    return String(text || "").split("\n").reduce((entries, line) => applyLine(entries, line), {})
}

// Sinks are { id, name, serial }. Returns the node.name of the sink the
// stream is routed to, or "" when it follows the default output (no entry,
// "-1", or a target that no longer exists).
function streamTarget(entries, streamId, sinks) {
    const keys = (entries || {})[String(streamId)]
    if (!keys) return ""
    const list = sinks || []
    const object = keys["target.object"]
    if (object && object.value !== null && object.value !== "-1") {
        const value = object.value
        const found = /^\d+$/.test(value)
            ? list.find(sink => String(sink.serial) === value)
            : list.find(sink => sink.name === value)
        return found ? found.name : ""
    }
    const node = keys["target.node"]
    if (node && /^\d+$/.test(node.value || "")) {
        const found = list.find(sink => String(sink.id) === node.value)
        return found ? found.name : ""
    }
    return ""
}

function validId(value) {
    return typeof value === "number" && Number.isInteger(value) && value > 0
        || typeof value === "string" && /^[1-9]\d*$/.test(value)
}

function validName(value) {
    return typeof value === "string" && /^[A-Za-z0-9_.:@+-]+$/.test(value) && !value.startsWith("-")
}

// argv that routes the stream to the sink; [] for invalid input.
function moveCommand(streamId, sink) {
    if (!validId(streamId) || !sink) return []
    const base = ["pw-metadata", "-n", "default", String(streamId), "target.object"]
    if (validId(sink.serial)) return base.concat([String(sink.serial), "Spa:Id"])
    if (validName(sink.name)) return base.concat([sink.name])
    return []
}

// argv lists that send the stream back to the default output. target.object
// is always removed (the known entries may lag behind); a legacy
// target.node entry only when present.
function resetCommands(entries, streamId) {
    if (!validId(streamId)) return []
    const commands = [["pw-metadata", "-n", "default", "-d", String(streamId), "target.object"]]
    const keys = (entries || {})[String(streamId)] || {}
    if (keys["target.node"]) commands.push(["pw-metadata", "-n", "default", "-d", String(streamId), "target.node"])
    return commands
}

// Options for the output selector: "" = default output, then every sink.
function outputOptions(sinks, defaultLabel) {
    const options = [{ value: "", label: defaultLabel || "Default output" }]
    for (const sink of sinks || []) {
        if (sink && sink.name) options.push({ value: sink.name, label: sink.label || sink.name })
    }
    return options
}

function isMeterStream(name) {
    return name === METER_NODE
}
