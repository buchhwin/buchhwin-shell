import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/system/SystemLogic.js" as S
import "../../services/media/MediaLogic.js" as M

ShellRoot {
    Component.onCompleted: {
        // CPU
        const first = S.cpuTimes("cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 2 3 4")
        T.eq(first, { idle: 850, total: 1000 }, "idle includes iowait")
        const second = S.cpuTimes("cpu  200 0 100 900 50 0 0 0 0 0")
        T.near(S.cpuUsage(first, second), 0.6, "busy share between samples", 1e-9)
        T.eq([S.cpuUsage(null, second), S.cpuUsage(second, second)], [-1, -1], "no usable pair")
        T.eq([S.cpuTimes(""), S.cpuTimes("intr 1 2 3")], [null, null], "unexpected /proc/stat")

        // Memory and disk
        const mem = S.memory("MemTotal:       16000000 kB\nMemFree:  1000000 kB\nMemAvailable:    4000000 kB\n")
        T.eq([mem.total, mem.used], [16000000, 12000000], "used = total - available")
        T.near(mem.usage, 0.75, "memory usage", 1e-9)
        T.eq(S.memory("MemTotal: 1000 kB\nMemFree: 250 kB").used, 750, "old kernels without MemAvailable")
        T.eq(S.memory("nothing"), null, "no MemTotal")
        const root = S.disk("    1B-Size     1B-Used\n500000000000 125000000000\n")
        T.eq([root.total, root.used, root.usage], [500000000000, 125000000000, 0.25], "df bytes")
        T.eq([S.disk("header only\n"), S.disk("h\n0 0")], [null, null], "unusable df output")
        T.eq(S.loadAverage("0.60 0.97 0.90 1/619 1234"), [0.6, 0.97, 0.9], "load average")
        T.eq(S.loadAverage(""), [], "no load average")

        // top: only the second iteration counts, top itself and commands with spaces
        const top = [
            "top - 00:36:01 up  5:37,  1 user,  load average: 0.60, 0.97, 0.90",
            "",
            "    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND",
            "    11 user      20   0    7884   5316   3164 S  99.0   0.1   0:00.02 stale",
            "",
            "top - 00:36:02 up  5:37,  1 user,  load average: 0.60, 0.97, 0.90",
            "",
            "    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND",
            " 188678 user      20   0    7884   5316   3164 R  12.5   0.0   0:00.02 top",
            " 103080 user      20   0 2642056 178548  96100 S   9.5   1.3   2:36.58 Hyprland",
            " 105216 user      20   0 1448.6g 283496 200932 S   4,7   2.0   0:47.34 Web Content",
            "   2000 user      20   0    1000    100    100 S   0.0   0.1   0:00.01 idle"
        ].join("\n")
        T.eq(S.topProcesses(top, 2), [
            { pid: 103080, name: "Hyprland", cpu: 9.5, memory: 1.3 },
            { pid: 105216, name: "Web Content", cpu: 4.7, memory: 2 }
        ], "last iteration, top skipped, spaces and decimal commas")
        T.eq(S.topProcesses("garbage", 5), [], "no header")

        T.eq([S.formatBytes(0), S.formatBytes(512), S.formatBytes(7400000000), S.formatBytes(512000000000), S.formatBytes(1900000000000)],
             ["0 B", "512 B", "7.4 GB", "512 GB", "1.9 TB"], "byte formatting")
        T.eq([S.percent(0.254), S.percent(2), S.percent("x")], ["25%", "100%", "0%"], "percent")

        // Media: stream of a player and loop order
        const streams = [
            { appName: "Firefox", binary: "firefox", appId: "", pid: 900 },
            { appName: "Chromium", binary: "chromium-browser", appId: "", pid: 4242 },
            { appName: "spotify", binary: "spotify", appId: "", pid: 77 },
            { appName: "Elisa", binary: "elisa", appId: "org.kde.elisa", pid: 5 }
        ]
        T.eq(M.streamIndex({ identity: "Spotify", desktopEntry: "com.spotify.Client", dbusName: "org.mpris.MediaPlayer2.spotify" }, streams), 2, "identity match")
        T.eq(M.streamIndex({ identity: "Chrome", desktopEntry: "", dbusName: "org.mpris.MediaPlayer2.chromium.instance4242" }, streams), 1, "pid from the bus name wins")
        T.eq(M.streamIndex({ identity: "Mozilla Firefox", desktopEntry: "firefox", dbusName: "org.mpris.MediaPlayer2.firefox.instance_1_23" }, streams), 0, "desktop entry match")
        T.eq(M.streamIndex({ identity: "Music", desktopEntry: "org.kde.elisa", dbusName: "org.mpris.MediaPlayer2.elisa" }, streams), 3, "last desktop entry segment")
        T.eq(M.streamIndex({ identity: "mpv", desktopEntry: "", dbusName: "org.mpris.MediaPlayer2.mpv" }, streams), -1, "no stream")
        T.eq([M.streamIndex(null, streams), M.streamIndex({ identity: "x" }, [])], [-1, -1], "nothing to match")
        T.eq([M.nextLoopState(0), M.nextLoopState(2), M.nextLoopState(1)], [2, 1, 0], "loop order off → list → track → off")

        T.finish("SystemStatsTest")
    }
}
