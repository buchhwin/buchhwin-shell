.pragma library
.import "../updates/UpdatesLogic.js" as Updates

// Words and decisions for the snapshots of the whole setup (scripts/snapshot.py,
// services/SnapshotService.qml, Settings > Profiles "Backups"). Pure; unit
// tested in tests/qml/SnapshotTest.qml.

var KINDS = {
    "daily": "Daily",
    "manual": "Kept by hand",
    "before-restore": "Before a restore",
    "before-import": "Before an import"
}
// What the page shows before "Show all".
var SHOWN = 5
// How long a failed day's snapshot waits before the next write tries again.
var RETRY_MS = 60 * 60000
var SNAPSHOT_NAME = /^(daily|manual|before-restore|before-import)-[0-9]{4}-[0-9]{2}-[0-9]{2}(-[0-9]{6})?(-[0-9]+)?\.tar\.gz$/

function validName(name) {
    return typeof name === "string" && SNAPSHOT_NAME.test(name)
}

function kindLabel(kind) {
    return KINDS[kind] || "Snapshot"
}

// The helper's one JSON line (the last one that parses); null without one.
function parseAnswer(text) {
    const lines = String(text || "").split("\n").map(line => line.trim()).filter(line => line.length)
    for (let i = lines.length - 1; i >= 0; --i) {
        try {
            const value = JSON.parse(lines[i])
            if (value && typeof value === "object" && !Array.isArray(value)) return value
        } catch (error) {
            continue
        }
    }
    return null
}

// `list`'s snapshots, checked: a name the helper would take, a count and a
// size that are numbers. Anything else is left out.
function snapshots(answer) {
    if (!answer || answer.ok !== true || !Array.isArray(answer.snapshots)) return []
    return answer.snapshots.filter(item => item && validName(item.name)).map(item => ({
        name: item.name,
        kind: KINDS[item.kind] ? item.kind : "manual",
        created: typeof item.created === "string" ? item.created : "",
        files: Math.max(0, Number(item.files) || 0),
        size: Math.max(0, Number(item.size) || 0)
    }))
}

function sizeText(bytes) {
    const value = Number(bytes) || 0
    if (value < 1000) return value + " B"
    if (value < 1000000) return Math.round(value / 1000) + " KB"
    return (value / 1000000).toFixed(1).replace(/\.0$/, "") + " MB"
}

// "Today, 09:30", "Yesterday, 18:02", "Oct 12, 08:15" - the Updates page's
// words for a time.
function whenText(created, now) {
    const time = Date.parse(String(created || ""))
    return isFinite(time) ? Updates.checkedText(time, now) : "Unknown time"
}

function subtitle(item) {
    if (!item) return ""
    return kindLabel(item.kind) + " · " + item.files + (item.files === 1 ? " file" : " files") + " · " + sizeText(item.size)
}

// A member of the archive as the user knows it.
function fileLabel(path) {
    const text = String(path || "")
    if (text === "state/state.json") return "notification rules"
    const slash = text.indexOf("/")
    return slash >= 0 ? text.slice(slash + 1) : text
}

// `inspect`'s list → what importing changes, for the confirmation:
// { replaced: [labels], added: [labels], same: N }.
function importPlan(files) {
    const plan = { replaced: [], added: [], same: 0 }
    for (const item of files || []) {
        if (!item || typeof item.path !== "string") continue
        if (item.state === "same") plan.same += 1
        else if (item.state === "new") plan.added.push(fileLabel(item.path))
        else plan.replaced.push(fileLabel(item.path))
    }
    return plan
}

function joined(list, limit) {
    const shown = list.slice(0, limit)
    return shown.join(", ") + (list.length > limit ? " and " + (list.length - limit) + " more" : "")
}

function importText(plan) {
    if (!plan) return ""
    const parts = []
    if (plan.replaced.length) parts.push("Replaces " + joined(plan.replaced, 6))
    if (plan.added.length) parts.push((parts.length ? "adds " : "Adds ") + joined(plan.added, 4))
    if (!parts.length) return "Holds nothing that differs from your setup now."
    return parts.join("; ") + (plan.same ? "; " + plan.same + " unchanged." : ".")
        + " A copy of your setup now is kept first, and the shell restarts."
}

// After a restore or an import: whether the shell has to read everything again.
function needsRestart(answer) {
    return !!answer && answer.ok === true && Array.isArray(answer.written) && answer.written.length > 0
}

function resultText(command, answer) {
    if (!answer) return "The snapshot helper did not answer"
    if (answer.ok !== true) return (typeof answer.error === "string" && answer.error.length ? answer.error : "It did not work")
    if (command === "export") return "Exported " + answer.files + (answer.files === 1 ? " file" : " files") + " to " + answer.path
    if (command === "take") return "Kept a copy of the setup now"
    if (command === "restore" || command === "import") {
        const count = Array.isArray(answer.written) ? answer.written.length : 0
        if (!count) return "Nothing differed - your setup is as it was"
        return (command === "restore" ? "Restored " : "Imported ") + count + (count === 1 ? " file" : " files")
            + ". The shell restarts to read them."
    }
    return ""
}

// The file name an export offers.
function exportName(home, date) {
    const day = date.getFullYear() + "-" + ("0" + (date.getMonth() + 1)).slice(-2) + "-" + ("0" + date.getDate()).slice(-2)
    return String(home || "") + "/buchhwin-shell-setup-" + day + ".tar.gz"
}
