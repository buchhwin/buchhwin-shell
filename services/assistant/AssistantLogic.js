.pragma library

// The assistant panel's rules (shell/assistant/AssistantPanel.qml through
// services/AssistantService.qml): a chat with a language model that Ollama
// runs on this computer, over its HTTP API on the loopback interface and
// nowhere else. No cloud, no key, no account: an address that is not this
// computer is refused here, before curl is ever started, and a model Ollama
// itself only proxies to its cloud is not offered. What the user asked is
// kept nowhere but in the panel, unless they switch the history file on
// (Settings > Desktop extras > Assistant), which is then the user's alone
// (0600).

var DEFAULT_URL = "http://127.0.0.1:11434"
var DEFAULT_PORT = 11434
var TAGS_PATH = "/api/tags"
var CHAT_PATH = "/api/chat"

// How long a reply may take, end to end, and how long the stream may stand
// still. A model on the CPU can think for minutes, and loading a big one
// from disk sends nothing for a while; a stream that says nothing for five
// minutes is not coming back.
var CHAT_MAX_SECONDS = 900
var STALL_SECONDS = 300
// The model list answers at once when Ollama runs; five seconds is a hung
// server, not a slow one.
var TAGS_MAX_SECONDS = 5

// What goes back to the model with each question: the conversation so far,
// newest last, up to these. Ollama cuts a context that is too long for the
// model itself, but it first has to read all of it, and a long chat would
// send its whole history with every line.
var CONTEXT_MESSAGES = 24
var CONTEXT_CHARS = 24000
// What the history file keeps, at most.
var HISTORY_MESSAGES = 200
var HISTORY_VERSION = 1
// One message's text, at most, in the panel and in the file: a runaway
// model that never stops is cut here rather than grown into a string the
// panel has to lay out on every token.
var MESSAGE_CHARS = 100000

// ---- the address -----------------------------------------------------------

// Whether a host name or address is this computer. The whole of 127/8 is
// loopback; "localhost" is resolved by curl itself to loopback without
// asking a resolver (curl 7.78 and later), and IPv6 has the one address.
function isLoopback(host) {
    const text = String(host === undefined || host === null ? "" : host).trim().toLowerCase()
    if (text === "localhost" || text === "::1" || text === "0:0:0:0:0:0:0:1") return true
    const parts = text.split(".")
    if (parts.length !== 4 || parts[0] !== "127") return false
    return parts.every(part => /^\d{1,3}$/.test(part) && Number(part) <= 255)
}

// "http://127.0.0.1:11434" for an address on this computer, "" for anything
// else. Only plain http (Ollama serves nothing else, and a https:// address
// would be a proxy somewhere), no path, no user, no query: the paths are the
// shell's own. An empty setting is the default address.
function endpoint(text) {
    const value = String(text === undefined || text === null ? "" : text).trim()
    if (!value.length) return DEFAULT_URL
    const match = /^http:\/\/(\[[0-9a-fA-F:.]+\]|[A-Za-z0-9.-]+)(?::(\d{1,5}))?\/?$/.exec(value)
    if (!match) return ""
    const host = match[1].toLowerCase()
    const bare = host.charAt(0) === "[" ? host.slice(1, -1) : host
    if (!isLoopback(bare)) return ""
    const port = match[2] === undefined ? DEFAULT_PORT : Number(match[2])
    if (!(port >= 1 && port <= 65535)) return ""
    return "http://" + host + ":" + port
}

// The curl command for one request, or [] for an address that is not this
// computer (or none at all) and for a path that is not one of the two the
// assistant asks. No ~/.curlrc (`--disable`, which only works as the first
// argument: a `proxy`, `resolve` or `connect-to` line there would carry a
// question to another machine just the same), no proxy whatever the
// environment says (an http_proxy in the session would), http only, no
// redirect followed. A body is read from stdin (`@-`), so a question is
// never a process argument the whole system can read.
function curlCommand(base, path, withBody) {
    const given = String(base === undefined || base === null ? "" : base).trim()
    const address = given.length ? endpoint(given) : ""
    if (!address.length || (path !== TAGS_PATH && path !== CHAT_PATH)) return []
    const args = ["curl", "--disable", "--silent", "--show-error", "--noproxy", "*", "--proto", "=http", "--max-redirs", "0",
                  "--connect-timeout", "2"]
    if (withBody === true)
        args.push("--no-buffer", "--max-time", String(CHAT_MAX_SECONDS), "--speed-limit", "1",
                  "--speed-time", String(STALL_SECONDS), "--header", "Content-Type: application/json",
                  "--data-binary", "@-")
    else
        args.push("--max-time", String(TAGS_MAX_SECONDS))
    args.push(address + path)
    return args
}

// ---- the models ------------------------------------------------------------

// A model Ollama only passes on to ollama.com ("gpt-oss:120b-cloud"): the
// list says so with `remote_host`/`remote_model`, and the name ends in
// "cloud". The assistant is local or nothing, so these are left out.
function isRemote(entry) {
    if (!entry || typeof entry !== "object") return true
    if (entry.remote_host || entry.remote_model) return true
    return /(?:^|[:-])cloud$/i.test(String(entry.name || ""))
}

// "llama3.2 · 3.2B" for an entry of /api/tags: the name without the default
// tag, and the size Ollama names when it knows it.
function modelLabel(entry) {
    const name = String(entry && entry.name || "").replace(/:latest$/, "")
    const details = entry && entry.details && typeof entry.details === "object" ? entry.details : {}
    const size = typeof details.parameter_size === "string" ? details.parameter_size.trim() : ""
    return size.length ? name + " · " + size : name
}

// { models: [{ name, label }], skipped } from /api/tags' answer, sorted by
// name; null for an answer that is not Ollama's. `skipped` counts the cloud
// models left out, so the panel can say why one the user pulled is missing.
function parseModels(text) {
    let data = null
    try { data = JSON.parse(String(text === undefined || text === null ? "" : text)) } catch (error) { return null }
    if (!data || typeof data !== "object" || !Array.isArray(data.models)) return null
    const named = data.models.filter(entry => entry && typeof entry.name === "string" && entry.name.trim().length)
    const local = named.filter(entry => !isRemote(entry))
    const seen = {}
    const models = []
    for (const entry of local) {
        const name = entry.name.trim()
        if (seen[name]) continue
        seen[name] = true
        models.push({ name: name, label: modelLabel(entry) })
    }
    models.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
    return { models: models, skipped: named.length - local.length }
}

// The model to ask: the one chosen in Settings while Ollama still has it,
// else the first there is ("" with none). A chosen model that was removed
// does not leave the panel with nothing to ask.
function chooseModel(stored, models) {
    const names = (models || []).map(entry => entry && entry.name).filter(name => typeof name === "string")
    const wanted = String(stored === undefined || stored === null ? "" : stored)
    if (wanted.length && names.indexOf(wanted) >= 0) return wanted
    return names.length ? names[0] : ""
}

// ---- a conversation --------------------------------------------------------

function validMessage(message) {
    return !!message && (message.role === "user" || message.role === "assistant")
        && typeof message.content === "string"
}

// What goes to the model: the newest messages within CONTEXT_MESSAGES and
// CONTEXT_CHARS, as { role, content }, starting with a question - a reply
// without the question it answers only confuses a small model. The newest
// question always goes, cut to the budget if it is longer than all of it.
function contextMessages(messages, maxMessages, maxChars) {
    const count = maxMessages > 0 ? maxMessages : CONTEXT_MESSAGES
    const budget = maxChars > 0 ? maxChars : CONTEXT_CHARS
    const list = (messages || []).filter(validMessage)
        .filter(message => message.role === "user" || message.content.length > 0)
    const picked = []
    let used = 0
    for (let index = list.length - 1; index >= 0 && picked.length < count; index -= 1) {
        const content = list[index].content
        if (picked.length && used + content.length > budget) break
        picked.unshift({ role: list[index].role, content: picked.length ? content : content.slice(-budget) })
        used += Math.min(content.length, budget)
    }
    while (picked.length > 1 && picked[0].role !== "user") picked.shift()
    return picked
}

// The body of one /api/chat request, streamed.
function requestBody(model, messages) {
    return JSON.stringify({ model: String(model || ""), messages: contextMessages(messages), stream: true })
}

// One line of the stream: { content, thinking, done, reason, tokens,
// seconds }, { error } for Ollama's own error line (a model that is not
// there, one that does not fit into memory) or for a line that is not JSON,
// and null for an empty line. A thinking model sends `thinking` before its
// answer; the panel says "Thinking …" for it rather than showing it.
function parseChunk(line) {
    const text = String(line === undefined || line === null ? "" : line).trim()
    if (!text.length) return null
    let data = null
    try { data = JSON.parse(text) } catch (error) { return { error: "unreadable" } }
    if (!data || typeof data !== "object" || Array.isArray(data)) return { error: "unreadable" }
    if (typeof data.error === "string") return { error: data.error.length ? data.error : "unreadable" }
    const message = data.message && typeof data.message === "object" ? data.message : {}
    const tokens = Number(data.eval_count)
    const nanos = Number(data.eval_duration)
    return {
        content: typeof message.content === "string" ? message.content : "",
        thinking: typeof message.thinking === "string" && message.thinking.length > 0,
        done: data.done === true,
        reason: typeof data.done_reason === "string" ? data.done_reason : "",
        tokens: isFinite(tokens) && tokens > 0 ? Math.round(tokens) : 0,
        seconds: isFinite(nanos) && nanos > 0 ? nanos / 1e9 : 0
    }
}

// Text that grew by `content`, cut at MESSAGE_CHARS.
function appended(text, content) {
    const next = String(text || "") + String(content || "")
    return next.length > MESSAGE_CHARS ? next.slice(0, MESSAGE_CHARS) : next
}

// ---- what went wrong, in words -----------------------------------------------

// curl's exit code as a kind: "offline" (nothing listens), "timeout",
// "dropped" (the connection went in the middle), "" for success.
function curlFailure(code) {
    const value = Number(code)
    if (value === 0) return ""
    if (value === 7) return "offline"
    if (value === 28) return "timeout"
    if (value === 52 || value === 56 || value === 18) return "dropped"
    return "failed"
}

// Ollama's error line as a kind: the model is gone ("model 'x' not found,
// try pulling it first"), the machine has too little memory for it, or
// something else.
function ollamaFailure(message) {
    const text = String(message || "").toLowerCase()
    if (text === "unreadable") return "unreadable"
    if (text.indexOf("not found") >= 0) return "missingModel"
    if (text.indexOf("memory") >= 0) return "memory"
    return "ollama"
}

// What the panel says about a failed reply.
function failureText(kind, model) {
    const name = String(model || "").replace(/:latest$/, "")
    switch (kind) {
    case "offline": return "Ollama is not running on this computer any more."
    case "timeout": return "The model did not answer in time."
    case "dropped": return "Ollama stopped in the middle of the answer."
    case "missingModel": return name.length ? name + " is not in Ollama any more." : "The model is not in Ollama any more."
    case "memory": return "The model does not fit into this computer's memory. A smaller one may."
    case "unreadable": return "Ollama's answer could not be read."
    case "ollama": return "Ollama could not answer."
    case "failed": return "The question did not reach Ollama."
    }
    return ""
}

// The panel's state in words: { title, description, steps } for the empty
// panel (EmptyState: no full stop at the end). `steps` are the commands to
// run, one each, shown as blocks to copy: written into the prose they could
// not be copied, and "start it" left out the command for it. `installHint`
// is DistroService.installHint("ollama"), `installCommand` the command alone
// ("" where the distribution is not known: the hint says what to do then).
var START_COMMAND = "sudo systemctl enable --now ollama"
var PULL_COMMAND = "ollama pull llama3.2"
function stateText(state, installed, installHint, skipped, installCommand) {
    switch (state) {
    case "refused":
        return { title: "Only this computer",
                 description: "The address in Settings is not on this computer. The assistant talks to Ollama on this computer only (127.0.0.1, localhost or ::1)",
                 steps: [] }
    case "offline":
        if (installed === false) {
            const command = String(installCommand || "")
            return { title: "Ollama is not installed",
                     description: "The assistant uses a model that runs on this computer, through Ollama. "
                         + (command.length ? "Install it, start it and pull a model"
                            : String(installHint || "Install ollama with your package manager").replace(/\.$/, "")
                              + ", then start it and pull a model"),
                     steps: (command.length ? [command] : []).concat([START_COMMAND, PULL_COMMAND]) }
        }
        return { title: "Ollama is not running",
                 description: "Start it, or run ollama serve in a terminal, then check again",
                 steps: [START_COMMAND] }
    case "noModels":
        return { title: "No model yet",
                 description: (skipped > 0 ? "Cloud models are not offered: everything stays on this computer. " : "")
                     + "Pull one in a terminal, for example llama3.2",
                 steps: [PULL_COMMAND] }
    case "checking":
    case "unknown":
        return { title: "Looking for Ollama …", description: "", steps: [] }
    }
    return { title: "", description: "", steps: [] }
}

// ---- the answer's pieces -------------------------------------------------------

// A reply as text and code: [{ kind: "text" | "code", text, lang, open }].
// Code between ``` fences is set in the mono font with a copy button of its
// own; a fence still open (a reply being written) is code to its end. Blank
// lines around a text piece are dropped, an empty text piece left out.
function segments(text) {
    const lines = String(text === undefined || text === null ? "" : text).split("\n")
    const result = []
    let buffer = []
    let inCode = false
    let lang = ""
    const pushText = () => {
        while (buffer.length && !buffer[0].trim().length) buffer.shift()
        while (buffer.length && !buffer[buffer.length - 1].trim().length) buffer.pop()
        if (buffer.length) result.push({ kind: "text", text: buffer.join("\n"), lang: "", open: false })
        buffer = []
    }
    const pushCode = open => {
        result.push({ kind: "code", text: buffer.join("\n"), lang: lang, open: open })
        buffer = []
    }
    for (const line of lines) {
        const fence = /^\s*```\s*([A-Za-z0-9_+#.-]*)\s*$/.exec(line)
        if (fence && !inCode) {
            pushText()
            inCode = true
            lang = fence[1]
            continue
        }
        if (inCode && /^\s*```\s*$/.test(line)) {
            pushCode(false)
            inCode = false
            lang = ""
            continue
        }
        buffer.push(line)
    }
    if (inCode) pushCode(true)
    else pushText()
    return result
}

// Keys for a view of the pieces that keep a piece's row while it grows:
// its place and its kind, never its text (pitfall 76 - strings key by
// value).
function segmentKeys(list) {
    return (list || []).map((segment, index) => index + ":" + segment.kind)
}

// ---- the history file ----------------------------------------------------------

// The file's text for a conversation: the newest HISTORY_MESSAGES, roles,
// texts and the model that answered - no time, no machine.
function historyText(messages) {
    const kept = (messages || []).filter(validMessage).slice(-HISTORY_MESSAGES).map(message => {
        const entry = { role: message.role, content: message.content.slice(0, MESSAGE_CHARS) }
        if (message.role === "assistant" && typeof message.model === "string" && message.model.length) entry.model = message.model
        if (message.stopped === true) entry.stopped = true
        return entry
    })
    return JSON.stringify({ version: HISTORY_VERSION, messages: kept }) + "\n"
}

// A conversation back from the file: [] for a file that is not one, the
// messages that are valid otherwise, numbered from `firstId`.
function parseHistory(text, firstId) {
    let data = null
    try { data = JSON.parse(String(text === undefined || text === null ? "" : text)) } catch (error) { return [] }
    if (!data || typeof data !== "object" || data.version !== HISTORY_VERSION || !Array.isArray(data.messages)) return []
    let id = Math.max(1, Math.round(Number(firstId)) || 1)
    return data.messages.filter(validMessage).slice(-HISTORY_MESSAGES).map(message => {
        const entry = { id: "m" + id, role: message.role, content: message.content.slice(0, MESSAGE_CHARS),
                        model: typeof message.model === "string" ? message.model : "", stopped: message.stopped === true }
        id += 1
        return entry
    })
}

// The number after the highest "m<n>" id, so new messages never take an id a
// loaded one has.
function nextIdAfter(messages) {
    let highest = 0
    for (const message of messages || []) {
        const match = /^m(\d+)$/.exec(String(message && message.id || ""))
        if (match) highest = Math.max(highest, Number(match[1]))
    }
    return highest + 1
}
