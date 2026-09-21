.pragma library

// Windows the session keeps running but never shows. Hyprland rules in
// hypr/windowrules.conf and hypr/hyprland.lua move them to the special
// workspace below with opacity 0; the switcher, overview, workspace indicator
// and active window widget skip them. Keep this list and both rule sets in sync.

// xwaylandvideobridge (KDE XDG autostart) bridges Wayland screen sharing to
// X11 apps through an otherwise black, empty window.
var classes = ["xwaylandvideobridge"]
var workspace = "special:buchhwin-hidden"

function isHiddenClass(name) {
    const text = String(name || "").toLowerCase()
    return text.length > 0 && classes.indexOf(text) >= 0
}

// A client from `hyprctl -j clients`.
function isHiddenClient(client) {
    if (!client) return false
    const onHiddenWorkspace = client.workspace && String(client.workspace.name || "") === workspace
    return onHiddenWorkspace || isHiddenClass(client.class) || isHiddenClass(client.initialClass)
}

// Windows that count for a workspace, from [{ appId, ipcClass }] (Quickshell
// toplevels: Wayland app id and the class of the last IPC object).
function visibleCount(windows) {
    return (Array.isArray(windows) ? windows : [])
        .filter(window => !window || !(isHiddenClass(window.appId) || isHiddenClass(window.ipcClass))).length
}
