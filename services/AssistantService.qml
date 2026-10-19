pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "assistant/AssistantLogic.js" as Logic

// The assistant panel's conversation (shell/assistant/AssistantPanel.qml): a
// model Ollama runs on this computer, asked over its HTTP API on loopback
// with curl - never another machine (AssistantLogic.endpoint refuses any
// other address before a process starts), never a cloud model. Without
// Ollama the panel says how to get it.
//
// Nothing runs until the panel opens or Settings shows the section: the
// singleton is made by the first thing that reads it, the model list is
// asked for then, and a reply's curl runs only while it streams. The
// conversation lives here, in memory; only with Settings' "Keep the
// conversation" does it go to a file of the user's own (0600) after each
// reply - and switching that off deletes the file.
Singleton {
    id: root

    readonly property string url: Logic.endpoint(SettingsService.value("assistant.url"))
    // Functions and handlers below read `url` itself, not this: inside
    // onUrlChanged this binding may not have caught up yet, and a refused
    // address read as allowed started curl with no address at all.
    readonly property bool refused: url.length === 0
    readonly property string storedModel: SettingsService.value("assistant.model") || ""
    readonly property bool keepHistory: SettingsService.value("assistant.keepHistory") === true
    readonly property string historyPath: Paths.stateDir + "/assistant-history.json"

    // "unknown" before the first look, "checking", "ready", "offline",
    // "noModels", "refused".
    property string status: refused ? "refused" : "unknown"
    property var models: []
    // Cloud models Ollama listed and the assistant left out.
    property int skipped: 0
    // Whether the ollama command is here at all, asked once Ollama does not
    // answer: the panel's hint is then how to install it, not how to start it.
    property bool installed: true
    readonly property string model: Logic.chooseModel(storedModel, models)
    readonly property var current: models.find(entry => entry.name === model) || null

    property var messages: []
    readonly property var messageIds: messages.map(message => message.id)
    property int nextId: 1
    // The reply being written, and whether the model is still thinking
    // before it (a reasoning model's first part).
    property string streamText: ""
    property bool thinking: false
    property bool busy: false
    // What went wrong with the last reply, in words; "" for nothing.
    property string error: ""
    // Asked before the model list was there (`assistant ask`): sent once it is.
    property string queued: ""
    property bool historyLoaded: false

    onUrlChanged: {
        models = []
        status = url.length ? "unknown" : "refused"
        if (watchers > 0) refresh()
    }
    // Off deletes the file. On keeps the conversation going now - the file
    // then holds what is here, and reading it back would show it twice -,
    // or brings back the one kept before. Not while the settings are still
    // loading: their arrival is no change of mind, and an empty conversation
    // saved then would have deleted the file it was about to read.
    onKeepHistoryChanged: {
        if (!SettingsService.loaded) return
        if (!keepHistory) forgetHistory()
        else if (messages.length) {
            historyLoaded = true
            saveHistory()
        } else {
            historyLoaded = false
            loadHistory()
        }
    }

    // Something that shows the state (the panel while open, Settings while
    // the section is on screen) says so; the model list is asked for when
    // the first one arrives.
    property int watchers: 0
    function watch(on) {
        watchers = Math.max(0, watchers + (on ? 1 : -1))
        if (on) {
            refresh()
            loadHistory()
        }
    }

    function refresh() {
        const command = Logic.curlCommand(url, Logic.TAGS_PATH)
        if (!command.length) {
            status = "refused"
            return
        }
        if (tags.running) return
        if (status !== "ready") status = "checking"
        tags.command = Paths.bound(command)
        tags.running = true
    }

    function send(text) {
        const prompt = String(text === undefined || text === null ? "" : text).trim()
        const command = Logic.curlCommand(url, Logic.CHAT_PATH, true)
        if (!prompt.length || busy || !command.length) return false
        if (!model.length) {
            queued = prompt
            refresh()
            return true
        }
        // The kept conversation, if it was never read (`assistant ask` before
        // the panel was ever open): it comes back in front of this one.
        loadHistory()
        const question = { id: "m" + nextId, role: "user", content: prompt.slice(0, Logic.MESSAGE_CHARS), model: "", stopped: false }
        nextId += 1
        messages = messages.concat([question])
        streamText = ""
        thinking = false
        error = ""
        busy = true
        chat.failure = ""
        chat.stopped = false
        chat.discard = false
        chat.model = model
        chat.body = Logic.requestBody(model, messages)
        chat.command = Paths.bound(command)
        chat.running = true
        return true
    }
    // `assistant ask`: the question waits for the model list if it has to.
    function ask(text) {
        const prompt = String(text === undefined || text === null ? "" : text).trim()
        if (!prompt.length || !url.length) return false
        if (status !== "ready") {
            queued = prompt
            refresh()
            return true
        }
        return send(prompt)
    }

    // The reply so far stays, marked as stopped.
    function stop() {
        queued = ""
        if (!chat.running) return
        chat.stopped = true
        chat.signal(15)
    }

    // A new conversation: the old one is gone, from the file too - and a
    // reply still being written with it, which would otherwise arrive in the
    // new one once curl has ended.
    function clear() {
        if (chat.running) chat.discard = true
        stop()
        messages = []
        streamText = ""
        error = ""
        if (keepHistory) forgetHistory()
    }

    // Copies a text the shell's way (the emoji picker's, the calculator's).
    function copy(text) {
        Quickshell.clipboardText = String(text || "")
    }

    // Counts and states only - never a question, an answer or a model's
    // name (IPC `assistant get`).
    function describe() {
        return JSON.stringify({ status: status, models: models.length, skipped: skipped, modelChosen: model.length > 0,
                                busy: busy, thinking: thinking, messages: messages.length, failed: error.length > 0,
                                keepHistory: keepHistory, installed: installed })
    }

    // ---- the model list --------------------------------------------------------
    Process {
        id: tags
        stdout: StdioCollector { id: tagsOut }
        // An Ollama that is not running is a state, not an error: curl's
        // "Failed to connect" is not written to the log.
        stderr: StdioCollector {}
        onExited: code => {
            // A question that waited for the list goes with it when Ollama
            // is not there: kept, it would be sent whenever Ollama answered
            // next, long after it was asked.
            if (code !== 0) {
                root.models = []
                root.status = "offline"
                root.queued = ""
                if (!installCheck.running) installCheck.running = true
                return
            }
            const parsed = Logic.parseModels(tagsOut.text)
            if (!parsed) {
                root.models = []
                root.status = "offline"
                root.queued = ""
                return
            }
            root.installed = true
            root.skipped = parsed.skipped
            if (JSON.stringify(parsed.models) !== JSON.stringify(root.models)) root.models = parsed.models
            root.status = parsed.models.length ? "ready" : "noModels"
            if (root.queued.length && root.status === "ready") {
                const waiting = root.queued
                root.queued = ""
                root.send(waiting)
            } else if (root.status !== "ready") {
                root.queued = ""
            }
        }
    }
    Process {
        id: installCheck
        command: ["sh", "-c", "command -v ollama"]
        onExited: code => { root.installed = code === 0 }
    }

    // ---- a reply -----------------------------------------------------------------
    // The request on stdin (a question is never a process argument), the
    // stream line by line.
    Process {
        id: chat
        property string body: "{}"
        property string failure: ""
        property string model: ""
        property bool stopped: false
        property bool discard: false
        stdinEnabled: true
        onStarted: {
            write(body)
            stdinEnabled = false
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.takeChunk(data)
        }
        stderr: StdioCollector {}
        onExited: code => {
            stdinEnabled = true
            root.finishReply(code)
        }
    }

    function takeChunk(line) {
        const chunk = Logic.parseChunk(line)
        if (!chunk) return
        if (chunk.error !== undefined) {
            chat.failure = chunk.error
            return
        }
        if (chunk.content.length) {
            streamText = Logic.appended(streamText, chunk.content)
            thinking = false
        } else if (chunk.thinking && !streamText.length) {
            thinking = true
        }
    }

    function finishReply(code) {
        if (chat.discard) {
            chat.discard = false
            streamText = ""
            thinking = false
            busy = false
            return
        }
        const reply = streamText
        const failed = chat.failure.length ? Logic.ollamaFailure(chat.failure)
            : chat.stopped ? "" : Logic.curlFailure(code)
        if (reply.length || chat.stopped) {
            messages = messages.concat([{ id: "m" + nextId, role: "assistant", content: reply, model: chat.model,
                                          stopped: chat.stopped || (failed.length > 0 && reply.length > 0) }])
            nextId += 1
        }
        streamText = ""
        thinking = false
        busy = false
        error = Logic.failureText(failed, chat.model)
        if (failed === "offline") {
            status = "offline"
            models = []
        } else if (failed === "missingModel") {
            refresh()
        }
        saveHistory()
    }

    // ---- the history file ----------------------------------------------------------
    // Read once, the first time something shows the conversation or asks
    // while it is kept. A question asked before the file was back goes after
    // the kept conversation rather than in its place: the next save would
    // have written the new conversation alone, and the kept one was gone.
    function loadHistory() {
        if (!keepHistory || historyLoaded) return
        historyLoaded = true
        fileTurn("read")
    }
    // Written whole after each reply, through a file only the user can read,
    // moved into place so a crash never leaves half a conversation.
    function saveHistory() {
        if (!keepHistory) return
        fileTurn(messages.length ? "save" : "forget")
    }
    // "New chat", or Keep switched off: the file goes, and a read of it still
    // to come or under way no longer brings the old conversation back.
    function forgetHistory() {
        fileQueue = fileQueue.filter(action => action !== "read")
        if (historyRead.running) historyRead.dropped = true
        fileTurn("forget")
    }

    // The file's turns - "read", "save", "forget" - one at a time, in the
    // order asked: a deletion that overtook a write still running had the
    // conversation back in the file a moment later, Keep switched off or not.
    // A save or a deletion stands for the whole conversation, so one that
    // still waits gives way to the newest.
    property var fileQueue: []
    function fileTurn(action) {
        const queue = fileQueue.slice()
        if (action !== "read" && queue.length && queue[queue.length - 1] !== "read") queue.pop()
        queue.push(action)
        fileQueue = queue
        nextFileTurn()
    }
    function nextFileTurn() {
        if (historyRead.running || historyFile.running || !fileQueue.length) return
        const action = fileQueue[0]
        fileQueue = fileQueue.slice(1)
        if (action === "read") {
            historyRead.dropped = false
            historyRead.command = ["sh", "-c", "test -f \"$1\" && cat -- \"$1\"", "sh", historyPath]
            historyRead.running = true
        } else if (action === "save" && keepHistory && messages.length) {
            historyFile.text = Logic.historyText(messages)
            historyFile.command = ["sh", "-c", "umask 077 && mkdir -p -- \"${1%/*}\" && cat > \"$1.tmp\" && mv -f -- \"$1.tmp\" \"$1\"",
                                   "sh", historyPath]
            historyFile.running = true
        } else if (action === "forget") {
            historyFile.text = ""
            historyFile.command = ["rm", "-f", "--", historyPath, historyPath + ".tmp"]
            historyFile.running = true
        } else {
            Qt.callLater(nextFileTurn)
        }
    }
    Process {
        id: historyRead
        property bool dropped: false
        stdout: StdioCollector { id: historyOut }
        onExited: code => {
            Qt.callLater(root.nextFileTurn)
            if (code !== 0 || dropped) return
            const loaded = Logic.parseHistory(historyOut.text, root.nextId)
            if (!loaded.length) return
            root.messages = loaded.concat(root.messages)
            root.nextId = Logic.nextIdAfter(root.messages)
        }
    }
    Process {
        id: historyFile
        property string text: ""
        stdinEnabled: true
        onStarted: {
            if (text.length) write(text)
            stdinEnabled = false
        }
        stderr: ErrorLog { label: "assistant.history" }
        onExited: {
            stdinEnabled = true
            Qt.callLater(root.nextFileTurn)
        }
    }
}
