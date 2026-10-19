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
    // Build a nested Lua table; Lua option names use underscores. A dot is a
    // level too: `general:col.active_border` is `general = { col = {
    // active_border = ... } }`, where a key `col.active_border` would not
    // even parse.
    const tree = {}
    for (const key of keys) {
        const parts = checkWord(key).split(/[:.]/).map(part => part.replace(/-/g, "_"))
        let node = tree
        for (let i = 0; i < parts.length - 1; ++i) node = node[parts[i]] = node[parts[i]] || {}
        node[parts[parts.length - 1]] = { leaf: map[key] }
    }
    const render = node => "{ " + Object.keys(node).map(name => name + " = "
        + (node[name].leaf !== undefined ? luaValue(node[name].leaf) : render(node[name]))).join(", ") + " }"
    return { legacy: legacy, legacyEmpty: legacyEmpty, lua: "hl.config(" + render(tree) + ")" }
}

// A monitor of its own, on. The Lua dialect's hl.monitor keeps what an
// earlier call for the same output said and the new one leaves out - a
// monitor switched off stayed off, and a mirror stayed a mirror, under a
// rule that names a mode and a place (Hyprland 0.56, probed nested) - so
// both are said every time. The legacy keyword replaces the whole rule.
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
            + ", scale = " + scale + ", transform = " + Number(entry.transform) + ", vrr = " + Number(entry.vrr)
            + ", disabled = false, mirror = \"\" })"
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
    // The Lua dialect animates with the leaf's spring where it has one; the
    // legacy one has no springs and uses the bezier.
    const spring = entry.spring ? checkWord(entry.spring) : ""
    return {
        legacy: "keyword animation " + leaf + "," + on + "," + speed + "," + bezier + tail,
        legacyEmpty: [],
        lua: "hl.animation({ leaf = " + luaString(leaf) + ", enabled = " + (entry.enabled ? "true" : "false")
            + ", speed = " + speed + (spring.length ? ", spring = " + luaString(spring) : ", bezier = " + luaString(bezier))
            + (style.length ? ", style = " + luaString(style) : "") + " })"
    }
}

// One spring curve. Lua only: the legacy dialect has no springs, and its
// leaves name beziers instead.
function springCurve(curve) {
    const name = checkWord(curve.name)
    const numbers = [curve.mass, curve.stiffness, curve.dampening].map(Number)
    if (numbers.some(value => !isFinite(value) || value < 0.5)) throw new Error("invalid spring")
    return {
        legacy: "",
        legacyEmpty: [],
        lua: "hl.curve(" + luaString(name) + ", { type = \"spring\", mass = " + numbers[0]
            + ", stiffness = " + numbers[1] + ", dampening = " + numbers[2] + " })"
    }
}

// Everything the animation mode changes on the compositor: whether animations
// run at all, how long each leaf takes, and whether a window dragged or
// resized with the pointer interpolates toward it.
function animationMode(entries, on, pointer, springs) {
    return combine([options({
        "animations:enabled": on,
        "misc:animate_mouse_windowdragging": pointer,
        "misc:animate_manual_resizes": pointer
    })].concat(on ? (springs || []).map(springCurve).concat(entries.map(animation)) : []))
}

function env(name, value) {
    return { legacy: "keyword env " + checkWord(name) + "," + legacyValue(value), legacyEmpty: [], lua: "hl.env(" + luaString(checkWord(name)) + ", " + luaString(value) + ")" }
}

function address(value) {
    if (!/^0x[0-9a-fA-F]+$/.test(String(value))) throw new Error("invalid window address")
    return String(value)
}

function focusMonitor(name) {
    const monitor = checkWord(name)
    return { legacy: "focusmonitor " + monitor, lua: "hl.dsp.focus({ monitor = " + luaString(monitor) + " })" }
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
// first undock, which on a docked laptop happens daily. With the rule the
// returning monitor takes its own block back.
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

// Taking a rule back when "Workspaces per monitor" is turned off. A rule
// binds a workspace to its monitor whenever the workspace is *created*, so
// with the setting off but the rules still in, Super+3 on the second screen
// created 3 on the first and the focus jumped there, until the next config
// reload. Hyprland 0.56 has no way to delete a rule, and an empty `monitor`
// is ignored when rules merge; in the Lua config `hl.workspace_rule`
// returns the rule it merged into, and a disabled rule binds nothing. The
// legacy `keyword workspace` has neither, so its rules stay until the next
// reload (`legacy` is empty; HyprlandService sends this to a Lua config only).
//
// A rule of the user's own config for the same workspace is the same rule
// (Hyprland merges them), and goes with it until the next reload. An id that
// is no workspace number sends nothing.
function releaseWorkspaceRule(id) {
    const number = Math.round(Number(id))
    const valid = isFinite(number) && number >= 1
    return {
        legacy: "",
        legacyEmpty: [],
        lua: valid ? "hl.workspace_rule({ workspace = " + luaString(String(number)) + " }):set_enabled(false)" : ""
    }
}

// The rules of `ids` taken back, and the workspaces held open (`kept`,
// { id: monitor }) held again in the same request. A held workspace's
// `persistent` and its block's monitor are one merged rule (`hyprctl -j
// workspacerules`: { workspaceString: "1", monitor, persistent }), so the
// release disabled the hold too: the empty held ones went at once, and the
// shell went on believing it held them. Each comes back as a rule of its own.
// Lua only, like the release.
function releaseRules(ids, kept) {
    const held = kept && typeof kept === "object" ? kept : {}
    const release = (Array.isArray(ids) ? ids : []).map(releaseWorkspaceRule)
    const keep = Object.keys(held).map(Number).sort((a, b) => a - b).map(id => keepWorkspaceRule(id, true, held[id]))
    const lua = release.concat(keep).map(item => item.lua).filter(text => text.length)
    return { legacy: "", legacyEmpty: [], lua: lua.join("\n") }
}

// Held open or let go (Settings > Bar & notch > Keep empty workspaces open):
// `persistent`, which Hyprland 0.56 merges into the rule it already has for
// that workspace - and never `releaseWorkspaceRule`, whose set_enabled(false)
// would take a per-monitor block's monitor along. Held open, it names the
// monitor the workspace is on: a persistent rule moves its workspace to the
// rule's monitor, and without one that is the focused monitor - which emptied
// the other, Hyprland filled it with a new workspace, and holding that one
// open too ran away (nested). Let go, an empty workspace no monitor
// shows goes at once; one on screen goes when it is left. Both dialects take
// it at runtime (probed nested 17.10., `hyprctl -j workspacerules`). An id
// that is no workspace number sends nothing; neither does holding one open
// without a monitor.
function keepWorkspaceRule(id, on, monitorName) {
    const number = Math.round(Number(id))
    const monitor = on ? String(monitorName || "") : ""
    const valid = isFinite(number) && number >= 1 && (!on || monitor.length > 0)
    if (!valid) return { legacy: "", legacyEmpty: [], lua: "" }
    const name = monitor.length ? checkWord(monitor) : ""
    return {
        legacy: "keyword workspace " + number + (name.length ? ",monitor:" + name : "") + ",persistent:" + (on ? "true" : "false"),
        legacyEmpty: [],
        lua: "hl.workspace_rule({ workspace = " + luaString(String(number))
            + (name.length ? ", monitor = " + luaString(name) : "") + ", persistent = " + (on ? "true" : "false") + " })"
    }
}

// A configuration change and then a dispatcher, in one request, so the second
// can rely on the first: a workspace held open before it is switched to, not
// a moment after (two `hyprctl` runs are not promised to arrive in order).
// Lua: one eval, the rules applied at once rather than at the next idle pass
// (`exec_scheduled_prop_refresh_immediately`); legacy: one batch, whose
// `keyword` is applied before the dispatch is read.
function withDispatch(config, command) {
    const legacy = [config.legacy, command.legacy.length ? "dispatch " + command.legacy : ""].filter(text => text.length)
    const lua = config.lua.length ? [config.lua, "hl.exec_scheduled_prop_refresh_immediately()"] : []
    return {
        legacy: legacy.join(" ; "),
        legacyEmpty: config.legacyEmpty || [],
        lua: lua.concat(["hl.dispatch(" + command.lua + ")"]).join("\n")
    }
}

// Dispatchers one after the other, in one request: a `hyprctl` per step
// (started in a loop by `sh`) cost about 10 ms of CPU and 10 ms of waiting
// each, and a login at the desk sends eight. Legacy: one `--batch`, which
// Hyprland runs in the order given (the builders never put a `;` in a
// dispatcher); a step that fails no longer stops the ones after it, so the
// focus still comes back last. Lua: one eval of `hl.dispatch(...)` lines,
// the form `withDispatch` sends its dispatcher in.
function dispatchBatch(list) {
    const commands = (Array.isArray(list) ? list : []).filter(command => command && command.legacy !== undefined)
    for (const command of commands)
        if (/[;\n]/.test(String(command.legacy))) throw new Error("invalid dispatcher")
    return {
        legacy: commands.map(command => "dispatch " + command.legacy).join(" ; "),
        lua: commands.map(command => "hl.dispatch(" + command.lua + ")").join("\n")
    }
}

// A workspace onto a monitor: what a rule would have done had the workspace
// been created after it. `hl.dsp.workspace.move` is the dispatcher's Lua name
// (found by listing `hl.dsp.workspace` in the running compositor - the wiki
// names none of them).
function moveWorkspaceToMonitor(id, monitorName) {
    const number = Math.round(Number(id))
    const name = checkWord(monitorName)
    return {
        legacy: "moveworkspacetomonitor " + number + " " + name,
        lua: "hl.dsp.workspace.move({ workspace = " + number + ", monitor = " + luaString(name) + " })"
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

// The active window to a workspace, the view going with it: what
// Super+Shift+Page Down means by "take the window along" (the Super+Shift+N
// keys stay where they are; moveActiveSilent).
function moveActive(id) {
    const number = Math.round(Number(id))
    return { legacy: "movetoworkspace " + number, lua: "hl.dsp.window.move({ workspace = " + number + " })" }
}

// Floating and pinned are toggled, never set: the shell reads the state from
// `hyprctl -j clients` first and only asks for a change it wants, and a
// toggle is the one form both dialects are known to take (Super+C's own
// `togglefloating`, and Hyprland's example config `float({ action =
// "toggle" })`).
function toggleFloating(windowAddress) {
    const target = address(windowAddress)
    return { legacy: "togglefloating address:" + target,
             lua: "hl.dsp.window.float({ action = \"toggle\", window = \"address:" + target + "\" })" }
}

// Shown on every workspace of its monitor, above the tiled windows. Hyprland
// pins floating windows only (`toggleFloating` first).
function togglePin(windowAddress) {
    const target = address(windowAddress)
    return { legacy: "pin address:" + target,
             lua: "hl.dsp.window.pin({ action = \"toggle\", window = \"address:" + target + "\" })" }
}

function pixels(value) {
    const number = Math.round(Number(value))
    if (!isFinite(number)) throw new Error("invalid size")
    return number
}

// A floating window to an exact size and place, in the global layout's
// logical pixels (the space `hyprctl monitors` and Quickshell's screens use).
function resizeExact(windowAddress, width, height) {
    const target = address(windowAddress)
    const w = pixels(width), h = pixels(height)
    if (w < 1 || h < 1) throw new Error("invalid size")
    return { legacy: "resizewindowpixel exact " + w + " " + h + ",address:" + target,
             lua: "hl.dsp.window.resize({ x = " + w + ", y = " + h + ", relative = false, window = \"address:" + target + "\" })" }
}

function moveExact(windowAddress, x, y) {
    const target = address(windowAddress)
    const left = pixels(x), top = pixels(y)
    return { legacy: "movewindowpixel exact " + left + " " + top + ",address:" + target,
             lua: "hl.dsp.window.move({ x = " + left + ", y = " + top + ", relative = false, window = \"address:" + target + "\" })" }
}

// A special workspace shown over the focused monitor, or put away again (the
// drop-down terminal's).
function toggleSpecial(name) {
    const word = String(name || "")
    if (!/^[A-Za-z0-9_-]+$/.test(word)) throw new Error("invalid special workspace: " + word)
    return { legacy: "togglespecialworkspace " + word, lua: "hl.dsp.workspace.toggle_special(" + luaString(word) + ")" }
}

// Into a submap of binds, or back to the normal ones with "reset" (the
// keyboard passthrough).
function submap(name) {
    const word = String(name || "")
    if (!/^[A-Za-z0-9_-]+$/.test(word)) throw new Error("invalid submap: " + word)
    return { legacy: "submap " + word, lua: "hl.dsp.submap(" + luaString(word) + ")" }
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
// With a `shortcut` as well (`buchhwin:gestures.run.overview`), the Lua
// variant sends that global shortcut instead of running the command; the
// legacy keyword keeps the command.
function gestureEntry(entry) {
    const slot = gestureSlot(entry.fingers, entry.direction)
    if (entry.command !== undefined) {
        const text = String(entry.command).trim()
        // Commas would split the dispatcher arguments of the legacy keyword.
        if (/,/.test(text)) throw new Error("invalid gesture command")
        const shortcut = entry.shortcut ? String(entry.shortcut) : ""
        if (shortcut.length && !/^[A-Za-z0-9_-]+:[A-Za-z0-9_.-]+$/.test(shortcut)) throw new Error("invalid gesture shortcut")
        return {
            legacy: "keyword gesture " + slot.fingers + ", " + slot.direction + ", dispatcher, exec, " + legacyExec(text),
            lua: "hl.gesture({ fingers = " + slot.fingers + ", direction = " + luaString(slot.direction)
                + ", action = function() "
                + (shortcut.length ? "hl.dispatch(hl.dsp.global(" + luaString(shortcut) + "))" : "hl.exec_cmd(" + luaString(text) + ")")
                + " end })"
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
