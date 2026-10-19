.pragma library
.import "LaunchLogic.js" as Launch

// "Open in VS Code" in the launcher's plain search: the folders VS Code
// opened last and the folders under ~/git, opened straight in the editor
// instead of the launcher opening VS Code and the folder being picked inside
// it. scripts/launcher-code-folders.py reads them (VS Code's state database
// read-only and immutable, its storage.json, the project folders) once per
// launcher open; this is what the shell makes of its answer. Unit tested
// (tests/qml/LauncherSourcesTest.qml).

var LIMIT = 3

// The builds the script knows, by the folder their user data lives in under
// ~/.config, and the programs their desktop entries run.
var EDITORS = [
    { name: "Code", programs: ["code"] },
    { name: "Code - OSS", programs: ["code-oss"] },
    { name: "VSCodium", programs: ["codium", "vscodium"] },
    { name: "Code - Insiders", programs: ["code-insiders"] }
]

function programOf(app) {
    const command = app && app.command && app.command.length ? String(app.command[0]) : ""
    return command.split("/").pop()
}

// The installed editor: the first visible desktop entry that runs one of the
// programs (visual-studio-code-bin's is com.microsoft.VSCode, Arch's own
// code-oss, Flathub's com.visualstudio.code - the id says little, the
// program says which build it is). → { app, editor } or null.
function editorEntry(apps) {
    for (const editor of EDITORS) {
        const app = (apps || []).find(entry => entry && !entry.noDisplay && editor.programs.indexOf(programOf(entry)) >= 0)
        if (app) return { app: app, editor: editor.name }
    }
    return null
}

// The script's answer, checked: { editors: { name: [paths] }, projects: [paths] }.
function parse(text) {
    let data = null
    try {
        data = JSON.parse(String(text || ""))
    } catch (error) {
        return { editors: {}, projects: [] }
    }
    const paths = list => Array.isArray(list) ? list.filter(path => typeof path === "string" && path.startsWith("/")) : []
    const editors = {}
    const given = data && typeof data.editors === "object" && data.editors ? data.editors : {}
    for (const name of Object.keys(given)) editors[name] = paths(given[name])
    return { editors: editors, projects: paths(data && data.projects) }
}

function contractHome(path, home) {
    const prefix = String(home || "") + "/"
    if (prefix.length > 1 && path === prefix.slice(0, -1)) return "~"
    return prefix.length > 1 && path.startsWith(prefix) ? "~/" + path.slice(prefix.length) : path
}

// The editor's recent folders first, then the projects, each once, as
// { path, name, place }: name the folder's (a workspace file's without
// .code-workspace), place where it is with the home folder as ~.
function folders(parsed, editor, home) {
    const seen = {}
    const out = []
    const recent = parsed && parsed.editors && parsed.editors[editor] ? parsed.editors[editor] : []
    for (const path of recent.concat(parsed ? parsed.projects : [])) {
        const clean = path.replace(/\/+$/, "")
        if (!clean.length || seen[clean]) continue
        seen[clean] = true
        const base = clean.split("/").pop()
        out.push({ path: clean, name: base.replace(/\.code-workspace$/, ""), place: contractHome(clean, home),
                   workspace: /\.code-workspace$/.test(base) })
    }
    return out
}

// The folders a query finds by name, best first and recent first among equals.
function matches(list, query, score, limit) {
    const q = String(query || "").trim().toLowerCase()
    if (q.length < 2) return []
    return (list || [])
        .map((folder, order) => ({ folder: folder, order: order, score: score(folder.name, q) }))
        .filter(entry => entry.score > 0)
        .sort((a, b) => b.score - a.score || a.order - b.order)
        .slice(0, limit === undefined ? LIMIT : limit)
        .map(entry => entry.folder)
}

// The editor's own launch (launch-app.sh, named after its entry - LaunchLogic)
// with the folder after it: `code /path` opens it, or brings the window that
// has it open to the front.
function openContext(app, path, script) {
    const context = Launch.launchContext(app, {}, script)
    if (!context || !String(path || "").startsWith("/")) return null
    context.command = context.command.concat([String(path)])
    return context
}
