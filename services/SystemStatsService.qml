pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "system/SystemLogic.js" as Logic
import "system/ProcessLogic.js" as ProcessLogic
import "system/SensorLogic.js" as Sensors

// CPU, memory and disk usage for the stat widgets and the system popup.
// Samples every two seconds only while something tracks it; the busiest
// processes (read from /proc, ProcessLogic) only while the popup is open;
// temperatures, the GPU's load and the fan (SensorLogic) only while the popup
// or a temperature widget shows them, the disk's heat and the network's speed
// only while the popup does.
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

    // One tick for all: the meters', the sensors' and the network's reads
    // land together.
    Timer {
        interval: 2000
        repeat: true
        running: root.trackers > 0 || root.sensorTrackers > 0 || root.networkTrackers > 0
        onTriggered: {
            if (root.trackers > 0) root.sample()
            if (root.sensorTrackers > 0) root.sampleSensors()
            if (root.networkTrackers > 0) netFile.reload()
        }
    }

    // ---- sensors and the network (SensorLogic) -------------------------------
    // The files are found once, as the first tracker starts (the hwmonN
    // numbers are the boot's), and from then on only the few picked are read:
    // each FileView has its path only while something tracks the sensors. The
    // network has trackers of its own - the popup; a temperature widget on the
    // bar has no use for /proc/net/dev every two seconds. So has the disk: an
    // NVMe drive's temperature is a command to the drive itself (the kernel
    // asks it for its health log on every read), and drivetemp's read can
    // keep a hard disk from spinning down - a drive asked every two seconds,
    // for as long as a widget that does not even show the disk is placed.
    property int sensorTrackers: 0
    property int networkTrackers: 0
    property int diskTrackers: 0
    property var sensorPaths: null         // { cpu, gpu, gpuBusy, disk, fan }
    property real cpuTemp: NaN             // degrees Celsius
    property real gpuTemp: NaN
    property real gpuBusy: NaN             // 0..1
    property real diskTemp: NaN
    property real fanRpm: NaN
    property var netRates: null            // { rx, tx } bytes per second
    property var lastNet: null             // { rx, tx, at }
    readonly property bool sensing: sensorTrackers > 0 && sensorPaths !== null
    readonly property bool fahrenheit: SettingsService.value("weather.unit") === "fahrenheit"

    function trackSensors() {
        sensorTrackers += 1
        if (sensorPaths === null) { if (!discoverProc.running) discoverProc.running = true }
        else sampleSensors()
    }
    function untrackSensors() { sensorTrackers = Math.max(0, sensorTrackers - 1) }
    function trackNetwork() { networkTrackers += 1 }
    function trackDisk() { diskTrackers += 1 }
    function untrackDisk() { diskTrackers = Math.max(0, diskTrackers - 1) }
    // The next open measures the network afresh, not against a read from
    // minutes ago.
    function untrackNetwork() {
        networkTrackers = Math.max(0, networkTrackers - 1)
        if (!networkTrackers) { lastNet = null; netRates = null }
    }
    function sampleSensors() {
        for (const view of [cpuTempFile, gpuTempFile, gpuBusyFile, diskTempFile, fanFile])
            if (view.path.length) view.reload()
    }
    // For `widgets sensors` over IPC: which sensors were found and what they
    // read, numbers only (NaN, nothing read, as null).
    function sensorStatus() {
        const number = value => isFinite(value) ? value : null
        const paths = sensorPaths
        return { trackers: sensorTrackers, networkTrackers: networkTrackers, diskTrackers: diskTrackers,
                 found: paths ? { cpu: paths.cpu.length > 0, gpu: paths.gpu.length > 0, gpuBusy: paths.gpuBusy.length > 0,
                                  disk: paths.disk.length > 0, fan: paths.fan.length > 0 } : null,
                 cpuTemp: number(cpuTemp), gpuTemp: number(gpuTemp), gpuBusy: number(gpuBusy),
                 diskTemp: number(diskTemp), fanRpm: number(fanRpm),
                 rx: netRates ? Math.round(netRates.rx) : null, tx: netRates ? Math.round(netRates.tx) : null }
    }
    function formatTemp(celsius) { return Sensors.formatTemp(celsius, fahrenheit) }
    function formatRate(bytesPerSecond) { return Sensors.formatRate(bytesPerSecond) }
    function tempLevel(celsius) { return Sensors.level(celsius) }

    Process {
        id: discoverProc
        stderr: ErrorLog { label: "SystemStatsService.discoverProc" }
        command: Sensors.discoveryCommand()
        stdout: StdioCollector { onStreamFinished: root.sensorPaths = Sensors.pick(Sensors.parseDiscovery(text)) }
    }

    FileView { id: cpuTempFile; path: root.sensing ? root.sensorPaths.cpu : ""; printErrors: false; onLoaded: root.cpuTemp = Sensors.celsius(text()) }
    FileView { id: gpuTempFile; path: root.sensing ? root.sensorPaths.gpu : ""; printErrors: false; onLoaded: root.gpuTemp = Sensors.celsius(text()) }
    FileView { id: gpuBusyFile; path: root.sensing ? root.sensorPaths.gpuBusy : ""; printErrors: false; onLoaded: root.gpuBusy = Sensors.busy(text()) }
    FileView { id: diskTempFile; path: root.sensing && root.diskTrackers > 0 ? root.sensorPaths.disk : ""; printErrors: false; onLoaded: root.diskTemp = Sensors.celsius(text()) }
    FileView { id: fanFile; path: root.sensing ? root.sensorPaths.fan : ""; printErrors: false; onLoaded: root.fanRpm = Sensors.rpm(text()) }
    FileView {
        id: netFile
        path: root.networkTrackers > 0 ? "/proc/net/dev" : ""
        printErrors: false
        onLoaded: {
            const totals = Sensors.netTotals(text())
            if (!totals) return
            const now = Date.now()
            const rates = Sensors.rates(root.lastNet, totals, root.lastNet ? now - root.lastNet.at : 0)
            if (rates) root.netRates = rates
            root.lastNet = { rx: totals.rx, tx: totals.tx, at: now }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.processTrackers > 0
        onTriggered: root.readProcesses()
    }
}
