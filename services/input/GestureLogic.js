.pragma library

// Touchpad gestures from Settings > Input (`gestures.*`), applied as runtime
// Hyprland gestures through HyprCompat (HyprCommands.gestures). Shell panels
// run `quickshell ipc call gestures run NAME` when the swipe ends; Hyprland's
// own actions (workspace, fullscreen, float, close) follow the fingers.
// Unit tested.

// Every slot the shell manages, in settings order.
var slots = [
    { key: "threeHorizontal", fingers: 3, direction: "horizontal", horizontal: true, label: "3 fingers left/right" },
    { key: "threeUp", fingers: 3, direction: "up", label: "3 fingers up" },
    { key: "threeDown", fingers: 3, direction: "down", label: "3 fingers down" },
    { key: "fourHorizontal", fingers: 4, direction: "horizontal", horizontal: true, label: "4 fingers left/right" },
    { key: "fourUp", fingers: 4, direction: "up", label: "4 fingers up" },
    { key: "fourDown", fingers: 4, direction: "down", label: "4 fingers down" },
    { key: "pinchIn", fingers: 4, direction: "pinchin", label: "4 fingers pinch in" },
    { key: "pinchOut", fingers: 4, direction: "pinchout", label: "4 fingers pinch out" }
]

// Actions for up, down and pinch slots. `panel` toggles a shell panel like its
// hotkey, `hypr` is a Hyprland gesture action.
var actions = [
    { value: "none", label: "Nothing" },
    { value: "overview", label: "Overview", panel: "overview" },
    { value: "launcher", label: "Launcher", panel: "launcher" },
    { value: "dashboard", label: "Dashboard", panel: "dashboard" },
    { value: "controlCenter", label: "Control center", panel: "controlCenter" },
    { value: "notifications", label: "Notifications", panel: "notifications" },
    { value: "clipboard", label: "Clipboard history", panel: "clipboard" },
    { value: "closePanel", label: "Close the open panel", closePanel: true },
    { value: "fullscreen", label: "Fullscreen window", hypr: "fullscreen" },
    { value: "float", label: "Float window", hypr: "float" },
    { value: "close", label: "Close window", hypr: "close" }
]

var horizontalActions = [
    { value: "workspace", label: "Switch workspace", hypr: "workspace" },
    { value: "none", label: "Nothing" }
]

function optionsFor(slot) {
    return slot.horizontal ? horizontalActions : actions
}

function actionFor(slot, value) {
    return optionsFor(slot).find(item => item.value === value) || null
}

// The shell action behind `gestures run NAME`: { panel } or { closePanel }, or
// null for anything else.
function shellAction(name) {
    const action = actions.find(item => item.value === name)
    return action && (action.panel || action.closePanel) ? action : null
}

// Command for a shell action, or "" when the shell path cannot be used
// unquoted in a Hyprland exec.
function shellCommand(shellPath, name) {
    const path = String(shellPath || "").replace(/\/+$/, "")
    if (!/^\/[A-Za-z0-9_.\/+@-]+$/.test(path) || !shellAction(name)) return ""
    return "quickshell --path " + path + " ipc call gestures run " + name
}

// { enabled, gestures: [{ fingers, direction, action | command }], slots,
//   options } for a settings getter (path -> value).
function plan(get, shellPath) {
    const enabled = get("gestures.enabled") !== false
    const list = []
    for (const slot of slots) {
        const action = enabled ? actionFor(slot, get("gestures." + slot.key)) : null
        if (!action || action.value === "none") continue
        const entry = { fingers: slot.fingers, direction: slot.direction }
        if (action.hypr) entry.action = action.hypr
        else {
            const command = shellCommand(shellPath, action.value)
            if (!command.length) continue
            entry.command = command
        }
        list.push(entry)
    }
    return {
        enabled: enabled,
        gestures: list,
        slots: slots.map(slot => ({ fingers: slot.fingers, direction: slot.direction })),
        options: {
            // Hyprland's "invert" is the natural direction: the workspaces
            // follow the fingers.
            "gestures:workspace_swipe_invert": get("gestures.naturalSwipe") !== false,
            "gestures:workspace_swipe_create_new": get("gestures.createNew") === true,
            "gestures:workspace_swipe_direction_lock": true
        }
    }
}

// Active gestures for lists (Settings > Shortcuts): [{ label, action }].
function rows(get) {
    if (get("gestures.enabled") === false) return []
    return slots.map(slot => ({ slot: slot, action: actionFor(slot, get("gestures." + slot.key)) }))
        .filter(item => item.action && item.action.value !== "none")
        .map(item => ({ label: item.slot.label, action: item.action.label }))
}

// Whether `hyprctl -j devices` lists a touchpad among the pointer devices.
function hasTouchpad(text) {
    try {
        const data = JSON.parse(text)
        const mice = data && Array.isArray(data.mice) ? data.mice : []
        return mice.some(item => item && /touchpad|trackpad|glidepoint/i.test(String(item.name)))
    } catch (error) {
        return false
    }
}
