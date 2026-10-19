import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/system/SensorLogic.js" as S

// The system popup's sensors: which of the kernel's files are read for the
// CPU, the GPU, the disk and the fan (and which GPU is never woken for it),
// what a read says, and the network's speed between two reads of
// /proc/net/dev. The discovery run is tried against this machine's /sys and
// only for its shape - a test container may have no sensors at all.
ShellRoot {
    id: root
    property int step: 0

    Process {
        id: shell
        property string output: ""
        property int code: -1
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: exitCode => { shell.code = exitCode; next.start() }
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }

    Component.onCompleted: {
        // A ThinkPad with an AMD APU, as this laptop reports it (the paths
        // shortened), and a discrete GPU that sleeps.
        const listing = [
            "fan\tacpi_fan\t\t\t/sys/class/hwmon/hwmon1/fan1_input",
            "temp\tacpitz\t\t\t/sys/class/hwmon/hwmon2/temp1_input",
            "temp\tnvme\tComposite\t\t/sys/class/hwmon/hwmon4/temp1_input",
            "temp\tnvme\tSensor 1\t\t/sys/class/hwmon/hwmon4/temp2_input",
            "fan\tthinkpad\t\t\t/sys/class/hwmon/hwmon5/fan1_input",
            "temp\tthinkpad\tCPU\t\t/sys/class/hwmon/hwmon5/temp1_input",
            "temp\tthinkpad\tGPU\t\t/sys/class/hwmon/hwmon5/temp2_input",
            "temp\tamdgpu\tedge\t0\t/sys/class/hwmon/hwmon9/temp1_input",
            "temp\tamdgpu\tedge\t1\t/sys/class/hwmon/hwmon6/temp1_input",
            "temp\tk10temp\tTctl\t\t/sys/class/hwmon/hwmon7/temp1_input",
            "busy\tgpu\t\t0\t/sys/class/drm/card0/device/gpu_busy_percent",
            "busy\tgpu\t\t1\t/sys/class/drm/card1/device/gpu_busy_percent",
            "temp\tbroken",
            "temp\tx\t\t\t/etc/passwd"
        ].join("\n")
        const rows = S.parseDiscovery(listing)
        T.eq(rows.length, 12, "every sensor line, nothing outside /sys")
        T.eq(S.pick(rows), {
            cpu: "/sys/class/hwmon/hwmon7/temp1_input",
            gpu: "/sys/class/hwmon/hwmon6/temp1_input",
            gpuBusy: "/sys/class/drm/card1/device/gpu_busy_percent",
            disk: "/sys/class/hwmon/hwmon4/temp1_input",
            fan: "/sys/class/hwmon/hwmon5/fan1_input"
        }, "k10temp's Tctl, the GPU the machine boots on (not the sleeping one), the NVMe's composite, the ThinkPad's fan")
        T.eq(S.pick(S.parseDiscovery("temp\tcoretemp\tCore 0\t\t/sys/a\ntemp\tcoretemp\tPackage id 0\t\t/sys/b")).cpu, "/sys/b",
             "Intel's package before a core")
        T.eq(S.pick(S.parseDiscovery("temp\tacpitz\t\t\t/sys/z\nfan\tacpi_fan\t\t\t/sys/f")), { cpu: "/sys/z", gpu: "", gpuBusy: "", disk: "", fan: "/sys/f" },
             "an ACPI zone as the last resort, and ACPI's fan when it is the only one")
        T.eq(S.pick([]), { cpu: "", gpu: "", gpuBusy: "", disk: "", fan: "" }, "no sensors: nothing to read")
        T.eq(S.pick(S.parseDiscovery("temp\tamdgpu\tedge\t0\t/sys/d\nbusy\tgpu\t\t0\t/sys/e")), { cpu: "", gpu: "", gpuBusy: "", disk: "", fan: "" },
             "a discrete GPU alone is still never read")

        // ---- reads ------------------------------------------------------------
        T.eq([S.celsius("41875\n"), S.celsius("-273000"), S.celsius(""), S.celsius("x")].map(v => isNaN(v) ? "none" : v),
             [41.9, "none", "none", "none"], "millidegrees, a sensor that is off, no read")
        T.eq([S.rpm("2400\n"), S.rpm("0"), isNaN(S.rpm(""))], [2400, 0, true], "the fan in rpm; 0 is a fan that stands")
        T.eq([S.busy("37"), S.busy("150"), isNaN(S.busy(""))], [0.37, 1, true], "the GPU's load")
        T.eq([S.formatTemp(41.9, false), S.formatTemp(41.9, true), S.formatTemp(NaN, false)], ["42°", "107°", ""],
             "whole degrees, in the weather's unit")
        T.eq([S.level(79), S.level(80), S.level(95), S.level(NaN)], ["", "warning", "danger", ""], "too hot")

        // ---- the network ---------------------------------------------------------
        const header = "Inter-|   Receive |  Transmit\n face |bytes    packets errs drop fifo frame compressed multicast|bytes ...\n"
        const first = S.netTotals(header
            + "    lo: 209815706   22802    0    0    0     0          0         0 209815706   22802    0    0    0     0       0          0\n"
            + "wlp2s0: 1000 10 0 0 0 0 0 0 500 5 0 0 0 0 0 0\n"
            + "   wg0: 400 4 0 0 0 0 0 0 300 3 0 0 0 0 0 0\n"
            + "enp1s0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n")
        T.eq(first, { rx: 1000, tx: 500 }, "the real interfaces, not the loopback or a tunnel")
        const second = { rx: 3000, tx: 1500 }
        T.eq(S.rates(first, second, 2000), { rx: 1000, tx: 500 }, "bytes per second between two reads")
        T.eq([S.rates(null, second, 2000), S.rates(second, first, 2000), S.rates(first, second, 0)], [null, null, null],
             "no pair, a counter that went back, no time between")
        T.eq(S.netTotals(header + "    lo: 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0\n"), null, "only a loopback: no network")
        T.eq([S.formatRate(0), S.formatRate(512), S.formatRate(340000), S.formatRate(1250000), S.formatRate(NaN)],
             ["0 B/s", "512 B/s", "340 KB/s", "1.3 MB/s", "0 B/s"], "rates in decimal units")
        advance()
    }

    function advance() {
        step += 1
        if (step === 1) {
            shell.command = S.discoveryCommand()
            shell.running = true
        } else if (step === 2) {
            T.eq(shell.code, 0, "the discovery run ends cleanly, sensors or not")
            const rows = S.parseDiscovery(shell.output)
            T.ok(rows.every(row => row.path.indexOf("/sys/") === 0 && /_input$|gpu_busy_percent$/.test(row.path)),
                 "and lists sensor files only")
            T.finish("SensorTest")
        }
    }
}
