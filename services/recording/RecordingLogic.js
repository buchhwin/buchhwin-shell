.pragma library

// Screen recording: chooses the recorder, builds its command line, names the
// output file, parses the state file of scripts/record.sh and formats the
// elapsed time. record.sh only collects runtime facts (`probe`: installed
// recorders, selected region, focused output, default audio devices) and
// runs the command built here in a detached supervisor. Unit tested
// (tests/qml/RecordingTest.qml).

var MODES = ["region", "screen", "window"]
var AUDIO_MODES = ["off", "desktop", "desktop+mic"]
var FPS_CHOICES = [30, 60]
var GSR_FLATPAK = "com.dec05eba.gpu_screen_recorder"
var INSTALL_HINT = "sudo dnf install wf-recorder"

function validMode(mode) {
    return MODES.indexOf(mode) >= 0
}

function validAudio(audio) {
    return AUDIO_MODES.indexOf(audio) >= 0 ? audio : "off"
}

function validFps(fps) {
    const value = Number(fps)
    return FPS_CHOICES.indexOf(value) >= 0 ? value : 30
}

// Preferred order: wf-recorder, gpu-screen-recorder, its Flatpak.
function chooseBackend(backends) {
    const found = backends && typeof backends === "object" ? backends : {}
    if (found.wfRecorder === true) return "wf-recorder"
    if (found.gsr === true) return "gpu-screen-recorder"
    if (found.gsrFlatpak === true) return "gpu-screen-recorder-flatpak"
    return ""
}

function backendLabel(backend) {
    return backend === "gpu-screen-recorder-flatpak" ? "gpu-screen-recorder (Flatpak)" : backend
}

function pad(value) {
    return (value < 10 ? "0" : "") + value
}

// Recording_YYYY-MM-DD_HH-MM-SS.mp4 in local time.
function fileName(date) {
    return "Recording_" + date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
        + "_" + pad(date.getHours()) + "-" + pad(date.getMinutes()) + "-" + pad(date.getSeconds()) + ".mp4"
}

// Absolute folder from the setting ("~/…" expanded, empty → default).
function folderPath(setting, home) {
    let folder = String(setting || "").trim()
    if (!folder.length) folder = "~/Videos/Recordings"
    if (folder === "~") folder = home
    else if (folder.indexOf("~/") === 0) folder = home + folder.slice(1)
    if (folder.charAt(0) !== "/") folder = home + "/" + folder
    return folder.length > 1 ? folder.replace(/\/+$/, "") : folder
}

function outputFile(setting, home, date) {
    return folderPath(setting, home) + "/" + fileName(date)
}

// "X,Y WxH" (slurp, record.sh probe) → { x, y, w, h }, null when invalid or empty.
function parseGeometry(text) {
    const match = /^\s*(-?\d+),(-?\d+) (\d+)x(\d+)\s*$/.exec(String(text || ""))
    if (!match) return null
    const geometry = { x: parseInt(match[1]), y: parseInt(match[2]), w: parseInt(match[3]), h: parseInt(match[4]) }
    return geometry.w > 0 && geometry.h > 0 ? geometry : null
}

// Encoders need even sizes; the region shrinks by at most one pixel.
function evenGeometry(geometry) {
    return { x: geometry.x, y: geometry.y, w: Math.max(2, geometry.w - geometry.w % 2), h: Math.max(2, geometry.h - geometry.h % 2) }
}

// Output of `record.sh probe MODE` → normalized object.
function parseProbe(text) {
    let data = null
    try { data = JSON.parse(String(text || "").trim()) } catch (error) { data = null }
    if (!data || typeof data !== "object" || Array.isArray(data)) data = {}
    const backends = data.backends && typeof data.backends === "object" ? data.backends : {}
    const string = value => typeof value === "string" ? value : ""
    return {
        valid: Object.keys(data).length > 0,
        backends: { wfRecorder: backends.wfRecorder === true, gsr: backends.gsr === true, gsrFlatpak: backends.gsrFlatpak === true },
        cancelled: data.cancelled === true,
        geometry: parseGeometry(data.geometry),
        output: string(data.output),
        sink: string(data.sink),
        source: string(data.source)
    }
}

// { argv, warnings, error } for one recording.
//   target: { mode, geometry, output } (geometry for region/window)
//   options: { fps, audio, sink, source, file }
function recorderCommand(backend, target, options) {
    const warnings = []
    const mode = target ? target.mode : ""
    if (!validMode(mode)) return { argv: [], warnings: warnings, error: "Unknown recording mode" }
    const needsGeometry = mode !== "screen"
    if (needsGeometry && !target.geometry) return { argv: [], warnings: warnings, error: mode === "window" ? "No active window" : "No region selected" }
    if (!needsGeometry && !target.output) return { argv: [], warnings: warnings, error: "No focused display" }
    const file = String(options.file || "")
    if (!file.length) return { argv: [], warnings: warnings, error: "No output file" }
    const fps = String(validFps(options.fps))
    const audio = validAudio(options.audio)
    const geometry = needsGeometry ? evenGeometry(target.geometry) : null

    if (backend === "wf-recorder") {
        const argv = ["wf-recorder", "-y", "-f", file, "-r", fps]
        if (geometry) argv.push("-g", geometry.x + "," + geometry.y + " " + geometry.w + "x" + geometry.h)
        else argv.push("-o", target.output)
        if (audio !== "off") {
            // wf-recorder takes one PulseAudio source: the monitor of the default sink.
            if (options.sink) argv.push("--audio=" + options.sink + ".monitor")
            else warnings.push("No default audio output found, recording without sound")
            if (audio === "desktop+mic") warnings.push("wf-recorder records one audio source: desktop sound only")
        }
        return { argv: argv, warnings: warnings, error: "" }
    }

    if (backend === "gpu-screen-recorder" || backend === "gpu-screen-recorder-flatpak") {
        const argv = backend === "gpu-screen-recorder" ? ["gpu-screen-recorder"]
            : ["flatpak", "run", "--command=gpu-screen-recorder", GSR_FLATPAK]
        if (geometry) argv.push("-w", "region", "-region", geometry.w + "x" + geometry.h + "+" + geometry.x + "+" + geometry.y)
        else argv.push("-w", target.output)
        argv.push("-f", fps, "-c", "mp4")
        if (audio === "desktop") argv.push("-a", "default_output")
        else if (audio === "desktop+mic") argv.push("-a", "default_output|default_input")
        argv.push("-o", file)
        return { argv: argv, warnings: warnings, error: "" }
    }

    return { argv: [], warnings: warnings, error: "Screen recording needs wf-recorder" }
}

// record.sh start … -- ARGV
function startCommand(script, statePath, recording) {
    const command = [script, "--state", statePath, "start", "--file", recording.file, "--mode", recording.mode,
                     "--backend", recording.backend, "--audio", validAudio(recording.audio)]
    if (recording.notify) command.push("--notify")
    return command.concat(["--"], recording.argv)
}

// State file of record.sh → { active, pid, supervisor, file, mode, backend, audio, started }.
function parseState(text) {
    const idle = { active: false, pid: 0, supervisor: 0, file: "", mode: "", backend: "", audio: "off", started: 0 }
    let data = null
    try { data = JSON.parse(String(text || "").trim()) } catch (error) { return idle }
    if (!data || typeof data !== "object" || data.active !== true) return idle
    const pid = Number(data.pid)
    const started = Number(data.started)
    if (!(pid > 0) || !(started > 0) || typeof data.file !== "string" || !data.file.length) return idle
    return {
        active: true, pid: pid, supervisor: Number(data.supervisor) > 0 ? Number(data.supervisor) : 0,
        file: data.file, mode: validMode(data.mode) ? data.mode : "screen",
        backend: typeof data.backend === "string" ? data.backend : "", audio: validAudio(data.audio), started: started
    }
}

// Milliseconds → "0:05", "12:34", "1:02:03".
function elapsedText(ms) {
    const total = Math.max(0, Math.floor((Number(ms) || 0) / 1000))
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor(total / 60) % 60
    const seconds = total % 60
    return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(seconds) : minutes + ":" + pad(seconds)
}

function baseName(path) {
    const text = String(path || "")
    return text.slice(text.lastIndexOf("/") + 1)
}

// Last lines of `record.sh stop`: "saved PATH" or "failed MESSAGE".
function parseStopResult(text) {
    const lines = String(text || "").trim().split("\n").filter(line => line.length)
    const last = lines.length ? lines[lines.length - 1] : ""
    if (last.indexOf("saved ") === 0) return { ok: true, file: last.slice(6), message: "" }
    if (last.indexOf("failed ") === 0) return { ok: false, file: "", message: last.slice(7) }
    return { ok: false, file: "", message: last }
}

function missingNotification() {
    return { title: "Screen recording needs wf-recorder", body: "Install with: " + INSTALL_HINT }
}
