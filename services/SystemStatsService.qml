pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "system/SystemLogic.js" as Logic
import "system/ProcessLogic.js" as ProcessLogic

// CPU, memory and disk usage for the stat widgets and the system popup.
// Samples every two seconds only while something tracks it; the busiest
// processes (read from /proc, ProcessLogic) only while the popup is open.
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
    function trackProcesses() { processTrackers += 1; readProcesses() }
    // The next open measures afresh, not against a read from minutes ago.
    function untrackProcesses() {
        processTrackers = Math.max(0, processTrackers - 1)
        if (!processTrackers) { lastProcesses = null; processSoon.stop() }
    }
    function readProcesses() { if (!procProc.running) procProc.running = true }

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

    // The busiest processes: each one's CPU time since the read before
    // (ProcessLogic.busiest). The first read of an open has nothing to
    // compare with, so the second follows half a second later - top's own
    // delay - and then one every three seconds.
    property var lastProcesses: null
    Process {
        id: procProc
        stderr: ErrorLog { label: "SystemStatsService.procProc" }
        // Its own pid first, to leave the reader out of the list, and the
        // page size the resident sizes are counted in. A process that ends
        // between the glob and the read is a "No such file" for cat to keep.
        command: ["sh", "-c", "echo $$ $(getconf PAGESIZE); exec cat /proc/stat /proc/[0-9]*/stat 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.processTrackers) return
                const current = ProcessLogic.snapshot(text)
                const list = ProcessLogic.busiest(root.lastProcesses, current, root.memory ? root.memory.total : 0, 5)
                root.lastProcesses = current
                if (list) root.processes = list
                else processSoon.start()
            }
        }
    }
    Timer { id: processSoon; interval: 500; onTriggered: root.readProcesses() }

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
        onTriggered: root.readProcesses()
    }
}
