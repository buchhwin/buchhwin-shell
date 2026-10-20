.pragma library
.import "../hypr/HiddenWindows.js" as Hidden
.import "../hypr/HyprCommands.js" as Commands
.import "../workspaces/WorkspaceLogic.js" as Workspaces

// Minimized windows (services/MinimizeService.qml), as a Windows or KDE
// taskbar has them: Hyprland has no minimized state, so a minimized window
// is moved, without the focus, to a special workspace of its own - one per
// workspace it came from, `special:buchhwin-minimized-3` for a window
// minimized on 3. The name is the whole record: nothing is kept anywhere
// else, so the shell knows after a restart where each one belongs, and the
// dock, the overview and Alt+Tab, which all read where a window is, see it
// as minimized without being told. A special workspace nobody opens is never
// drawn, and that is the risk: a window there that nothing lists is lost to
// the user. Everything that lists windows therefore lists these too, and
// every start of the shell brings them back.
//
// The session's hidden helpers have their own special workspace
// (HiddenWindows.js, `special:buchhwin-hidden`): never one of these, never
// minimized, never brought back.

var PREFIX = "special:buchhwin-minimized"

function lower(text) { return String(text || "").toLowerCase() }

// ---- the workspaces -------------------------------------------------------------
// The special workspace for a window minimized on `origin`; one with no number
// to go back to (a named workspace's) has the bare name and comes back to the
// workspace in front.
function parkName(origin) {
    const number = Math.round(Number(origin))
    return isFinite(number) && number > 0 ? PREFIX + "-" + number : PREFIX
}

// Whether a workspace name is one of these.
function isParked(name) {
    const text = String(name || "")
    return text === PREFIX || text.indexOf(PREFIX + "-") === 0
}

// The workspace a minimized window came from, 0 for none known.
function originOf(name) {
    if (!isParked(name)) return 0
    const rest = String(name).slice(PREFIX.length + 1)
    return /^[1-9]\d*$/.test(rest) ? Number(rest) : 0
}

// Where a window is, for the dock's menu and the overview: "Minimized", and
// the workspace it goes back to when that is known - called what its pip
// calls it (WorkspaceLogic.title; `order` the monitors in their blocks'
// order, empty without blocks, `monitor` the one that workspace is on, ""
// when it is not there now).
function parkedLabel(name, order, monitor) {
    const origin = originOf(name)
    return origin > 0 ? "Minimized · " + Workspaces.title(origin, "", monitor, order) : "Minimized"
}

// The same under the overview's "Minimized" row, which says the first half
// already: the workspace alone, "" when it is not known.
function originLabel(name, order, monitor) {
    const origin = originOf(name)
    return origin > 0 ? Workspaces.title(origin, "", monitor, order) : ""
}

// ---- the windows ----------------------------------------------------------------
// A window as this file reads it: { address ("0x…"), appClass, workspace (id),
// workspaceName, pinned }. From a client of `hyprctl -j clients`:
function fromClient(client) {
    const c = client || {}
    const workspace = c.workspace || {}
    return { address: addressOf(c.address), appClass: String(c.class || c.initialClass || ""),
             workspace: Number(workspace.id) || 0, workspaceName: String(workspace.name || ""),
             pinned: c.pinned === true, title: String(c.title || ""),
             focusOrder: Number(c.focusHistoryID) >= 0 ? Number(c.focusHistoryID) : Number.MAX_SAFE_INTEGER }
}

// "0x…" for an address with or without its prefix, "" for none.
function addressOf(value) {
    const text = lower(value)
    const bare = text.indexOf("0x") === 0 ? text.slice(2) : text
    return /^[0-9a-f]+$/.test(bare) ? "0x" + bare : ""
}

// Whether a window can be minimized: a real window on a workspace a user sees.
// Not one of the shell's hidden helpers, not one minimized already, not one
// pinned to every workspace - Hyprland keeps a pinned window where it is -,
// and none on a special workspace: a scratchpad or the drop-down terminal is
// put away by its own key, and minimized it would come back to an ordinary
// workspace, no longer where that key looks for it.
function canMinimize(window) {
    const w = window || {}
    if (!addressOf(w.address).length || Hidden.isHiddenClass(w.appClass)) return false
    // Every special one: the helpers', the minimized windows' own, a scratchpad's.
    const name = String(w.workspaceName || "")
    if (name === "special" || name.indexOf("special:") === 0) return false
    return w.pinned !== true
}

// The workspace a window is minimized from: its number, 0 for one that has
// none to go back to (a special or a named workspace).
function originFor(window) {
    const id = Math.round(Number(window && window.workspace))
    return isFinite(id) && id > 0 ? id : 0
}

// Where a minimized window goes back to: its own workspace, else the one in
// front (`focused`), else the first.
function restoreTarget(window, focused) {
    const origin = originOf(window && window.workspaceName)
    if (origin > 0) return origin
    const front = Math.round(Number(focused))
    return isFinite(front) && front > 0 ? front : 1
}

// The minimized ones among `windows`, minimized last first: `order` is
// { address: when } for the ones the shell minimized itself (the rest, from
// before a restart or asked for by the app, go after them in the order
// given).
function parked(windows, order) {
    const stamps = order || {}
    const list = Array.prototype.slice.call(windows || []).filter(w => w && isParked(w.workspaceName) && addressOf(w.address).length)
    return list.map((w, index) => ({ w: w, index: index }))
        .sort((a, b) => (Number(stamps[b.w.address]) || 0) - (Number(stamps[a.w.address]) || 0) || a.index - b.index)
        .map(entry => entry.w)
}

// The one Super+Shift+H brings back: the one minimized last. "" for none.
function lastParked(windows, order) {
    const list = parked(windows, order)
    return list.length ? list[0].address : ""
}

// The window in front, while it is on the focused workspace (or a special
// one shown over it, or pinned to every workspace): Quickshell keeps the
// last window as Hyprland's active one when an empty workspace takes the
// focus (testing.md pitfall 118), and it keeps one just minimized the same
// way - neither is in front. `focused`: the focused workspace's id.
function inFront(window, focused) {
    const w = window || {}
    if (!addressOf(w.address).length || isParked(w.workspaceName)) return false
    const workspace = Number(w.workspace)
    const front = Number(focused)
    if (!(front > 0) || !(workspace > 0) || w.pinned === true) return true
    return workspace === front
}

// ---- what Hyprland is told ----------------------------------------------------------
// The two dialects as HyprCommands.js writes them. The workspace is a name
// here, which HyprCommands' builders, made for numbers, do not take.
function minimizeCommand(windowAddress, origin) {
    const target = Commands.address(windowAddress)
    const name = parkName(origin)
    return {
        legacy: "movetoworkspacesilent " + name + ",address:" + target,
        lua: "hl.dsp.window.move({ workspace = " + Commands.luaString(name) + ", window = \"address:" + target + "\", follow = false })"
    }
}

// Back to `workspace`, and to the front when `focus` - one request, so the
// focus never comes before the move (it would open the special workspace).
function restorePlan(windowAddress, workspace, focus) {
    const plan = [Commands.moveWindowSilent(workspace, windowAddress)]
    if (focus) plan.push(Commands.focusWindow(windowAddress))
    return plan
}

// Every minimized window back where it came from, none to the front: what a
// start of the shell does, and turning the feature off for good. `focused`:
// the workspace for the ones with no number of their own.
function restoreAllPlan(windows, focused) {
    const plan = []
    for (const window of parked(windows, {}))
        plan.push(Commands.moveWindowSilent(restoreTarget(window, focused), window.address))
    return plan
}

// ---- an app's own minimize button ----------------------------------------------------
// The event `minimized>>ADDRESS,1` (`,0` back), which Hyprland documents for a
// window's request to change its minimized state; it never minimizes
// anything itself. Hyprland 0.56.2 posted none for xdg-shell's set_minimized
// (GTK3, GTK4) nor an X11 iconify (XWayland) in the nested checks
// (testing.md pitfall 149), so this acts only for what it does report.
// { address, minimized }, or null for anything else.
function parseRequest(data) {
    const parts = String(data || "").split(",")
    if (parts.length !== 2) return null
    const address = addressOf(parts[0].trim())
    const flag = parts[1].trim()
    if (!address.length || (flag !== "0" && flag !== "1")) return null
    return { address: address, minimized: flag === "1" }
}

// What the shell does with it: "minimize", "restore" or "none". `state`: {
// enabled (Settings: honour the apps' own minimize buttons), window (the
// window that asked, as above; null when it is not known), activeAddress and
// activeClass (the window and the app with the focus, from Hyprland's own
// events), panelOpen (a panel of the shell's - Alt+Tab, the overview, the
// launcher - is up) }. A minimize counts only from the app the user is in: a
// game set to minimize itself when it loses the focus (SDL does that, and a
// Windows game under Wine) asks just after Alt+Tab took the focus away, and
// it would vanish each time. The same app is enough - a toolbar of its own
// may have the focus. Nor while a panel is up: it holds the keyboard while
// the window stays the active one, so such a game asks then, and a click
// meant for a minimize button lands on the panel's scrim. Asked to come
// back, a minimized window always may.
function requestAction(request, state) {
    const s = state || {}
    const window = s.window || null
    if (!request || !window || addressOf(window.address) !== request.address) return "none"
    if (!request.minimized) return isParked(window.workspaceName) ? "restore" : "none"
    if (s.enabled !== true || s.panelOpen === true || !canMinimize(window)) return "none"
    const focused = addressOf(s.activeAddress) === request.address
    const sameApp = lower(s.activeClass).length > 0 && lower(s.activeClass) === lower(window.appClass)
    return focused || sameApp ? "minimize" : "none"
}

// A special workspace opened on a monitor (`activespecial>>NAME,MONITOR`): the
// name when it is one of these, else "". Something focused a minimized window
// (an app raising itself, a notification's action): it comes back to its
// workspace rather than standing over it in a special one nothing can close.
function openedParked(data) {
    const parts = String(data || "").split(",")
    if (parts.length < 2) return ""
    parts.pop()
    const name = parts.join(",")
    return isParked(name) ? name : ""
}
