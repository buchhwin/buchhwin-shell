.pragma library
.import "../hypr/HiddenWindows.js" as Hidden
.import "../switcher/SwitcherLogic.js" as Switcher

// Open windows in the launcher's plain search ("Switch to window"): the
// overview filters its windows by what is typed, and until now the launcher
// found apps only, so a window was a Super+W and a search away. Unit tested
// (tests/qml/LauncherSourcesTest.qml).

// How many window rows a query brings, after the best app: a launcher is
// for finding one thing, and the overview is there for all of them.
var LIMIT = 4

// Quickshell's HyprlandToplevel objects as plain ones, without the session's
// hidden helpers (services/hypr/HiddenWindows.js: their class, or the
// special workspace the window rules put them on). Address with its "0x",
// the way HyprCommands wants it (Quickshell hands it over without). The
// workspace is called what its pip calls it (SwitcherLogic.workspaceLabel;
// `order` the monitors in their blocks' order, empty without blocks).
function entries(toplevels, order) {
    const list = []
    for (const toplevel of toplevels || []) {
        if (!toplevel) continue
        const raw = String(toplevel.address || "").toLowerCase()
        const bare = raw.startsWith("0x") ? raw.slice(2) : raw
        if (!/^[0-9a-f]+$/.test(bare)) continue
        const wayland = toplevel.wayland || null
        const appId = String(wayland && wayland.appId || "")
        const workspace = toplevel.workspace || null
        const workspaceName = workspace ? String(workspace.name !== undefined ? workspace.name : workspace.id) : ""
        if (Hidden.isHiddenClass(appId) || workspaceName === Hidden.workspace) continue
        const title = String(toplevel.title || (wayland && wayland.title) || "")
        const monitor = toplevel.monitor ? toplevel.monitor.name : workspace && workspace.monitor ? workspace.monitor.name : ""
        list.push({ address: "0x" + bare, title: title, appId: appId,
                    workspace: Switcher.workspaceLabel(workspace || {}, monitor, order) })
    }
    return list
}

// The windows a query finds, best first. `score(text, query)` is the
// launcher's own (LauncherService.score), `appName(appId)` the name of the
// app a window belongs to (its desktop entry's, or the id itself). The title
// counts a little less than the app's name, as an app's generic name does
// next to its name.
function matches(windows, query, score, appName, limit) {
    const q = String(query || "").trim().toLowerCase()
    if (q.length < 2) return []
    return (windows || [])
        .map(window => ({ window: window,
                          score: Math.max(score(appName(window.appId), q), score(window.title, q) * 0.9,
                                          score(window.appId, q) * 0.8) }))
        .filter(entry => entry.score > 0)
        .sort((a, b) => b.score - a.score || a.window.title.localeCompare(b.window.title))
        .slice(0, limit === undefined ? LIMIT : limit)
        .map(entry => entry.window)
}

// The row's second line: what Enter does, the app and where the window is -
// or that it is minimized, which the switcher's label says for a window
// parked on its own special workspace.
function subtitle(window, appName) {
    const name = appName(window.appId)
    const place = window.workspace === "Minimized" ? " · minimized"
        : window.workspace.length ? " · Workspace " + window.workspace : ""
    return "Switch to window" + (name.length ? " · " + name : "") + place
}
