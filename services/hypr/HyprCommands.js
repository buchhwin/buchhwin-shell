.pragma library

// Hyprland commands in both configuration worlds. With a legacy .conf config
// Hyprland takes `dispatch workspace 3` and `keyword a:b value`; with a Lua
// config (required from Hyprland 0.57) the same actions are Lua expressions:
// `dispatch hl.dsp.focus({ workspace = 3 })` and `eval hl.config({...})`.
// Every builder returns { legacy, lua }. Unit tested.

function luaString(value) {
    const text = String(value)
    if (/[\x00-\x1f]/.test(text)) throw new Error("control characters are not allowed")
    return "\"" + text.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
}

function luaValue(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    if (typeof value === "number") {
        if (!isFinite(value)) throw new Error("invalid number")
        return String(value)
    }
    return luaString(value)
}

function legacyValue(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    const text = String(value)
    if (/[;\n]/.test(text)) throw new Error("invalid legacy value")
    return text
}

function checkWord(text) {
    if (!/^[A-Za-z0-9_:.@x,-]+$/.test(String(text))) throw new Error("invalid identifier: " + text)
    return String(text)
}

// { "decoration:blur:size": 6, "input:touchpad:tap-to-click": true }
// Empty values cannot go through `hyprctl --batch` (a literal "" is kept as
// two quote characters, which resets kb_variant and falls back to the US
// layout); they are listed in `legacyEmpty` and set with separate calls.
function options(map) {
    const keys = Object.keys(map)
    const legacy = keys.filter(key => map[key] !== "").map(key => "keyword " + checkWord(key) + " " + legacyValue(map[key])).join(" ; ")
    const legacyEmpty = keys.filter(key => map[key] === "").map(checkWord)
    // Build a nested Lua table; Lua option names use underscores.
    const tree = {}
    for (const key of keys) {
        const parts = checkWord(key).split(":").map(part => part.replace(/-/g, "_"))
        let node = tree
        for (let i = 0; i < parts.length - 1; ++i) node = node[parts[i]] = node[parts[i]] || {}
        node[parts[parts.length - 1]] = { leaf: map[key] }
    }
    const render = node => "{ " + Object.keys(node).map(name => name + " = "
        + (node[name].leaf !== undefined ? luaValue(node[name].leaf) : render(node[name]))).join(", ") + " }"
    return { legacy: legacy, legacyEmpty: legacyEmpty, lua: "hl.config(" + render(tree) + ")" }
}

function monitor(entry) {
    const name = checkWord(entry.name)
    if (entry.disabled) return { legacy: "keyword monitor " + name + ",disable", legacyEmpty: [], lua: "hl.monitor({ output = " + luaString(name) + ", disabled = true })" }
    const mode = Math.round(entry.width) + "x" + Math.round(entry.height) + "@" + Number(entry.refresh).toFixed(2)
    const position = Math.round(entry.x) + "x" + Math.round(entry.y)
    const scale = Math.round(Number(entry.scale) * 100) / 100
    return {
        legacyEmpty: [],
        legacy: "keyword monitor " + name + "," + mode + "," + position + "," + scale + ",transform," + Number(entry.transform) + ",vrr," + Number(entry.vrr),
        lua: "hl.monitor({ output = " + luaString(name) + ", mode = " + luaString(mode) + ", position = " + luaString(position)
            + ", scale = " + scale + ", transform = " + Number(entry.transform) + ", vrr = " + Number(entry.vrr) + " })"
    }
}

// One animation leaf. The style may carry a space ("popin 96%"), so the line
// is built by hand rather than through `options()`, which takes single words.
function animation(entry) {
    const leaf = checkWord(entry.leaf)
    const speed = Number(entry.speed)
    if (!isFinite(speed) || speed <= 0) throw new Error("invalid animation speed")
    const bezier = checkWord(entry.bezier)
    const style = String(entry.style || "")
    if (/[;\n"]/.test(style)) throw new Error("invalid animation style")
    const on = entry.enabled ? "1" : "0"
    const tail = style.length ? "," + style : ""
    return {
        legacy: "keyword animation " + leaf + "," + on + "," + speed + "," + bezier + tail,
        legacyEmpty: [],
        lua: "hl.animation({ leaf = " + luaString(leaf) + ", enabled = " + (entry.enabled ? "true" : "false")
            + ", speed = " + speed + ", bezier = " + luaString(bezier)
            + (style.length ? ", style = " + luaString(style) : "") + " })"
    }
}

// Everything the animation mode changes on the compositor: whether animations
// run at all, how long each leaf takes, and whether a window dragged or
// resized with the pointer interpolates toward it.
function animationMode(entries, on, pointer) {
    return combine([options({
        "animations:enabled": on,
        "misc:animate_mouse_windowdragging": pointer,
        "misc:animate_manual_resizes": pointer
    })].concat(on ? entries.map(animation) : []))
}

function env(name, value) {
    return { legacy: "keyword env " + checkWord(name) + "," + legacyValue(value), legacyEmpty: [], lua: "hl.env(" + luaString(checkWord(name)) + ", " + luaString(value) + ")" }
}

function address(value) {
    if (!/^0x[0-9a-fA-F]+$/.test(String(value))) throw new Error("invalid window address")
    return String(value)
}

function workspace(id) {
    const number = Math.round(Number(id))
    return { legacy: "workspace " + number, lua: "hl.dsp.focus({ workspace = " + number + " })" }
}

function focusWindow(windowAddress) {
    const target = address(windowAddress)
    return { legacy: "focuswindow address:" + target, lua: "hl.dsp.focus({ window = \"address:" + target + "\" })" }
}

// Move the *active* window, which is what a key press means: no address at
// all, exactly as the checked-in `Super+Shift+N` binds do it.
function moveActiveSilent(id) {
    const number = Math.round(Number(id))
    return {
        legacy: "movetoworkspacesilent " + number,
        lua: "hl.dsp.window.move({ workspace = " + number + ", follow = false })"
    }
}

// A workspace rule saying which monitor an id belongs to.
//
// This is what makes docking survivable. Unplug a screen and Hyprland moves
// its workspaces onto a survivor; plug it back in and, without a rule, they
// stay where they were dumped - so the blocks stop meaning anything after the
// first undock, which on this machine is daily. With the rule the returning
// monitor takes its own block back.
//
// Deliberately **not** `persistent`: that would call every id in every block
// into existence, thirty workspaces for three monitors, whether or not
// anything is in them. The rule only says where a workspace belongs *if* it
// exists.
function workspaceRule(id, monitorName) {
    const number = Math.round(Number(id))
    const name = checkWord(monitorName)
    return {
        legacy: "keyword workspace " + number + ",monitor:" + name,
        legacyEmpty: [],
        lua: "hl.workspace_rule({ workspace = " + luaString(String(number))
            + ", monitor = " + luaString(name) + " })"
    }
}

function moveWindowSilent(id, windowAddress) {
    const target = address(windowAddress)
    const number = Math.round(Number(id))
    return {
        legacy: "movetoworkspacesilent " + number + ",address:" + target,
        lua: "hl.dsp.window.move({ workspace = " + number + ", window = \"address:" + target + "\", follow = false })"
    }
}

function closeWindow(windowAddress) {
    const target = address(windowAddress)
    return { legacy: "closewindow address:" + target, lua: "hl.dsp.window.close({ window = \"address:" + target + "\" })" }
}

// All monitors, or only `monitorName` (Lua takes `monitor`; `output` would
// address every monitor).
function dpms(on, monitorName) {
    const action = on ? "on" : "off"
    if (!monitorName) return { legacy: "dpms " + action, lua: "hl.dsp.dpms({ action = \"" + action + "\" })" }
    const name = checkWord(monitorName)
    return { legacy: "dpms " + action + " " + name, lua: "hl.dsp.dpms({ action = \"" + action + "\", monitor = " + luaString(name) + " })" }
}

function exit() {
    return { legacy: "exit", lua: "hl.dsp.exit()" }
}

// Key bindings made at runtime (Settings > Shortcuts). Modifiers are
// Hyprland names, the key a keysym name ("T", "F5", "comma", "XF86Mail").
// Legacy values are hyprlang: `#` starts a comment (`##` is a literal one)
// and `$NAME` expands variables such as `$terminal`, so commands keep `${NAME}`
// (the shell reads it the same way). `;` would split a --batch and is refused.
const bindModifiers = ["SUPER", "CTRL", "ALT", "SHIFT"]

function bindCombo(mods, key) {
    const list = (mods || []).map(mod => String(mod).toUpperCase())
    for (const mod of list) if (bindModifiers.indexOf(mod) < 0) throw new Error("invalid modifier: " + mod)
    if (!/^[A-Za-z0-9_]+$/.test(String(key))) throw new Error("invalid key: " + key)
    return { mods: bindModifiers.filter(mod => list.indexOf(mod) >= 0), key: String(key) }
}

function legacyExec(command) {
    const text = String(command).trim()
    if (!text.length || /[;\x00-\x1f]/.test(text)) throw new Error("invalid command")
    return text.replace(/#/g, "##").replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g, "${$1}")
}

function bindExec(mods, key, command, description) {
    const combo = bindCombo(mods, key)
    const text = String(command).trim()
    const label = String(description || "")
    if (/[,;#$\x00-\x1f]/.test(label)) throw new Error("invalid description")
    const legacyCombo = combo.mods.join(" ") + "," + combo.key
    const luaCombo = combo.mods.concat([combo.key]).join(" + ")
    return {
        legacy: label.length ? "keyword bindd " + legacyCombo + "," + label + ",exec," + legacyExec(text)
                             : "keyword bind " + legacyCombo + ",exec," + legacyExec(text),
        legacyEmpty: [],
        lua: "hl.bind(" + luaString(luaCombo) + ", hl.dsp.exec_cmd(" + luaString(text) + ")"
            + (label.length ? ", { description = " + luaString(label) + " })" : ")")
    }
}

function unbind(mods, key) {
    const combo = bindCombo(mods, key)
    return {
        legacy: "keyword unbind " + combo.mods.join(" ") + "," + combo.key,
        legacyEmpty: [],
        lua: "hl.unbind(" + luaString(combo.mods.concat([combo.key]).join(" + ")) + ")"
    }
}

// Touchpad gestures (Hyprland 0.56+: `gesture = 3, horizontal, workspace`,
// Lua `hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })`).
// A slot is fingers + direction; `action: "unset"` removes whatever it holds.
// Adding to a taken slot fails ("overshadowed"), so `gestures` removes the old
// ones first. Removing an empty slot fails too: a legacy keyword only prints
// that, but a Lua `hl.gesture` error stays in `hyprctl configerrors`. The Lua
// variant therefore remembers its slots in the global `buchhwin_gestures`,
// which a config reload resets together with the gestures themselves.
const gestureDirections = ["swipe", "horizontal", "vertical", "left", "right", "up", "down", "pinch", "pinchin", "pinchout"]
// Hyprland's own gesture actions, which follow the fingers.
const gestureActions = ["workspace", "fullscreen", "float", "close", "move", "resize"]

function gestureSlot(fingers, direction) {
    const count = Number(fingers)
    if (!Number.isInteger(count) || count < 3 || count > 5) throw new Error("invalid finger count: " + fingers)
    if (gestureDirections.indexOf(direction) < 0) throw new Error("invalid gesture direction: " + direction)
    return { fingers: count, direction: direction }
}

// { fingers, direction, action } for a Hyprland action, or
// { fingers, direction, command } for a shell command run when the swipe ends.
function gestureEntry(entry) {
    const slot = gestureSlot(entry.fingers, entry.direction)
    if (entry.command !== undefined) {
        const text = String(entry.command).trim()
        // Commas would split the dispatcher arguments of the legacy keyword.
        if (/,/.test(text)) throw new Error("invalid gesture command")
        return {
            legacy: "keyword gesture " + slot.fingers + ", " + slot.direction + ", dispatcher, exec, " + legacyExec(text),
            lua: "hl.gesture({ fingers = " + slot.fingers + ", direction = " + luaString(slot.direction)
                + ", action = function() hl.exec_cmd(" + luaString(text) + ") end })"
        }
    }
    if (gestureActions.indexOf(entry.action) < 0) throw new Error("invalid gesture action: " + entry.action)
    return {
        legacy: "keyword gesture " + slot.fingers + ", " + slot.direction + ", " + entry.action,
        lua: "hl.gesture({ fingers = " + slot.fingers + ", direction = " + luaString(slot.direction) + ", action = " + luaString(entry.action) + " })"
    }
}

// Replace the managed gestures: `list` holds the wanted entries, `slots` every
// slot the caller manages (legacy removes them all; errors for empty ones are
// harmless there).
function gestures(list, slots) {
    const entries = (list || []).map(entry => Object.assign(gestureSlot(entry.fingers, entry.direction), { built: gestureEntry(entry) }))
    const managed = (slots || []).map(slot => gestureSlot(slot.fingers, slot.direction))
    const legacy = managed.map(slot => "keyword gesture " + slot.fingers + ", " + slot.direction + ", unset")
        .concat(entries.map(entry => entry.built.legacy))
    const lua = [
        "for _, slot in ipairs(buchhwin_gestures or {}) do hl.gesture({ fingers = slot[1], direction = slot[2], action = \"unset\" }) end",
        "buchhwin_gestures = {}"
    ].concat(entries.map(entry => entry.built.lua + "\ntable.insert(buchhwin_gestures, { " + entry.fingers + ", " + luaString(entry.direction) + " })"))
    return { legacy: legacy.join(" ; "), legacyEmpty: [], lua: lua.join("\n") }
}

// Join several { legacy, lua } config commands (keyword/eval kinds).
function combine(list) {
    return {
        legacy: list.map(item => item.legacy).filter(text => text.length).join(" ; "),
        legacyEmpty: list.reduce((keys, item) => keys.concat(item.legacyEmpty || []), []),
        lua: list.map(item => item.lua).join("\n")
    }
}
