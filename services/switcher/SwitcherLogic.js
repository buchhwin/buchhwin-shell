.pragma library
.import "../hypr/HiddenWindows.js" as Hidden
.import "../dock/MinimizeLogic.js" as Minimize
.import "../workspaces/WorkspaceLogic.js" as Workspaces

// Pure helpers for the Alt+Tab window switcher: windows from
// `hyprctl -j clients` in most-recently-used order and the wrapping selection.

// Mapped, visible windows (without the session's hidden helper windows) ordered by Hyprland's focusHistoryID (0 = focused
// last). Windows without a history id go last, in address order. Minimized
// windows (services/dock/MinimizeLogic.js) are listed - Alt+Tab is one of the
// ways back to them - after all the others, as on Windows: the window just
// minimized was used last, and a quick Alt+Tab brought it straight back.
//
// `order` (the monitors in their blocks' order, empty without blocks) and
// `monitors` ({ workspace id: the name of the monitor it is on }) let the
// badge call a workspace what its pip calls it; without them its id.
function build(clients, order, monitors) {
    return (clients || [])
        .filter(client => client && client.address && client.mapped !== false && client.hidden !== true
                && !Hidden.isHiddenClient(client))
        .map(client => {
            const workspace = client.workspace || {}
            const history = Number(client.focusHistoryID)
            return {
                address: String(client.address), title: String(client.title || ""),
                appClass: String(client.class || client.initialClass || ""),
                workspace: Number(workspace.id) || 0,
                workspaceName: workspaceLabel(workspace, (monitors || {})[Number(workspace.id)], order),
                minimized: Minimize.isParked(workspace.name),
                focusOrder: Number.isFinite(history) && history >= 0 ? history : Number.MAX_SAFE_INTEGER,
                width: Array.isArray(client.size) ? Number(client.size[0]) || 0 : 0,
                height: Array.isArray(client.size) ? Number(client.size[1]) || 0 : 0
            }
        })
        .sort((a, b) => (a.minimized ? 1 : 0) - (b.minimized ? 1 : 0) || a.focusOrder - b.focusOrder
                        || (a.address < b.address ? -1 : a.address > b.address ? 1 : 0))
}

// Badge text: the workspace as its pip calls it (WorkspaceLogic.label: a name
// somebody chose, the number in its monitor's block; `monitor` the one it is
// on, `order` as `build` has it), special workspaces by their name without
// the prefix, a minimized window's "Minimized".
function workspaceLabel(workspace, monitor, order) {
    const name = String(workspace && workspace.name !== undefined ? workspace.name : workspace && workspace.id !== undefined ? workspace.id : "")
    if (Minimize.isParked(name)) return "Minimized"
    if (name.startsWith("special:")) return name.slice(8)
    const id = workspace && workspace.id !== undefined ? Number(workspace.id) : Number(name)
    return Workspaces.label(id, name, monitor, order)
}

function wrap(index, count) {
    return count > 0 ? ((index % count) + count) % count : -1
}

// Index selected by the first key press. Forward skips the focused window so a
// single Alt+Tab returns to the previously used one; backward starts at the
// least recently used window.
function openIndex(windows, activeAddress, direction) {
    const count = windows.length
    if (count === 0) return -1
    if (count === 1) return 0
    if (direction < 0) return count - 1
    return windows[0].address === String(activeAddress || "") ? 1 : 0
}

// Selection after the opening press plus `extra` further steps (next = +1,
// previous = -1), wrapping around at both ends.
function selection(windows, activeAddress, direction, extra) {
    const first = openIndex(windows, activeAddress, direction)
    return first < 0 ? -1 : wrap(first + (extra || 0), windows.length)
}

function normalizeAddress(address) {
    const text = String(address || "").toLowerCase()
    return text.startsWith("0x") ? text.slice(2) : text
}
