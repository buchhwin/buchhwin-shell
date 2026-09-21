import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/recording/RecordingLogic.js" as R

ShellRoot {
    Component.onCompleted: {
        // Backend choice and validation.
        T.eq(R.chooseBackend({ wfRecorder: true, gsr: true, gsrFlatpak: true }), "wf-recorder", "wf-recorder first")
        T.eq(R.chooseBackend({ wfRecorder: false, gsr: true, gsrFlatpak: true }), "gpu-screen-recorder", "native gpu-screen-recorder next")
        T.eq(R.chooseBackend({ gsrFlatpak: true }), "gpu-screen-recorder-flatpak", "Flatpak last")
        T.eq([R.chooseBackend({}), R.chooseBackend(null), R.chooseBackend({ wfRecorder: "yes" })], ["", "", ""], "nothing installed")
        T.eq([R.validMode("region"), R.validMode("window"), R.validMode("all")], [true, true, false], "modes")
        T.eq([R.validAudio("desktop+mic"), R.validAudio("mic"), R.validFps(60), R.validFps("60"), R.validFps(144)],
             ["desktop+mic", "off", 60, 60, 30], "audio and fps fall back")

        // File names and folders.
        T.eq(R.fileName(new Date(2026, 8, 7, 9, 5, 3)), "Recording_2026-09-07_09-05-03.mp4", "file name in local time")
        T.eq(R.folderPath("", "/home/u"), "/home/u/Videos/Recordings", "default folder")
        T.eq(R.folderPath("~/Clips/", "/home/u"), "/home/u/Clips", "home expanded, trailing slash dropped")
        T.eq([R.folderPath("/data/rec", "/home/u"), R.folderPath("Movies", "/home/u"), R.folderPath("~", "/home/u")],
             ["/data/rec", "/home/u/Movies", "/home/u"], "absolute, relative and home folders")
        T.eq(R.outputFile("~/Videos/Recordings", "/home/u", new Date(2026, 0, 31, 23, 59, 58)),
             "/home/u/Videos/Recordings/Recording_2026-01-31_23-59-58.mp4", "output file")

        // Geometry and probe output.
        T.eq(R.parseGeometry("10,20 300x200"), { x: 10, y: 20, w: 300, h: 200 }, "slurp geometry")
        T.eq(R.parseGeometry("-1920,0 1920x1080"), { x: -1920, y: 0, w: 1920, h: 1080 }, "negative position")
        T.eq([R.parseGeometry(""), R.parseGeometry("10,20 0x5"), R.parseGeometry("selection cancelled")], [null, null, null], "invalid geometry")
        const probe = R.parseProbe('{"backends":{"wfRecorder":true,"gsr":false,"gsrFlatpak":false},"cancelled":false,'
            + '"geometry":"5,6 101x51","output":"","sink":"alsa_output.pci","source":"alsa_input.pci"}')
        T.eq([probe.valid, R.chooseBackend(probe.backends), probe.geometry, probe.sink, probe.cancelled],
             [true, "wf-recorder", { x: 5, y: 6, w: 101, h: 51 }, "alsa_output.pci", false], "probe parsed")
        T.eq([R.parseProbe("").valid, R.parseProbe("not json").valid, R.parseProbe("[]").valid], [false, false, false], "broken probe")
        T.eq(R.parseProbe('{"backends":{},"cancelled":true}').cancelled, true, "cancelled selection")

        // wf-recorder.
        const file = "/home/u/Videos/Recordings/Recording_x.mp4"
        const region = { mode: "region", geometry: { x: 5, y: 6, w: 101, h: 51 }, output: "" }
        const screen = { mode: "screen", geometry: null, output: "eDP-1" }
        let built = R.recorderCommand("wf-recorder", region, { fps: 60, audio: "off", sink: "s", file: file })
        T.eq(built, { argv: ["wf-recorder", "-y", "-f", file, "-r", "60", "-g", "5,6 100x50"], warnings: [], error: "" },
             "wf-recorder region with even size")
        built = R.recorderCommand("wf-recorder", screen, { fps: 30, audio: "desktop", sink: "alsa_output.pci", file: file })
        T.eq(built.argv, ["wf-recorder", "-y", "-f", file, "-r", "30", "-o", "eDP-1", "--audio=alsa_output.pci.monitor"],
             "wf-recorder screen with desktop audio")
        built = R.recorderCommand("wf-recorder", screen, { fps: 30, audio: "desktop+mic", sink: "out", source: "in", file: file })
        T.eq([built.argv[built.argv.length - 1], built.warnings.length], ["--audio=out.monitor", 1], "wf-recorder takes one audio source")
        built = R.recorderCommand("wf-recorder", screen, { fps: 30, audio: "desktop", sink: "", file: file })
        T.eq([built.argv.some(arg => arg.indexOf("--audio") === 0), built.warnings.length], [false, 1], "no sink, no audio")

        // gpu-screen-recorder.
        built = R.recorderCommand("gpu-screen-recorder", region, { fps: 60, audio: "desktop", file: file })
        T.eq(built.argv, ["gpu-screen-recorder", "-w", "region", "-region", "100x50+5+6", "-f", "60", "-c", "mp4",
                          "-a", "default_output", "-o", file], "gpu-screen-recorder region")
        built = R.recorderCommand("gpu-screen-recorder-flatpak", screen, { fps: 30, audio: "desktop+mic", file: file })
        T.eq(built.argv, ["flatpak", "run", "--command=gpu-screen-recorder", "com.dec05eba.gpu_screen_recorder",
                          "-w", "eDP-1", "-f", "30", "-c", "mp4", "-a", "default_output|default_input", "-o", file],
             "Flatpak screen with desktop and microphone")
        built = R.recorderCommand("gpu-screen-recorder", { mode: "window", geometry: { x: 0, y: 40, w: 800, h: 600 } },
                                  { fps: 30, audio: "off", file: file })
        T.eq(built.argv.slice(1, 5), ["-w", "region", "-region", "800x600+0+40"], "window as its region")

        // Errors.
        T.eq(R.recorderCommand("", screen, { file: file }).error, "Screen recording needs wf-recorder", "no backend")
        T.eq(R.recorderCommand("wf-recorder", { mode: "region", geometry: null }, { file: file }).error, "No region selected", "no region")
        T.eq(R.recorderCommand("wf-recorder", { mode: "window", geometry: null }, { file: file }).error, "No active window", "no window")
        T.eq(R.recorderCommand("wf-recorder", { mode: "screen", output: "" }, { file: file }).error, "No focused display", "no output")
        T.eq(R.recorderCommand("wf-recorder", { mode: "everything" }, { file: file }).argv, [], "unknown mode")
        T.eq(R.recorderCommand("wf-recorder", screen, { file: "" }).error, "No output file", "no file")

        // record.sh start command.
        T.eq(R.startCommand("/p/record.sh", "/run/r.json", { file: file, mode: "screen", backend: "wf-recorder",
                                                             audio: "bogus", notify: true, argv: ["wf-recorder", "-o", "X"] }),
             ["/p/record.sh", "--state", "/run/r.json", "start", "--file", file, "--mode", "screen", "--backend", "wf-recorder",
              "--audio", "off", "--notify", "--", "wf-recorder", "-o", "X"], "start command")
        T.eq(R.startCommand("/p/record.sh", "/s", { file: "f", mode: "region", backend: "b", audio: "desktop", notify: false, argv: ["a"] }).indexOf("--notify"),
             -1, "nested sessions do not notify")

        // State file.
        const state = R.parseState('{"active":true,"pid":42,"supervisor":41,"file":"/v/r.mp4","mode":"window",'
            + '"backend":"wf-recorder","audio":"desktop","started":1789000000000}')
        T.eq(state, { active: true, pid: 42, supervisor: 41, file: "/v/r.mp4", mode: "window", backend: "wf-recorder",
                      audio: "desktop", started: 1789000000000 }, "state parsed")
        T.eq([R.parseState("").active, R.parseState('{"active":false}').active, R.parseState("{broken").active,
              R.parseState('{"active":true,"pid":0,"file":"/x","started":1}').active,
              R.parseState('{"active":true,"pid":3,"file":"","started":1}').active], [false, false, false, false, false], "idle and invalid states")
        T.eq(R.parseState('{"active":true,"pid":3,"file":"/x","started":5,"mode":"odd","audio":7}').mode, "screen", "unknown mode shown as screen")

        // Elapsed time and results.
        T.eq([R.elapsedText(0), R.elapsedText(5999), R.elapsedText(754000), R.elapsedText(3723000), R.elapsedText(-5), R.elapsedText("x")],
             ["0:00", "0:05", "12:34", "1:02:03", "0:00", "0:00"], "elapsed text")
        T.eq(R.parseStopResult("saved /v/Recording_1.mp4\n"), { ok: true, file: "/v/Recording_1.mp4", message: "" }, "saved")
        T.eq(R.parseStopResult("failed No recording is running\n"), { ok: false, file: "", message: "No recording is running" }, "failed")
        T.eq(R.baseName("/v/Recording_1.mp4"), "Recording_1.mp4", "base name")
        T.eq(R.missingNotification(), { title: "Screen recording needs wf-recorder", body: "Install with: sudo dnf install wf-recorder" },
             "install hint")
        T.finish("RecordingTest")
    }
}
