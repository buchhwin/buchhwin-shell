.pragma library
.import "../hypr/HyprCommands.js" as Hypr

// Where apps open (Settings > Apps > Open on, the dock's "Always open here")
// and the list of work apps, as services/SessionAppsService.qml keeps them in
// ~/.config/buchhwin-shell/apps.json - and the Hyprland window rules a
// placement becomes. Pure; tests/qml/SessionAppsTest.qml.
//
// A placement names an app (its desktop entry id), a screen and, on that
// screen, one of the ten workspaces of its block, or the one it shows; and
// whether the app floats. The screen is kept by its description (make, model
// and serial: the same monitor whichever connector it is on today), its
// connector name beside it for a monitor that reports none. A screen that is
// not connected sends no rule: the app opens where you are, as it did before.
//
// The rules are sent at runtime, like the workspace blocks
// (HyprlandService.applyWorkspaceRules), and a config reload forgets them, so
// they are sent again after one. A rule's workspace is the block's own id on
// that monitor (DP-10's third is 13), and the block's rule names the monitor
// the workspace is created on - never a workspace without one (testing.md
// pitfall 117).

var VERSION = 1
// Enough for every app anybody places, and a bound on what a hand-edited file
// can make the shell send.
var MAX_RULES = 50
var MAX_WORK_APPS = 20
var RULE_PREFIX = "buchhwin-place-"

function text(value) { return value === undefined || value === null ? "" : String(value) }
function lower(value) { return text(value).toLowerCase() }

// A desktop entry id as AutostartService takes one: anything but a control
// character, within reason. Citrix names its subscribed apps with spaces and
// '$'; the id only ever finds an entry or names a rule.
function validId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 255 && !/[\u0000-\u001f\u007f]/.test(id)
}

// A connector name (DP-10, eDP-1, HDMI-A-1, BUCHTEST), or "".
function validMonitorName(name) {
    return typeof name === "string" && /^[A-Za-z0-9_.:@-]{1,64}$/.test(name)
}

function validDescription(value) {
    return typeof value === "string" && value.length <= 255 && !/[\u0000-\u001f\u007f]/.test(value)
}

// One placement as stored, or null. A workspace needs a screen: "the third
// workspace" means a block, and a block is a monitor's.
function sanitizeRule(raw, block) {
    if (!raw || typeof raw !== "object" || !validId(raw.app)) return null
    const size = Math.max(1, Math.round(Number(block) || 10))
    const screen = validDescription(raw.screen) ? raw.screen : ""
    const screenName = validMonitorName(raw.screenName) ? raw.screenName : ""
    const hasScreen = screen.length > 0 || screenName.length > 0
    const number = Math.round(Number(raw.workspace))
    const workspace = hasScreen && isFinite(number) && number >= 1 && number <= size ? number : 0
    return { app: raw.app, screen: screen, screenName: screenName, workspace: workspace, float: raw.float === true }
}

function emptyStore() {
    return { version: VERSION, placement: [], workApps: [] }
}

// apps.json, whatever was in it: unknown keys and broken entries are left
// out, one placement per app (the first), the work apps once each.
function parseStore(source, block) {
    let data = null
    try { data = JSON.parse(text(source)) } catch (error) { data = null }
    const store = emptyStore()
    if (!data || typeof data !== "object") return store
    const seen = {}
    for (const raw of Array.isArray(data.placement) ? data.placement : []) {
        const rule = sanitizeRule(raw, block)
        if (!rule || seen[rule.app]) continue
        seen[rule.app] = true
        store.placement.push(rule)
        if (store.placement.length >= MAX_RULES) break
    }
    const apps = {}
    for (const id of Array.isArray(data.workApps) ? data.workApps : []) {
        if (!validId(id) || apps[id]) continue
        apps[id] = true
        store.workApps.push(id)
        if (store.workApps.length >= MAX_WORK_APPS) break
    }
    return store
}

function serializeStore(store) {
    const value = store || emptyStore()
    return JSON.stringify({ version: VERSION, placement: value.placement || [], workApps: value.workApps || [] }, null, 2) + "\n"
}

function ruleFor(store, app) {
    return ((store && store.placement) || []).find(rule => rule.app === app) || null
}

// The app's placement replaced, or added at the end; refused (the store as it
// was) when the rule is not one or the list is full.
function withRule(store, raw, block) {
    const rule = sanitizeRule(raw, block)
    const list = (store && store.placement) || []
    if (!rule) return store
    const index = list.findIndex(item => item.app === rule.app)
    if (index < 0 && list.length >= MAX_RULES) return store
    const placement = index < 0 ? list.concat([rule]) : list.map((item, at) => at === index ? rule : item)
    return Object.assign({}, store, { placement: placement })
}

function withoutRule(store, app) {
    const list = (store && store.placement) || []
    return Object.assign({}, store, { placement: list.filter(item => item.app !== app) })
}

function withWorkApp(store, id) {
    const list = (store && store.workApps) || []
    if (!validId(id) || list.indexOf(id) >= 0 || list.length >= MAX_WORK_APPS) return store
    return Object.assign({}, store, { workApps: list.concat([id]) })
}

function withoutWorkApp(store, id) {
    const list = (store && store.workApps) || []
    return Object.assign({}, store, { workApps: list.filter(item => item !== id) })
}

// ---- screens -------------------------------------------------------------------
// The monitor a placement means among the ones that are on ([{ name,
// description }]): by description first - a monitor on another connector is
// still the same one -, else by connector name; null when it is not here.
function monitorFor(rule, monitors) {
    const list = Array.isArray(monitors) ? monitors.filter(item => item && validMonitorName(item.name)) : []
    if (!rule) return null
    const description = text(rule.screen)
    if (description.length) {
        const found = list.find(item => text(item.description) === description)
        if (found) return found
    }
    const name = text(rule.screenName)
    return name.length ? list.find(item => item.name === name) || null : null
}

// "U2723QE (DP-10)", or the description, or the connector alone.
function screenLabel(monitor) {
    if (!monitor) return ""
    const model = text(monitor.model).trim()
    const description = text(monitor.description).trim()
    const shown = model.length ? model : description
    return shown.length ? shown + " (" + monitor.name + ")" : text(monitor.name)
}

// Where a placement sends an app now: { monitor, workspace, float } with the
// block's own workspace id (or 0: the one the screen shows), or null when its
// screen is not connected or it would change nothing. `offsets`: { name:
// where that monitor's block starts }, all 0 without workspaces per monitor.
function ruleTarget(rule, monitors, offsets) {
    if (!rule) return null
    const hasScreen = text(rule.screen).length > 0 || text(rule.screenName).length > 0
    if (!hasScreen) return rule.float ? { monitor: "", workspace: 0, float: true } : null
    const monitor = monitorFor(rule, monitors)
    if (!monitor) return null
    const offset = Math.max(0, Math.round(Number((offsets || {})[monitor.name]) || 0))
    return { monitor: monitor.name, workspace: rule.workspace > 0 ? offset + rule.workspace : 0, float: rule.float === true }
}

// ---- the window a rule matches -------------------------------------------------
// A literal piece of a regular expression for RE2, Hyprland's engine:
// specials in a character class of their own ("[.]"), so the conf and the
// Lua dialect spell it the same - a backslash would have to be doubled in a
// Lua string (hypr/hyprland.lua's screen-share rule does the same). null
// for what a rule cannot carry: a comma ends a field of the conf's anonymous
// windowrule, '#' starts a hyprlang comment, ';' would split the request, and
// '\', ']' and '^' have no plain class of their own.
function literal(value) {
    const source = text(value)
    if (!source.length || /[,;#\\\]^\u0000-\u001f\u007f]/.test(source)) return null
    return source.replace(/[.$()*+?|{}[]/g, char => "[" + char + "]")
}

// The window classes a desktop entry's windows have: its id (org.kde.dolphin),
// its StartupWMClass (Code for VS Code, crx_<app> for a web app under
// XWayland) and the last part of a reverse-DNS id - the names DockLogic's
// entryMatches accepts.
function classNames(entry) {
    if (!entry) return []
    const id = text(entry.id)
    const names = [id, text(entry.startupClass)]
    if (id.indexOf(".") > 0) names.push(id.slice(id.lastIndexOf(".") + 1))
    const seen = {}
    return names.map(lower).filter(name => name.length && !seen[name] && (seen[name] = true))
}

function isCitrixEntry(entry) {
    return Array.prototype.slice.call((entry && entry.categories) || []).some(category => lower(category) === "citrix-subscribed")
}

// { class, title } of the rule's match, or null when nothing can be matched.
// A desktop subscribed in Citrix Workspace has no window class of its own -
// every session is Wfica - and is told apart by its title, which starts with
// the desktop's name as a whole word (DockLogic.citrixEntryFor).
function matchFor(entry) {
    if (!entry) return null
    if (isCitrixEntry(entry)) {
        const word = literal(text(entry.startupClass || entry.name).trim())
        return word ? { "class": "(?i)^(wfica)$", title: "(?i)^(" + word + ")([^0-9a-z_.-].*)?$" } : null
    }
    const names = classNames(entry).map(literal).filter(Boolean)
    return names.length ? { "class": "(?i)^(" + names.join("|") + ")$" } : null
}

// ---- the rules -------------------------------------------------------------------
// A short, stable name for a rule's whole content: the same placement on the
// same screen keeps its name, and anything that changes it (another
// workspace, the screen on another connector, a new block) is another rule.
function hash(source) {
    let value = 5381
    const textValue = text(source)
    for (let index = 0; index < textValue.length; ++index) value = ((value * 33) ^ textValue.charCodeAt(index)) >>> 0
    return value.toString(36)
}

function ruleName(match, target) {
    return RULE_PREFIX + hash(JSON.stringify([match["class"], match.title || "", target.monitor, target.workspace, target.float]))
}

// The rule itself in both dialects. Lua: a named `hl.window_rule`, which
// Hyprland keeps by its name, so it can be switched off again (ruleSwitch).
// Declared once per config load: a second declaration of a name takes the
// same rule and adds its effects to it again (Hyprland 0.56 appends them), so
// a restarted shell - which knows nothing of what the compositor holds - only
// switches on what the Lua global `buchhwin_places` says is there. A reload
// resets that global together with the rules, as it does `buchhwin_gestures`.
// The conf dialect has only the anonymous `windowrule` keyword, which nothing
// removes before the next config reload (ruleRelease takes one back).
function ruleCommand(name, match, target) {
    const effects = []
    const lua = ["name = " + Hypr.luaString(name)]
    const luaMatch = ["class = " + Hypr.luaString(match["class"])]
    if (match.title) luaMatch.push("title = " + Hypr.luaString(match.title))
    lua.push("match = { " + luaMatch.join(", ") + " }")
    // The screen always, when there is one: alone, the app opens on whatever
    // workspace it shows (and the focus goes with it, as with any new
    // window); with a workspace, a workspace that does not exist yet is made
    // on that screen - by the block's own rule while workspaces are per
    // monitor, and by this one without them (the window is on that screen
    // before its workspace is looked for), never on the focused one (pitfall
    // 117) - and "silent" keeps the focus where it is, like the workspace's
    // own "silent" (Hyprland 0.56 focuses a rule's monitor otherwise).
    if (text(target.monitor).length) {
        const monitor = Hypr.checkWord(target.monitor) + (target.workspace > 0 ? " silent" : "")
        effects.push("monitor " + monitor)
        lua.push("monitor = " + Hypr.luaString(monitor))
    }
    if (target.workspace > 0) {
        const workspace = Math.round(Number(target.workspace))
        effects.push("workspace " + workspace + " silent")
        lua.push("workspace = " + Hypr.luaString(workspace + " silent"))
    }
    if (target.float) {
        effects.push("float on")
        lua.push("float = true")
    }
    const fields = effects.concat(["match:class " + match["class"]])
    if (match.title) fields.push("match:title " + match.title)
    return {
        legacy: "keyword windowrule " + fields.join(", "),
        legacyEmpty: [],
        lua: "buchhwin_places = buchhwin_places or {}\n"
            + "if buchhwin_places[" + Hypr.luaString(name) + "] then " + ruleSwitch(name, true).lua
            + " else buchhwin_places[" + Hypr.luaString(name) + "] = true; hl.window_rule({ " + lua.join(", ") + " }) end"
    }
}

// A named rule on or off again (Lua only: `hl.window_rule` with a known name
// takes that rule and sets `enabled`, adding nothing - Hyprland 0.56,
// LuaBindingsConfigRules.cpp).
function ruleSwitch(name, on) {
    return { legacy: "", legacyEmpty: [], lua: "hl.window_rule({ name = " + Hypr.luaString(name) + ", enabled = " + (on ? "true" : "false") + " })" }
}

// A conf rule taken back: nothing removes an anonymous rule before the next
// reload, but Hyprland applies every rule that matches a window in order, a
// later one over an earlier one, and "unset" leaves the screen and the
// workspace to where the window would have opened (Hyprland 0.56,
// WindowRuleApplicator.cpp readStaticRules, Window.cpp setStaticProps). So a
// later rule for the same windows that unsets both puts the app where you
// are again - after a screen was unplugged too, where the old rule would make
// its workspace on the focused screen and the window open there unseen.
// Floating has no "unset" (`float off` would tile the app's own dialogs): it
// holds until the reload. null for a rule with nothing else to unset.
function ruleRelease(match, target) {
    if (!match || !target) return null
    const effects = []
    if (text(target.monitor).length) effects.push("monitor unset")
    if (target.workspace > 0) effects.push("workspace unset")
    if (!effects.length) return null
    const fields = effects.concat(["match:class " + match["class"]])
    if (match.title) fields.push("match:title " + match.title)
    return { legacy: "keyword windowrule " + fields.join(", "), legacyEmpty: [], lua: "" }
}

// The first plan after a start of the shell in the Lua dialect: the named
// rules an earlier run of the shell declared since the last config reload
// (the Lua global `buchhwin_places`) are switched off unless they are among
// `names`, so a place whose screen went while the shell was not running
// sends nothing. A reload clears the global with the rules: then there is
// nothing to sweep. Sent again while nothing is known yet (no place has a
// screen here), which changes nothing.
function ruleSweep(names) {
    const keep = (Array.isArray(names) ? names : []).map(name => "[" + Hypr.luaString(name) + "] = true").join(", ")
    return { legacy: "", legacyEmpty: [], lua: "local keep = { " + keep + " }\n"
        + "for name in pairs(buchhwin_places or {}) do if not keep[name] then hl.window_rule({ name = name, enabled = false }) end end" }
}

// The rules wanted now, from the placements: [{ app, name, match, target,
// command }], one per placement whose screen is here and whose app has a
// window to match. `entryFor(app)` -> { id, startupClass, name, categories }
// (the desktop entry, or just { id } for an app that is not installed: its
// id may still be its windows' class).
function wantedRules(store, monitors, offsets, entryFor) {
    const result = []
    for (const rule of (store && store.placement) || []) {
        const target = ruleTarget(rule, monitors, offsets)
        if (!target) continue
        const entry = typeof entryFor === "function" ? entryFor(rule.app) : null
        const match = matchFor(entry || { id: rule.app })
        if (!match) continue
        if (target.monitor.length && !validMonitorName(target.monitor)) continue
        const name = ruleName(match, target)
        result.push({ app: rule.app, name: name, match: match, target: target, command: ruleCommand(name, match, target) })
    }
    return result
}

// What to send to get from the rules Hyprland has from us (`known`: { name:
// { on, match, target } } since the last config reload, {} after a start or
// a reload) to the ones `wanted`. The ones no longer wanted go first - off
// by their names in Lua, released in the conf dialect (ruleRelease) - so a
// placement changed in place is its old rule taken back and then its new one
// declared, which comes later and wins. Then the new ones are declared and
// the known ones that are off come back: on by name in Lua, declared again in
// the conf dialect, after their release. A released conf rule's floating
// holds until the next reload; those are counted in `stale`.
// -> { commands, known, stale }
function rulePlan(known, wanted, lua) {
    const next = Object.assign({}, known || {})
    const fresh = Object.keys(next).length === 0
    const names = {}
    const unique = []
    for (const item of Array.isArray(wanted) ? wanted : []) {
        if (!item || names[item.name]) continue
        names[item.name] = true
        unique.push(item)
    }
    const commands = lua && fresh ? [ruleSweep(unique.map(item => item.name))] : []
    for (const name of Object.keys(next)) {
        const state = next[name]
        if (names[name] || !state || state.on !== true) continue
        const release = lua ? ruleSwitch(name, false) : ruleRelease(state.match, state.target)
        if (release) commands.push(release)
        next[name] = Object.assign({}, state, { on: false })
    }
    for (const item of unique) {
        const state = next[item.name]
        if (state && state.on === true) continue
        commands.push(state && lua ? ruleSwitch(item.name, true) : item.command)
        next[item.name] = { on: true, match: item.match, target: item.target }
    }
    const stale = lua ? 0 : Object.keys(next).filter(name => next[name].on !== true && !!next[name].target && next[name].target.float === true).length
    return { commands: commands, known: next, stale: stale }
}

// ---- words ---------------------------------------------------------------------
// The row under an app in Settings > Apps: "Workspace 3 on U2723QE (DP-10) ·
// floating", "The shown workspace on eDP-1", "Floating on any screen".
// `label` is the screen as the page names it ("" when it is not connected).
function describeRule(rule, label) {
    if (!rule) return ""
    const hasScreen = text(rule.screen).length > 0 || text(rule.screenName).length > 0
    if (!hasScreen) return rule.float ? "Floating on any screen" : "Any screen"
    const screen = text(label).length ? label : (text(rule.screen) || text(rule.screenName)) + ", not connected"
    const where = (rule.workspace > 0 ? "Workspace " + rule.workspace : "The shown workspace") + " on " + screen
    return rule.float ? where + " · floating" : where
}

// The dock menu's "Always open here": the dock's screen and the workspace it
// shows, as a placement. `local` is that workspace's place in the screen's
// block (1-10), 0 for one beyond it.
function hereRule(app, monitor, local, block) {
    if (!validId(app) || !monitor || !validMonitorName(monitor.name)) return null
    return sanitizeRule({ app: app, screen: text(monitor.description), screenName: monitor.name,
                          workspace: local, float: false }, block)
}

// Whether the app's placement is that one already (the menu then offers to
// let it go).
function isHere(rule, here) {
    if (!rule || !here || rule.workspace !== here.workspace || rule.float) return false
    return text(rule.screen).length > 0 ? rule.screen === here.screen : rule.screenName === here.screenName
}
