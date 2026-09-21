pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "recording/RecordingLogic.js" as Logic

// Screen recording (Super+Shift+R region, Super+Ctrl+Shift+R screen, launcher,
// IPC `recording`). scripts/record.sh probes the installed recorder
// (wf-recorder, gpu-screen-recorder or its Flatpak), the selection and audio
// devices; the command is built in recording/RecordingLogic.js and runs in a
// detached supervisor that survives shell restarts. The state lives in
// $XDG_RUNTIME_DIR/buchhwin-shell/recording.json (recording-nested.json in
// nested test sessions, so they never show the real session's recording).
// Notifications only go out in the real session; nested sessions log them.
Singleton {
    id: root

    readonly property bool realSession: AppearanceService.realSession
    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/buchhwin-shell/"
        + (Quickshell.env("BUCHHWIN_NESTED") === "1" ? "recording-nested.json" : "recording.json")
    readonly property string audio: SettingsService.value("recording.audio")
    readonly property int fps: SettingsService.value("recording.fps")
    readonly property string folder: Logic.folderPath(SettingsService.value("recording.folder"), Paths.home)

    property var state: Logic.parseState("")
    // Synthetic recording for screenshots (IPC `recording preview`).
    property bool preview: false
    property real previewStarted: 0
    property var backends: ({ wfRecorder: false, gsr: false, gsrFlatpak: false })
    property bool backendsKnown: false
    readonly property string backend: Logic.chooseBackend(backends)
    readonly property bool available: backend.length > 0
    readonly property string backendLabel: Logic.backendLabel(backend)
    // "probing" (selection), "starting", "stopping" or "".
    property string busy: ""
    property string lastError: ""
    property string lastFile: ""
    readonly property string lastFileName: Logic.baseName(lastFile)
    property real now: Date.now()

    readonly property bool active: preview || state.active
    readonly property real started: preview ? previewStarted : state.started
    readonly property string elapsedText: active ? Logic.elapsedText(now - started) : ""
    readonly property string mode: preview ? "region" : state.mode

    function toggle(mode) {
        if (active) stop()
        else start(mode)
    }

    function start(mode) {
        if (!Logic.validMode(mode) || active || busy.length || probeProc.running) return false
        lastError = ""
        busy = "probing"
        probeProc.mode = mode
        probeProc.command = [Paths.script("record.sh"), "probe", mode]
        probeProc.running = true
        return true
    }

    // From the launcher: let the panel close before the region is selected.
    function startSoon(mode) {
        startDelay.mode = mode
        startDelay.restart()
    }

    function stop() {
        if (preview) {
            stopPreview()
            return true
        }
        if (!state.active || busy === "stopping") return false
        busy = "stopping"
        stopProc.command = [Paths.script("record.sh"), "--state", statePath, "stop"]
        stopProc.running = true
        return true
    }

    function probeFinished(text) {
        const probe = Logic.parseProbe(text)
        backends = probe.backends
        backendsKnown = probe.valid
        const mode = probeProc.mode
        if (mode === "none") return
        busy = ""
        const backend = Logic.chooseBackend(probe.backends)
        if (!probe.valid) return fail("Could not check for a screen recorder")
        if (!backend.length) return missing()
        if (probe.cancelled) return
        const file = Logic.outputFile(SettingsService.value("recording.folder"), Paths.home, new Date())
        const built = Logic.recorderCommand(backend, { mode: mode, geometry: probe.geometry, output: probe.output },
                                            { fps: fps, audio: audio, sink: probe.sink, source: probe.source, file: file })
        if (built.error.length) return fail(built.error)
        for (const warning of built.warnings) console.info("buchhwin-shell: recording:", warning)
        busy = "starting"
        startProc.command = Logic.startCommand(Paths.script("record.sh"), statePath,
            { file: file, mode: mode, backend: backend, audio: audio, notify: realSession, argv: built.argv })
        startProc.running = true
    }

    function startFinished(text) {
        busy = ""
        const next = Logic.parseState(text)
        if (next.active) {
            state = next
            now = Date.now()
        } else {
            fail(Logic.parseStopResult(text).message || "The recorder did not start")
        }
    }

    function stopFinished(text) {
        busy = ""
        const result = Logic.parseStopResult(text)
        if (result.ok) lastFile = result.file
        else lastError = result.message
        stateFile.reload()
    }

    function fail(message) {
        busy = ""
        lastError = message
        console.warn("buchhwin-shell: recording:", message)
        return false
    }

    function missing() {
        const text = Logic.missingNotification()
        lastError = text.title
        if (realSession) {
            Quickshell.execDetached(["notify-send", "--app-name=Screen recording", "--icon=media-record", "--",
                                     text.title, text.body])
        } else {
            console.info("buchhwin-shell: recording: notification (nested, not sent):", text.title, "—", text.body)
        }
        return false
    }

    function showPreview() {
        previewStarted = Date.now() - 83000
        now = Date.now()
        preview = true
    }

    function stopPreview() {
        preview = false
    }

    // Recorders installed later are found without a restart.
    function refreshBackends() {
        if (probeProc.running) return
        probeProc.mode = "none"
        probeProc.command = [Paths.script("record.sh"), "probe", "none"]
        probeProc.running = true
    }

    Process {
        id: probeProc
        stderr: ErrorLog { label: "RecordingService.probeProc" }
        property string mode: "none"
        stdout: StdioCollector { onStreamFinished: root.probeFinished(text) }
    }

    Process {
        id: startProc
        stderr: ErrorLog { label: "RecordingService.startProc" }
        stdout: StdioCollector { onStreamFinished: root.startFinished(text) }
    }

    Process {
        id: stopProc
        stderr: ErrorLog { label: "RecordingService.stopProc" }
        stdout: StdioCollector { onStreamFinished: root.stopFinished(text) }
    }

    // Clears a state file left behind by a crashed supervisor, then loads it.
    Process {
        id: statusProc
        stderr: ErrorLog { label: "RecordingService.statusProc" }
        command: [Paths.script("record.sh"), "--state", root.statePath, "status"]
        stdout: StdioCollector { onStreamFinished: root.state = Logic.parseState(text) }
    }

    Component.onCompleted: {
        statusProc.running = true
        refreshBackends()
    }

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: root.state = Logic.parseState(text())
        onLoadFailed: root.state = Logic.parseState("")
    }

    Timer {
        id: startDelay
        property string mode: "region"
        interval: 350
        onTriggered: root.start(mode)
    }

    // Elapsed time; the supervisor removes the state file when the recorder
    // exits, which the periodic reload notices.
    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            root.now = Date.now()
            if (!root.preview && !stopProc.running) stateFile.reload()
        }
    }
}
