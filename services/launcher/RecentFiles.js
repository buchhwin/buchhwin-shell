.pragma library

// Recently used files in the launcher's plain search, from the list every
// GTK and KDE application keeps (~/.local/share/recently-used.xbel): no
// index and nothing running, unlike the "/" file search, which needs
// plocate's. The launcher reads the file when a query first asks for it in
// an open and forgets it when it closes. Unit tested
// (tests/qml/LauncherSourcesTest.qml).

// How many entries of the file are kept (the newest), and how many rows a
// query brings.
var KEEP = 300
var LIMIT = 3

var ENTITIES = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'" }

function unescapeXml(text) {
    return String(text).replace(/&(?:amp|lt|gt|quot|apos);|&#(\d+);|&#x([0-9a-fA-F]+);/g, (match, decimal, hex) =>
        decimal ? String.fromCharCode(Number(decimal)) : hex ? String.fromCharCode(parseInt(hex, 16)) : ENTITIES[match])
}

// A local path from a file:// URL, or "" for anything else (http, a remote
// host, a URL that does not decode).
function pathOf(href) {
    const url = unescapeXml(href)
    const match = url.match(/^file:\/\/(?:localhost)?(\/[^?#]*)$/)
    if (!match) return ""
    try {
        return decodeURIComponent(match[1])
    } catch (error) {
        return ""
    }
}

function attribute(tag, name) {
    const match = tag.match(new RegExp("\\b" + name + "=\"([^\"]*)\""))
    return match ? match[1] : ""
}

function contractHome(path, home) {
    const prefix = String(home || "") + "/"
    if (prefix.length > 1 && path === prefix.slice(0, -1)) return "~"
    return prefix.length > 1 && path.startsWith(prefix) ? "~/" + path.slice(prefix.length) : path
}

// What kind of row a file gets (its glyph), by its MIME type from the file.
function kindOf(mime, path) {
    const type = String(mime || "")
    if (type === "inode/directory") return "folder"
    if (type.startsWith("image/")) return "image"
    if (type === "application/pdf" || /\.pdf$/i.test(path)) return "pdf"
    return "file"
}

// → [{ path, name, folder, kind, time }], newest first, each path once,
// nothing from the trash. `folder` is where it is, with the home folder as ~.
function parse(text, home) {
    const trash = String(home || "") + "/.local/share/Trash/"
    const byPath = {}
    const parts = String(text || "").split("<bookmark ")
    for (let index = 1; index < parts.length; ++index) {
        const part = parts[index]
        const head = part.slice(0, part.indexOf(">") + 1)
        const path = pathOf(attribute(head, "href"))
        if (!path.length || path === "/" || path.startsWith(trash)) continue
        const time = Math.max(Date.parse(attribute(head, "modified")) || 0, Date.parse(attribute(head, "visited")) || 0,
                              Date.parse(attribute(head, "added")) || 0)
        const end = part.indexOf("</bookmark>")
        const mime = attribute(end >= 0 ? part.slice(0, end) : part, "type")
        const known = byPath[path]
        if (known && known.time >= time) continue
        const name = path.replace(/\/+$/, "").split("/").pop()
        const parent = path.slice(0, path.length - name.length).replace(/\/+$/, "") || "/"
        byPath[path] = { path: path, name: name, folder: contractHome(parent, home), kind: kindOf(mime, path), time: time }
    }
    return Object.keys(byPath).map(path => byPath[path])
        .sort((a, b) => b.time - a.time || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
        .slice(0, KEEP)
}

// The files a query finds by name, best first and newest among equals.
function matches(files, query, score, limit) {
    const q = String(query || "").trim().toLowerCase()
    if (q.length < 2) return []
    return (files || [])
        .map((file, order) => ({ file: file, order: order, score: score(file.name, q) }))
        .filter(entry => entry.score > 0)
        .sort((a, b) => b.score - a.score || a.order - b.order)
        .slice(0, limit === undefined ? LIMIT : limit)
        .map(entry => entry.file)
}
