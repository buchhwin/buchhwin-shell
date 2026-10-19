.pragma library

// Accounts (Settings > Accounts): parses the sections of read-only busctl JSON
// that scripts/accounts-status.sh prints from Akonadi's AgentManager, turns
// the agent instances that are resources into account rows and builds the argv
// lists for Sync now / Settings … / Remove and for the KDE account wizards.
// Instance and type ids are validated before they reach a command line.
// Account names live in the shell UI only: they never reach a log or the IPC
// output, which carries counts, ids and states.

// Akonadi AgentBase::Status.
var STATUS_IDLE = 0
var STATUS_RUNNING = 1
var STATUS_BROKEN = 2
var STATUS_NOT_CONFIGURED = 3

// Agent instance and agent type ids (also D-Bus arguments).
function validId(id) {
    return typeof id === "string" && /^[A-Za-z0-9_]{1,128}$/.test(id)
}

// busctl --json=short method result: {"type":"s","data":["value"]}. A string
// list ("as") wraps its array in the same way.
function busValue(text) {
    let parsed
    try { parsed = JSON.parse(String(text || "").trim()) } catch (error) { return undefined }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.data)) return undefined
    return parsed.data[0]
}

// Splits the helper output into sections keyed "@name arg".
function sections(text) {
    const result = []
    let current = null
    for (const line of String(text || "").split("\n")) {
        const match = /^@([a-z]+)(?: (.*))?$/.exec(line)
        if (match) {
            current = { name: match[1], arg: (match[2] || "").trim(), lines: [] }
            result.push(current)
        } else if (current) {
            current.lines.push(line)
        }
    }
    return result
}

// Section body lines "key <busctl JSON>" → { key: value }.
function fields(lines) {
    const result = {}
    for (const line of lines || []) {
        const index = String(line).indexOf(" ")
        if (index <= 0) continue
        const key = line.slice(0, index)
        if (!/^[a-z]+$/.test(key)) continue
        result[key] = busValue(line.slice(index + 1))
    }
    return result
}

function stringList(value) {
    return Array.isArray(value) ? value.filter(item => typeof item === "string") : []
}

// What an account holds, in the order that decides its group.
var MIME_KINDS = [
    { kind: "mail", mime: "message/rfc822" },
    { kind: "calendar", mime: "text/calendar" },
    { kind: "contacts", mime: "text/directory" },
    { kind: "notes", mime: "text/x-vnd.akonadi.note" }
]

function kinds(mimeTypes) {
    const list = mimeTypes || []
    return MIME_KINDS.filter(entry => list.indexOf(entry.mime) >= 0).map(entry => entry.kind)
}

function kindLabel(kind) {
    return kind === "mail" ? "Mail" : kind === "calendar" ? "Calendar"
        : kind === "contacts" ? "Contacts" : kind === "notes" ? "Notes" : "Other"
}

function primaryKind(account) {
    return account && account.kinds.length ? account.kinds[0] : "other"
}

// What the account synchronizes, e.g. "Calendar · Contacts".
function contentText(account) {
    if (!account || !account.kinds.length) return ""
    return account.kinds.map(kindLabel).join(" · ")
}

function icon(account) {
    const kind = primaryKind(account)
    return kind === "mail" ? "󰇮" : kind === "calendar" ? "󰸗" : kind === "contacts" ? "󰀄" : "󰒓" // Icons.settingsApp
}

// One @instance section plus its @type section → account row.
function account(id, data, types) {
    const values = data || {}
    const type = typeof values.type === "string" ? values.type : ""
    const info = (types && types[type]) || {}
    const capabilities = stringList(info.caps)
    const mimeTypes = stringList(info.mime)
    const name = typeof values.name === "string" ? values.name.trim() : ""
    return {
        id: id,
        type: type,
        name: name.length ? name : typeof info.name === "string" && info.name.length ? info.name : id,
        typeName: typeof info.name === "string" ? info.name : "",
        typeComment: typeof info.comment === "string" ? info.comment : "",
        iconName: typeof info.icon === "string" ? info.icon : "",
        status: typeof values.status === "number" ? values.status : STATUS_IDLE,
        statusMessage: typeof values.message === "string" ? values.message : "",
        online: values.online === true,
        progress: typeof values.progress === "number" && values.progress > 0 ? Math.round(values.progress) : 0,
        capabilities: capabilities,
        mimeTypes: mimeTypes,
        kinds: kinds(mimeTypes),
        // "Unique" resources (birthdays, search …) are created by KDE PIM
        // itself, not by adding an account.
        builtIn: capabilities.indexOf("Unique") >= 0
    }
}

// Every agent instance id of an @agents line, sorted.
function agentList(arg) {
    return String(arg || "").split(/\s+/).filter(validId).sort()
}

// Whole snapshot → { known, server, tools, agents, accounts }. `agents` is
// null when the snapshot did not list them (the sample, an older helper).
function parseStatus(text) {
    const result = { known: false, server: false, tools: [], agents: null, accounts: [] }
    const types = {}
    const instances = []
    for (const section of sections(text)) {
        if (section.name === "server") {
            result.known = true
            result.server = section.arg === "running"
        } else if (section.name === "tools") {
            result.tools = section.arg.split(/\s+/).filter(name => hasTool(name))
        } else if (section.name === "agents") {
            result.agents = agentList(section.arg)
        } else if (section.name === "type" && validId(section.arg)) {
            types[section.arg] = fields(section.lines)
        } else if (section.name === "instance" && validId(section.arg)) {
            instances.push({ id: section.arg, data: fields(section.lines) })
        }
    }
    result.accounts = sortAccounts(instances.map(entry => account(entry.id, entry.data, types)))
    return result
}

// ---- the poll between whole snapshots ----------------------------------------
// The page polls every 10 s with `accounts-status.sh --status ID…`: @server,
// @agents and, per instance, only what changes while it runs (name, status,
// message, online, progress). Types, icons, MIME types and capabilities stay
// those of the last whole snapshot.

// Whether a snapshot can be brought up to date by a status poll: it has to be
// a whole one of a running server that listed its agents.
function canPoll(status) {
    return !!status && status.known === true && status.server === true && Array.isArray(status.agents)
}

// The instance ids a status poll asks for.
function pollIds(status) {
    return canPoll(status) ? status.accounts.map(item => item.id).filter(validId) : []
}

// A status poll's answer laid over the last whole snapshot, or null when it
// cannot be: the server stopped, the answer is broken, or an agent instance
// came or went - then the next read has to be a whole one. An account the
// answer says nothing about (a call that timed out) keeps what it showed.
function mergeStatus(previous, text) {
    if (!canPoll(previous)) return null
    let server = null
    let agents = null
    const updates = {}
    for (const section of sections(text)) {
        if (section.name === "server") server = section.arg === "running"
        else if (section.name === "agents") agents = agentList(section.arg)
        else if (section.name === "instance" && validId(section.arg)) updates[section.arg] = fields(section.lines)
    }
    if (server !== true || agents === null || agents.join(" ") !== previous.agents.join(" ")) return null
    const accounts = previous.accounts.map(item => {
        const values = updates[item.id]
        if (!values) return item
        const name = typeof values.name === "string" ? values.name.trim() : ""
        return Object.assign({}, item, {
            name: name.length ? name : item.typeName.length ? item.typeName : item.id,
            status: typeof values.status === "number" ? values.status : STATUS_IDLE,
            statusMessage: typeof values.message === "string" ? values.message : "",
            online: values.online === true,
            progress: typeof values.progress === "number" && values.progress > 0 ? Math.round(values.progress) : 0
        })
    })
    return Object.assign({}, previous, { accounts: sortAccounts(accounts) })
}

// Broken first (they need attention), then offline, then by name; resources
// KDE PIM creates itself stay at the end of their group.
function rank(item) {
    if (item.builtIn) return 3
    if (item.status === STATUS_BROKEN) return 0
    if (!item.online) return 1
    return 2
}

function sortAccounts(accounts) {
    return (accounts || []).slice().sort((a, b) => rank(a) - rank(b)
        || a.name.localeCompare(b.name) || a.id.localeCompare(b.id))
}

var GROUPS = [
    { key: "mail", title: "Mail" },
    { key: "calendar", title: "Calendars" },
    { key: "contacts", title: "Contacts" },
    { key: "notes", title: "Notes" },
    { key: "other", title: "Other" }
]

// Accounts by what they hold, in display order; empty groups are dropped.
function groups(accounts) {
    const result = []
    for (const group of GROUPS) {
        const list = (accounts || []).filter(item => primaryKind(item) === group.key)
        if (list.length) result.push({ key: group.key, title: group.title, accounts: list })
    }
    return result
}

function statusText(item) {
    if (!item) return ""
    if (!item.online) return "Offline"
    if (item.status === STATUS_RUNNING) return item.progress > 0 ? "Syncing … " + item.progress + "%" : "Syncing …"
    if (item.status === STATUS_BROKEN) return "Error"
    if (item.status === STATUS_NOT_CONFIGURED) return "Not configured"
    return "Ready"
}

// "error" | "busy" | "muted" | "ok"; the page maps these to theme colours.
function statusTone(item) {
    if (!item) return "muted"
    if (item.status === STATUS_BROKEN || item.status === STATUS_NOT_CONFIGURED) return "error"
    if (!item.online) return "muted"
    return item.status === STATUS_RUNNING ? "busy" : "ok"
}

function syncing(accounts) {
    return (accounts || []).filter(item => item.online && item.status === STATUS_RUNNING).length
}

// Timestamps are milliseconds; both unknown times and a missing reference give
// an empty string.
function lastSyncText(timestamp, now) {
    const stamp = Number(timestamp) || 0
    const reference = Number(now) || 0
    if (stamp <= 0 || reference <= 0) return ""
    const seconds = Math.max(0, Math.round((reference - stamp) / 1000))
    if (seconds < 60) return "just now"
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + (minutes === 1 ? " minute ago" : " minutes ago")
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago")
    const days = Math.floor(hours / 24)
    return days === 1 ? "yesterday" : days + " days ago"
}

// Status messages that only repeat what the status column already shows.
var PLAIN_MESSAGES = ["Ready", "Idle", "Offline", "Online", "Not configured", "Error"]

// Row subtitle: resource type, the agent's own message when it says more than
// the status word, and the last sync this session saw.
function subtitle(item, lastSync, now) {
    if (!item) return ""
    const parts = []
    const content = contentText(item)
    const type = item.typeName.length ? item.typeName : item.type
    if (type.length) parts.push(content.length && content !== type ? type + " · " + content : type)
    else if (content.length) parts.push(content)
    const message = item.statusMessage.trim()
    if (message.length && message !== statusText(item) && PLAIN_MESSAGES.indexOf(message) < 0) parts.push(message)
    const sync = lastSyncText(lastSync, now)
    if (sync.length) parts.push("Last sync " + sync)
    return parts.join(" · ")
}

function summary(status) {
    if (!status || !status.known) return "Checking accounts …"
    if (!status.server) return "KDE PIM (Akonadi) is not running"
    const accounts = status.accounts || []
    if (!accounts.length) return "No accounts yet"
    const broken = accounts.filter(item => item.status === STATUS_BROKEN).length
    const offline = accounts.filter(item => !item.online).length
    const parts = [accounts.length === 1 ? "1 account" : accounts.length + " accounts"]
    if (broken) parts.push(broken === 1 ? "1 with an error" : broken + " with errors")
    if (offline) parts.push(offline + " offline")
    return parts.join(" · ")
}

// ---- commands ---------------------------------------------------------------

var MANAGER = ["busctl", "--user", "--auto-start=no", "call", "org.freedesktop.Akonadi.Control",
               "/AgentManager", "org.freedesktop.Akonadi.AgentManager"]

// One account action; null for unknown actions or ids. The id is always its
// own argv entry and never part of a shell string.
function command(action, id) {
    if (!validId(id)) return null
    switch (action) {
    case "sync": return MANAGER.concat(["agentInstanceSynchronize", "s", id])
    // The agent opens its own configuration dialog; 0 means "no parent window".
    case "configure": return MANAGER.concat(["agentInstanceConfigure", "sx", id, "0"])
    case "remove": return MANAGER.concat(["removeAgentInstance", "s", id])
    default: return null
    }
}

// KDE's own wizards; the shell never asks for credentials itself.
// `app` is the wizard's desktop entry: the name scripts/launch-app.sh gives
// its unit, which starts it with the session's environment.
var TOOLS = {
    kaccounts: { label: "Online accounts …", hint: "Google, Nextcloud and other providers",
                 argv: ["kcmshell6", "kcm_kaccounts"], app: "kcm_kaccounts" },
    systemsettings: { label: "Online accounts …", hint: "Google, Nextcloud and other providers",
                      argv: ["systemsettings", "kcm_kaccounts"], app: "systemsettings" },
    accountwizard: { label: "Mail & groupware …", hint: "IMAP, POP3, CalDAV, CardDAV and iCal files",
                     argv: ["accountwizard"], app: "org.kde.accountwizard" }
}
var TOOL_ORDER = ["kaccounts", "systemsettings", "accountwizard"]

function hasTool(name) {
    return typeof name === "string" && Object.prototype.hasOwnProperty.call(TOOLS, name)
}

// Wizards found on this machine, in display order and without duplicates
// (kcmshell6 and systemsettings open the same page).
function addOptions(tools) {
    const list = (tools || []).filter(hasTool)
    const result = []
    for (const key of TOOL_ORDER) {
        if (list.indexOf(key) < 0) continue
        const entry = TOOLS[key]
        if (result.some(item => item.label === entry.label)) continue
        result.push({ tool: key, label: entry.label, hint: entry.hint, argv: entry.argv.slice() })
    }
    return result
}

function addCommand(tool) {
    return hasTool(tool) ? TOOLS[tool].argv.slice() : null
}

function appId(tool) {
    return hasTool(tool) ? TOOLS[tool].app : ""
}

// Shell line for the dry run shown outside the real session.
function commandText(argv) {
    return (argv || []).map(arg => /^[A-Za-z0-9_\-.:\/=]+$/.test(arg) ? arg
        : "'" + String(arg).replace(/'/g, "'\\''") + "'").join(" ")
}

// Runs a command and appends its exit code, so one stdout stream carries both.
function wrap(argv) {
    return ["sh", "-c", "\"$@\" 2>&1; printf '\\n@exit %s\\n' \"$?\"", "sh"].concat(argv)
}

function parseResult(text) {
    const value = String(text || "")
    const match = /\n?@exit (\d+)\s*$/.exec(value)
    if (!match) return { code: -1, output: value.trim() }
    return { code: parseInt(match[1]), output: value.slice(0, match.index).trim() }
}

// Messages never repeat the account name: busctl errors can quote arguments.
function errorText(action, output) {
    const text = String(output || "")
    if (/Connection timed out|No such file or directory|not provided by any \.service/i.test(text))
        return "KDE PIM (Akonadi) did not answer"
    return action === "sync" ? "The account could not be synchronized"
        : action === "configure" ? "The settings dialog could not be opened"
        : action === "remove" ? "The account could not be removed"
        : "The action failed"
}

function successText(action) {
    return action === "sync" ? "Synchronizing …"
        : action === "configure" ? "The settings dialog is opening …"
        : action === "remove" ? "The account was removed" : ""
}
