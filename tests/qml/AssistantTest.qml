import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/assistant/AssistantLogic.js" as A

// The assistant's rules (services/assistant/AssistantLogic.js): Ollama on
// this computer and nowhere else, its model list without the cloud models,
// the stream, what goes back to the model, the reply's pieces and the
// history file.
ShellRoot {
    Component.onCompleted: {
        // ---- the address: this computer or nothing ----------------------------
        T.eq([A.endpoint(""), A.endpoint(undefined), A.endpoint(null), A.endpoint("  ")],
             [A.DEFAULT_URL, A.DEFAULT_URL, A.DEFAULT_URL, A.DEFAULT_URL], "an empty setting is the default address")
        T.eq(A.DEFAULT_URL, "http://127.0.0.1:11434", "Ollama's own default")
        T.eq([A.endpoint("http://127.0.0.1:11434"), A.endpoint("http://localhost:8080/"), A.endpoint("http://LOCALHOST"),
              A.endpoint("http://[::1]:11434"), A.endpoint("http://127.1.2.3:1")],
             ["http://127.0.0.1:11434", "http://localhost:8080", "http://localhost:11434", "http://[::1]:11434",
              "http://127.1.2.3:1"], "loopback addresses, normalised, the port defaulted")
        T.eq(["https://127.0.0.1:11434", "http://192.168.1.5:11434", "http://ollama.example.com", "http://localhost.example.com",
              "http://10.0.0.1", "http://0.0.0.0:11434", "http://user@127.0.0.1", "http://127.0.0.1:11434/api",
              "http://127.0.0.1:11434?x=1", "http://127.0.0.1:0", "http://127.0.0.1:65536", "http://[::2]:11434",
              "file:///etc/passwd", "127.0.0.1:11434", "http://127.0.0.256", "http://127.0.0", "ftp://localhost"].map(A.endpoint),
             ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
             "anything that is not this computer, or not plain http with a port, is refused")
        T.eq([A.isLoopback("127.0.0.1"), A.isLoopback("127.255.255.254"), A.isLoopback("::1"), A.isLoopback("localhost"),
              A.isLoopback("128.0.0.1"), A.isLoopback("127.0.0.1.example"), A.isLoopback(""), A.isLoopback(undefined)],
             [true, true, true, true, false, false, false, false], "loopback by address")

        // ---- curl: no proxy, no redirect, the body on stdin --------------------
        const tags = A.curlCommand("http://127.0.0.1:11434", A.TAGS_PATH)
        T.eq(tags.slice(0, 2), ["curl", "--disable"], "curl, without ~/.curlrc (only as the first argument)")
        T.eq(A.curlCommand("http://127.0.0.1:11434", A.CHAT_PATH, true)[1], "--disable", "the chat as well")
        T.eq(tags[tags.length - 1], "http://127.0.0.1:11434/api/tags", "the list's address last")
        T.eq([tags.indexOf("--noproxy") >= 0 && tags[tags.indexOf("--noproxy") + 1] === "*",
              tags[tags.indexOf("--proto") + 1], tags[tags.indexOf("--max-redirs") + 1],
              tags[tags.indexOf("--max-time") + 1], tags.indexOf("--data-binary") < 0, tags.indexOf("--location") < 0],
             [true, "=http", "0", "5", true, true], "no proxy, http only, no redirect, a short limit, no body")
        const chat = A.curlCommand("http://localhost:9000", A.CHAT_PATH, true)
        T.eq([chat[chat.length - 1], chat[chat.indexOf("--data-binary") + 1], chat.indexOf("--no-buffer") >= 0,
              chat[chat.indexOf("--max-time") + 1], chat[chat.indexOf("--speed-time") + 1]],
             ["http://localhost:9000/api/chat", "@-", true, "900", "300"], "the chat streams its body from stdin")
        T.eq(chat.filter(arg => arg.indexOf("{") >= 0), [], "no question ever on the command line")
        T.eq([A.curlCommand("http://192.168.1.5:11434", A.TAGS_PATH), A.curlCommand("", A.TAGS_PATH),
              A.curlCommand(undefined, A.CHAT_PATH, true), A.curlCommand("http://127.0.0.1:11434", "/api/pull"),
              A.curlCommand("http://127.0.0.1:11434", "/../x")], [[], [], [], [], []],
             "another machine, no address or another path: no command at all")

        // ---- the model list ----------------------------------------------------
        const listed = A.parseModels(JSON.stringify({ models: [
            { name: "qwen2.5:7b", details: { parameter_size: "7.6B" } },
            { name: "llama3.2:latest", details: { parameter_size: "3.2B" } },
            { name: "gpt-oss:120b-cloud", remote_host: "https://ollama.com:443", remote_model: "gpt-oss:120b" },
            { name: "deepseek-v3.1:671b-cloud" },
            { name: "kimi:cloud" },
            { name: "mistral", details: {} },
            { name: "mistral" },
            { name: "" }, { size: 3 }, null
        ] }))
        T.eq(listed.models.map(entry => entry.name), ["llama3.2:latest", "mistral", "qwen2.5:7b"],
             "local models by name, once each; the cloud ones and nameless entries left out")
        T.eq(listed.models.map(entry => entry.label), ["llama3.2 · 3.2B", "mistral", "qwen2.5:7b · 7.6B"], "labels")
        T.eq(listed.skipped, 3, "three cloud models skipped")
        T.eq([A.parseModels(""), A.parseModels("<html>"), A.parseModels("{}"), A.parseModels("[]"), A.parseModels(undefined)],
             [null, null, null, null, null], "not Ollama's answer")
        T.eq(A.parseModels('{"models":[]}'), { models: [], skipped: 0 }, "no model yet")
        T.eq([A.isRemote({ name: "a", remote_model: "b" }), A.isRemote({ name: "llama3:8b" }), A.isRemote({ name: "cloudy:7b" }),
              A.isRemote(null)], [true, false, false, true], "remote by its fields or a cloud tag")
        const models = [{ name: "a:1" }, { name: "b:2" }]
        T.eq([A.chooseModel("b:2", models), A.chooseModel("gone", models), A.chooseModel("", models), A.chooseModel("x", []),
              A.chooseModel(undefined, null)], ["b:2", "a:1", "a:1", "", ""], "the chosen model while there, else the first")

        // ---- what goes to the model ----------------------------------------------
        const talk = [
            { id: "m1", role: "user", content: "one" }, { id: "m2", role: "assistant", content: "two" },
            { id: "m3", role: "user", content: "three" }, { id: "m4", role: "assistant", content: "" },
            { id: "m5", role: "system", content: "sneaky" }, { id: "m6", role: "user", content: "four" }
        ]
        T.eq(A.contextMessages(talk), [{ role: "user", content: "one" }, { role: "assistant", content: "two" },
                                       { role: "user", content: "three" }, { role: "user", content: "four" }],
             "the conversation as roles and texts; an empty reply and other roles left out")
        T.eq(A.contextMessages(talk, 3), [{ role: "user", content: "three" }, { role: "user", content: "four" }],
             "the newest within the count, starting with a question")
        T.eq(A.contextMessages(talk, 10, 9), [{ role: "user", content: "three" }, { role: "user", content: "four" }],
             "and within the characters")
        T.eq(A.contextMessages([{ role: "user", content: "abcdef" }], 10, 4), [{ role: "user", content: "cdef" }],
             "the newest question always goes, cut to the budget")
        T.eq(A.contextMessages([]), [], "nothing to send")
        T.eq(JSON.parse(A.requestBody("llama3.2", talk.slice(0, 1))),
             { model: "llama3.2", messages: [{ role: "user", content: "one" }], stream: true }, "the request body, streamed")

        // ---- the stream ----------------------------------------------------------
        T.eq(A.parseChunk('{"model":"m","message":{"role":"assistant","content":"Hel"},"done":false}'),
             { content: "Hel", thinking: false, done: false, reason: "", tokens: 0, seconds: 0 }, "a token")
        T.eq(A.parseChunk('{"message":{"role":"assistant","content":"","thinking":"hmm"},"done":false}').thinking, true,
             "a thinking model's step")
        T.eq(A.parseChunk('{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","eval_count":42,"eval_duration":2000000000}'),
             { content: "", thinking: false, done: true, reason: "stop", tokens: 42, seconds: 2 }, "the last line")
        T.eq([A.parseChunk('{"error":"model \\"x\\" not found, try pulling it first"}').error,
              A.parseChunk("not json").error, A.parseChunk("[1]").error, A.parseChunk('{"error":""}').error],
             ['model "x" not found, try pulling it first', "unreadable", "unreadable", "unreadable"], "errors")
        T.eq([A.parseChunk(""), A.parseChunk("  "), A.parseChunk(undefined)], [null, null, null], "empty lines are nothing")
        T.eq(A.appended("ab", "cd"), "abcd", "the reply grows")
        T.eq(A.appended("x".repeat(A.MESSAGE_CHARS), "y").length, A.MESSAGE_CHARS, "up to the cap")

        // ---- failures in words ---------------------------------------------------
        T.eq([0, 7, 28, 52, 56, 18, 6].map(A.curlFailure), ["", "offline", "timeout", "dropped", "dropped", "dropped", "failed"],
             "curl's exit codes")
        T.eq(['model "x" not found, try pulling it first', "model requires more system memory (12 GiB) than is available",
              "unreadable", "boom"].map(A.ollamaFailure), ["missingModel", "memory", "unreadable", "ollama"], "Ollama's errors")
        T.eq(A.failureText("missingModel", "llama3.2:latest"), "llama3.2 is not in Ollama any more.", "a missing model by name")
        T.eq(["offline", "timeout", "dropped", "memory", "unreadable", "ollama", "failed"].every(kind => A.failureText(kind).length > 0),
             true, "every kind has words")
        T.eq(A.failureText(""), "", "no failure, no words")
        T.eq(A.stateText("offline", false, "Install with: sudo pacman -S ollama", 0, "sudo pacman -S ollama").steps,
             ["sudo pacman -S ollama", "sudo systemctl enable --now ollama", "ollama pull llama3.2"],
             "not installed: three commands to copy, the distribution's first")
        T.eq(A.stateText("offline", false, "Install ollama with your package manager.", 0, "").description.indexOf("Install ollama with your package manager, then start it") >= 0,
             true, "a distribution not known: the hint in words, the other two steps as commands")
        T.eq(A.stateText("offline", false, "Install ollama with your package manager.", 0, "").steps.length, 2, "and no install command")
        T.eq([A.stateText("offline", true).title, A.stateText("offline", true).steps], ["Ollama is not running", ["sudo systemctl enable --now ollama"]],
             "installed but not running: the command that starts it")
        T.eq(A.stateText("noModels", true, "", 2).description.indexOf("Cloud models are not offered") === 0, true,
             "no local model while cloud ones were skipped says why")
        T.eq(A.stateText("noModels", true, "", 0).steps, ["ollama pull llama3.2"], "and the pull to copy")
        T.eq(A.stateText("refused").description.indexOf("this computer only") >= 0, true, "another machine refused")
        T.eq(A.stateText("ready"), { title: "", description: "", steps: [] }, "nothing to say while ready")
        T.ok(["refused", "offline", "noModels", "checking"].every(state => !/[:.]$/.test(A.stateText(state, false, "", 0, "x").description)),
             "no description ends with a colon or a full stop")

        // ---- the reply's pieces --------------------------------------------------
        T.eq(A.segments("Hello\n\n```python\nprint(1)\n```\nDone"), [
            { kind: "text", text: "Hello", lang: "", open: false },
            { kind: "code", text: "print(1)", lang: "python", open: false },
            { kind: "text", text: "Done", lang: "", open: false }
        ], "text, code with its language, text")
        T.eq(A.segments("Look:\n```\na\n  b"), [
            { kind: "text", text: "Look:", lang: "", open: false },
            { kind: "code", text: "a\n  b", lang: "", open: true }
        ], "a fence still open while the reply is written is code to its end")
        T.eq(A.segments(""), [], "nothing")
        T.eq(A.segments("```\n```"), [{ kind: "code", text: "", lang: "", open: false }], "an empty block stays a block")
        T.eq(A.segmentKeys(A.segments("a\n```\nb\n```\nc")), ["0:text", "1:code", "2:text"], "keys by place and kind")
        T.eq(A.segmentKeys(A.segments("a\n```\nb")), A.segmentKeys(A.segments("a\n```\nb plus more")),
             "a growing piece keeps its key")

        // ---- the history file ----------------------------------------------------
        const saved = A.historyText([
            { id: "m1", role: "user", content: "hi" },
            { id: "m2", role: "assistant", content: "hello", model: "llama3.2", stopped: true },
            { id: "m3", role: "system", content: "x" }
        ])
        T.eq(JSON.parse(saved), { version: 1, messages: [{ role: "user", content: "hi" },
                                                         { role: "assistant", content: "hello", model: "llama3.2", stopped: true }] },
             "roles, texts and the model; nothing else")
        T.eq(saved.charAt(saved.length - 1), "\n", "a file ends in a newline")
        T.eq(A.parseHistory(saved, 5), [
            { id: "m5", role: "user", content: "hi", model: "", stopped: false },
            { id: "m6", role: "assistant", content: "hello", model: "llama3.2", stopped: true }
        ], "back, numbered from the next id")
        T.eq([A.parseHistory(""), A.parseHistory("{}"), A.parseHistory('{"version":2,"messages":[]}'), A.parseHistory("[")],
             [[], [], [], []], "a file that is not one is no conversation")
        const many = []
        for (let i = 0; i < A.HISTORY_MESSAGES + 5; i += 1) many.push({ role: "user", content: String(i) })
        T.eq(JSON.parse(A.historyText(many)).messages.length, A.HISTORY_MESSAGES, "the newest only")
        T.eq(JSON.parse(A.historyText(many)).messages[0].content, "5", "the oldest go first")
        T.eq(A.nextIdAfter([{ id: "m3" }, { id: "m12" }, { id: "x" }]), 13, "after the highest id")
        T.eq(A.nextIdAfter([]), 1, "from one")

        T.finish("AssistantTest")
    }
}
