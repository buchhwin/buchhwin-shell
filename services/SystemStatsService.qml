pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "system/SystemLogic.js" as Logic

// CPU, memory and disk usage for the stat widgets and the system popup.
// Samples every two seconds only while something tracks it; the busiest
// processes (`top`, two iterations) only while the popup is open.
Singleton {
    id: root
    property int trackers: 0
    property int processTrackers: 0
    property real cpu: 0
    property var memory: null        // { total, used, usage } KiB
    property var disk: null          // { total, used, usage } bytes
    property var load: []
    property var processes: []       // [{ pid, name, cpu, memory }]
    property var lastCpu: null

    readonly property real ram: memory ? memory.usage : 0
    readonly property real diskUsage: disk ? disk.usage : 0

    // First installed graphical system monitor.
    readonly property var monitorApp: ["org.kde.plasma-systemmonitor", "gnome-system-monitor", "org.gnome.SystemMonitor",
                                       "io.missioncenter.MissionCenter", "net.nokyan.Resources"]
        .map(id => DesktopEntries.byId(id)).find(entry => entry) || null

    function track() { trackers += 1; sample(true) }
    function untrack() { trackers = Math.max(0, trackers - 1) }
    function trackProcesses() { processTrackers += 1; if (!topProc.running) topProc.running = true }
    function untrackProcesses() { processTrackers = Math.max(0, processTrackers - 1) }

    function usage(metric) { return metric === "ram" ? ram : metric === "disk" ? diskUsage : cpu }
    function formatBytes(bytes) { return Logic.formatBytes(bytes) }
    function percent(ratio) { return Logic.percent(ratio) }

    function openMonitor() {
        if (!monitorApp) return
        LauncherService.launchApp(monitorApp)
        PanelService.close()
    }

    // Disk usage changes slowly: every 30 s (and when a new tracker starts).
    property int diskTick: 0
    // Each file is read again and its figure worked out when that read
    // finishes, in the view's own `loaded` handler. `reload()` is
    // asynchronous - with `blockLoading` too, measured - so a `text()` right
    // after it is the previous sample: every meter was one tick behind, and
    // the first CPU reading compared the boot-time text with itself.
    function sample(withDisk) {
        statFile.reload()
        memFile.reload()
        loadFile.reload()
        diskTick = (diskTick + 1) % 15
        if ((withDisk || diskTick === 0) && !diskProc.running) diskProc.running = true
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const times = Logic.cpuTimes(text())
            const busy = Logic.cpuUsage(root.lastCpu, times)
            if (busy >= 0) root.cpu = busy
            if (times) root.lastCpu = times
        }
    }
    FileView { id: memFile; path: "/proc/meminfo"; printErrors: false; onLoaded: root.memory = Logic.memory(text()) }
    FileView { id: loadFile; path: "/proc/loadavg"; printErrors: false; onLoaded: root.load = Logic.loadAverage(text()) }

    Process {
        id: diskProc
        stderr: ErrorLog { label: "SystemStatsService.diskProc" }
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector { onStreamFinished: root.disk = Logic.disk(text) }
    }

    Process {
        id: topProc
        stderr: ErrorLog { label: "SystemStatsService.topProc" }
        command: ["top", "-b", "-n", "2", "-d", "0.5", "-o", "%CPU", "-w", "512"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root.processes = Logic.topProcesses(text, 5) }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.trackers > 0
        onTriggered: root.sample()
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.processTrackers > 0
        onTriggered: if (!topProc.running) topProc.running = true
    }
}
