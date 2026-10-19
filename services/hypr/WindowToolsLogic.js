.pragma library
.import "../display/DisplayLogic.js" as Display
.import "../dock/MinimizeLogic.js" as Minimize

// Window actions the compositor has the pieces for and the shell puts
// together: keep a window on top, the drop-down terminal, and a Citrix
// session spread over the desk's screens. Pure, unit tested in
// WindowToolsTest.qml; HyprlandService reads `hyprctl -j clients` and sends
// what these return through HyprCompat.

// ---- Keep on top ----------------------------------------------------------
//
// Hyprland's `pin`: shown on every workspace of its monitor and above the
// tiled windows - KDE's "Keep above others", PowerToys' Always On Top. Only a
// floating window can be pinned, so a tiled one is floated first, and taken
// back into the layout when it is let go (`floated`: the shell floated it for
// this). A window that floated on its own stays floating.
//
// `client` is one of `hyprctl -j clients` ({ address, floating, pinned }).
// Returns { steps: ["float" | "pin"], floated } - each step a toggle of that
// state, which is the one form both dialects are known to take - or null for
// no window.
function keepOnTop(client, floated) {
    if (!client || !/^0x[0-9a-fA-F]+$/.test(String(client.address || ""))) return null
    if (client.pinned === true)
        return { steps: floated === true && client.floating === true ? ["pin", "float"] : ["pin"], floated: false }
    return { steps: client.floating === true ? ["pin"] : ["float", "pin"], floated: client.floating !== true }
}

// The window an action without an address means: the one with the keyboard
// (`focusHistoryID` 0), of the clients a person can see. Not one just
// minimized: Hyprland can leave focusHistoryID 0 on the last window of a
// workspace after it went to its minimized workspace (testing.md pitfall
// 118's shape), and floated and pinned from there it would leave that
// workspace without being restored.
function activeClient(clients) {
    const list = (Array.isArray(clients) ? clients : [])
        .filter(client => client && client.mapped !== false && client.hidden !== true
                && !(client.workspace && Minimize.isParked(client.workspace.name)))
    return list.find(client => Number(client.focusHistoryID) === 0) || null
}

function clientAt(clients, address) {
    const wanted = String(address || "").toLowerCase()
    if (!wanted.length) return activeClient(clients)
    const normal = wanted.indexOf("0x") === 0 ? wanted : "0x" + wanted
    return (Array.isArray(clients) ? clients : []).find(client => client && String(client.address || "").toLowerCase() === normal) || null
}

// ---- The drop-down terminal ----------------------------------------------
//
// One Alacritty window of its own class on a special workspace of its own,
// which Super+^ (the key left of 1, whatever the layout prints on it) shows
// over whatever is on screen and puts away again - Yakuake, Guake, a Hyprland
// scratchpad. hypr/'s `buchhwin-dropdown` rule floats it, sizes it and sends
// it there; the specialWorkspace animation slides it in from the top.
var DROPDOWN_CLASS = "buchhwin-dropdown"
var DROPDOWN_WORKSPACE = "buchhwin-dropdown"

// "toggle" while its window is there, else "launch" - the first press starts
// it, every later one shows or hides it. `appIds` are the windows' app ids.
function dropdownAction(appIds) {
    return (Array.isArray(appIds) ? appIds : []).some(id => String(id || "") === DROPDOWN_CLASS) ? "toggle" : "launch"
}

// ---- A Citrix session over the desk's screens ------------------------------
//
// Hyprland fullscreens a window on one monitor and has no way to name more
// (no _NET_WM_FULLSCREEN_MONITORS), so the session that spanned both 4K
// screens under Plasma sits on one of them here. What does work: a floating
// window the size of the screens together - the session then fills it, as it
// fills any window it is in. The screens must make one rectangle: two or more
// external ones side by side, as high as each other and at the same height
// on the desk. A laptop's own panel never counts, and a portrait screen
// beside them is not part of the row.

// [{ name, x, y, width, height }] of the screens that are on (logical, the
// space of Quickshell's screens and `hyprctl monitors`) -> { x, y, width,
// height, names } or null.
function spanTarget(screens) {
    const tolerance = 2
    const list = (Array.isArray(screens) ? screens : [])
        .filter(item => item && typeof item.name === "string" && item.name.length && !Display.isInternal(item.name)
                && Number(item.width) > 0 && Number(item.height) > 0)
        .map(item => ({ name: item.name, x: Math.round(Number(item.x) || 0), y: Math.round(Number(item.y) || 0),
                        width: Math.round(Number(item.width)), height: Math.round(Number(item.height)) }))
        .sort((a, b) => a.x - b.x || a.y - b.y)
    let best = null
    for (let start = 0; start < list.length; ++start) {
        const run = [list[start]]
        for (let index = start + 1; index < list.length; ++index) {
            const last = run[run.length - 1]
            const item = list[index]
            if (Math.abs(last.x + last.width - item.x) > tolerance) continue
            if (Math.abs(last.y - item.y) > tolerance || Math.abs(last.height - item.height) > tolerance) continue
            run.push(item)
        }
        if (run.length >= 2 && (!best || run.length > best.length)) best = run
    }
    if (!best) return null
    const first = best[0], last = best[best.length - 1]
    return { x: first.x, y: first.y, width: last.x + last.width - first.x, height: first.height,
             names: best.map(item => item.name) }
}

// The Citrix session window of `hyprctl -j clients`: class Wfica and not one
// of its dialogs (titled exactly "wfica"), the one used last when there are
// several. null for none.
function citrixWindow(clients) {
    const sessions = (Array.isArray(clients) ? clients : []).filter(client => client
        && /^wfica$/i.test(String(client.class || client.initialClass || ""))
        && String(client.title || "").length > 0 && String(client.title).toLowerCase() !== "wfica"
        && client.mapped !== false && client.hidden !== true
        && /^0x[0-9a-fA-F]+$/.test(String(client.address || "")))
    if (!sessions.length) return null
    const order = client => {
        const value = Number(client.focusHistoryID)
        return isFinite(value) && value >= 0 ? value : Number.MAX_SAFE_INTEGER
    }
    return sessions.slice().sort((a, b) => order(a) - order(b))[0]
}

// What spreading `client` over `target` takes, or why it cannot be done:
// { steps: [{ kind: "float" | "size" | "place", ... }], reason }. Nothing at
// all without a window, without the screens, or with the session in full
// screen - Hyprland's full screen is one monitor's, and the session must be
// taken out of it with its own toolbar first ("Window"), or the size would be
// undone at once.
function spanPlan(client, target) {
    if (!client) return { steps: [], reason: "No Citrix session window" }
    if (!target) return { steps: [], reason: "Needs two screens side by side" }
    if (Number(client.fullscreen) > 0) return { steps: [], reason: "Leave Citrix full screen first" }
    const steps = []
    if (client.floating !== true) steps.push({ kind: "float" })
    steps.push({ kind: "size", width: target.width, height: target.height })
    steps.push({ kind: "place", x: target.x, y: target.y })
    return { steps: steps, reason: "" }
}

// The words for a span that worked: "Citrix on 2 screens". The count, not
// the connectors' names: "Citrix over DP-8 and DP-10" said what Settings >
// Displays calls the screens otherwise, and ran out of the OSD's width.
function spanText(target) {
    const names = target && Array.isArray(target.names) ? target.names : []
    if (!names.length) return ""
    return names.length === 1 ? "Citrix on 1 screen" : "Citrix on " + names.length + " screens"
}
