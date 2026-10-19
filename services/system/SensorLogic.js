.pragma library

// Temperatures, the GPU's load, the fan and the network's speed for the
// system popup and the temperature widget (SystemStatsService). Pure
// functions, unit tested in SensorTest.qml.
//
// Fans spinning up on battery: how hot, and which part. The kernel names its
// sensors through hwmon (/sys/class/hwmon/hwmonN/name, tempN_input in
// millidegrees, fanN_input in rpm) and amdgpu its load
// (/sys/class/drm/cardN/device/gpu_busy_percent). The hwmonN numbers change
// between boots, so the service finds the files once as sampling starts (one
// shell run, `discoveryCommand`) and from then on only reads the few it picked,
// on the same 2-second tick as the CPU meter and only while something shows
// them.
//
// A discrete GPU is never read: on a laptop with two GPUs the second one
// sleeps (runtime power management) and reading its sensors wakes it - the
// battery cost this readout exists to explain. Only the GPU the machine boots
// on (boot_vga 1) counts.

// The CPU's sensor, by hwmon name and label, best first: AMD's Tctl/Tdie
// (k10temp, zenpower), Intel's package (coretemp), the ThinkPad's CPU, and an
// ACPI thermal zone as the last resort.
var CPU_SENSORS = [
    { name: "k10temp", labels: ["Tctl", "Tdie", ""] },
    { name: "zenpower", labels: ["Tdie", "Tctl", ""] },
    { name: "coretemp", labels: ["Package id 0", ""] },
    { name: "thinkpad", labels: ["CPU"] },
    { name: "cpu_thermal", labels: [""] },
    { name: "acpitz", labels: [""] }
]
var GPU_SENSORS = [
    { name: "amdgpu", labels: ["edge", "junction", ""] },
    { name: "nouveau", labels: [""] },
    { name: "thinkpad", labels: ["GPU"] }
]
var DISK_SENSORS = [
    { name: "nvme", labels: ["Composite", ""] },
    { name: "drivetemp", labels: [""] }
]

// One run that lists every candidate: "temp|fan<TAB>hwmon name<TAB>label
// <TAB>boot_vga<TAB>path" per sensor file, and "busy<TAB>card<TAB><TAB>
// boot_vga<TAB>path" per GPU load file. boot_vga is "" for a device that is
// no graphics card. Nothing is read but names, labels and that flag.
function discoveryCommand() {
    return ["sh", "-c",
        "for d in /sys/class/hwmon/hwmon*; do [ -r \"$d/name\" ] || continue; n=$(cat \"$d/name\" 2>/dev/null); "
        + "v=$(cat \"$d/device/boot_vga\" 2>/dev/null); "
        + "for f in \"$d\"/temp*_input \"$d\"/fan*_input; do [ -r \"$f\" ] || continue; l=$(cat \"${f%_input}_label\" 2>/dev/null); "
        + "case ${f##*/} in temp*) k=temp;; *) k=fan;; esac; printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$k\" \"$n\" \"$l\" \"$v\" \"$f\"; done; done; "
        + "for g in /sys/class/drm/card*/device/gpu_busy_percent; do [ -r \"$g\" ] || continue; "
        + "v=$(cat \"${g%/gpu_busy_percent}/boot_vga\" 2>/dev/null); printf 'busy\\tgpu\\t\\t%s\\t%s\\n' \"$v\" \"$g\"; done"]
}

function parseDiscovery(text) {
    const rows = []
    for (const line of String(text || "").split("\n")) {
        const fields = line.split("\t")
        if (fields.length < 5 || ["temp", "fan", "busy"].indexOf(fields[0]) < 0) continue
        if (fields[4].indexOf("/sys/") !== 0) continue
        rows.push({ kind: fields[0], name: fields[1], label: fields[2].trim(), bootVga: fields[3].trim(), path: fields[4] })
    }
    return rows
}

// A graphics device that is not the one the machine boots on: left alone.
function sleepingGpu(row) {
    return row.bootVga === "0"
}

function pickTemp(rows, wanted) {
    for (const sensor of wanted) {
        for (const label of sensor.labels) {
            const row = rows.find(item => item.kind === "temp" && item.name === sensor.name
                                  && (label === "" || item.label === label) && !sleepingGpu(item))
            if (row) return row.path
        }
    }
    return ""
}

// The files to read: { cpu, gpu, gpuBusy, disk, fan }, "" for what this
// machine does not have. The fan is the first that reports rpm (the
// ThinkPad's own before ACPI's, which often reads 0 whatever the fan does).
function pick(rows) {
    const list = rows || []
    const fans = list.filter(item => item.kind === "fan")
    const fan = fans.find(item => item.name !== "acpi_fan") || fans[0]
    const busy = list.find(item => item.kind === "busy" && !sleepingGpu(item))
    return {
        cpu: pickTemp(list, CPU_SENSORS),
        gpu: pickTemp(list, GPU_SENSORS),
        gpuBusy: busy ? busy.path : "",
        disk: pickTemp(list, DISK_SENSORS),
        fan: fan ? fan.path : ""
    }
}

// tempN_input -> degrees Celsius; NaN for a read that is no temperature (a
// sensor that is off reads an error, or -273).
function celsius(text) {
    const value = Number(String(text || "").trim())
    if (!String(text || "").trim().length || !isFinite(value) || value < -40000 || value > 200000) return NaN
    return Math.round(value / 100) / 10
}

function rpm(text) {
    const value = Number(String(text || "").trim())
    return String(text || "").trim().length && isFinite(value) && value >= 0 ? Math.round(value) : NaN
}

// gpu_busy_percent -> 0..1.
function busy(text) {
    const value = Number(String(text || "").trim())
    return String(text || "").trim().length && isFinite(value) ? Math.max(0, Math.min(1, value / 100)) : NaN
}

// "52°" - whole degrees; the unit is the weather's choice of Celsius or
// Fahrenheit.
function formatTemp(celsiusValue, fahrenheit) {
    if (!isFinite(celsiusValue)) return ""
    return Math.round(fahrenheit ? celsiusValue * 9 / 5 + 32 : celsiusValue) + "°"
}

// How hot is too hot for a readout's colour: 80 °C is where laptops start
// to throttle and fans run at full speed; 90 °C is close to the limit.
function level(celsiusValue) {
    return !isFinite(celsiusValue) ? "" : celsiusValue >= 90 ? "danger" : celsiusValue >= 80 ? "warning" : ""
}

// ---- the network --------------------------------------------------------------
// /proc/net/dev counts bytes per interface since boot. The speed is the
// difference between two reads. Virtual interfaces carry traffic that also
// crosses a real one - a tunnel's (wg, tun) on the Wi-Fi under it, a bridge's
// on its members - or none that leaves the machine (lo), so they are left
// out by name.
var VIRTUAL = /^(lo|wg|tun|tap|veth|docker|br-|virbr|vnet|vmnet|tailscale|zt|ppp|dummy|ifb|bond|team)/

function netTotals(text) {
    let rx = 0
    let tx = 0
    let seen = false
    for (const line of String(text || "").split("\n")) {
        const colon = line.indexOf(":")
        if (colon < 0) continue
        const name = line.slice(0, colon).trim()
        if (!name.length || VIRTUAL.test(name)) continue
        const fields = line.slice(colon + 1).trim().split(/\s+/).map(Number)
        if (fields.length < 9 || !isFinite(fields[0]) || !isFinite(fields[8])) continue
        rx += fields[0]
        tx += fields[8]
        seen = true
    }
    return seen ? { rx: rx, tx: tx } : null
}

// Bytes per second between two reads `ms` apart; null without a usable pair
// (a counter that went back is an interface that went and came again).
function rates(previous, current, ms) {
    if (!previous || !current || !(ms > 0) || current.rx < previous.rx || current.tx < previous.tx) return null
    return { rx: (current.rx - previous.rx) * 1000 / ms, tx: (current.tx - previous.tx) * 1000 / ms }
}

// "1.2 MB/s", "340 KB/s", "0 B/s": decimal units, as the disk's figures.
function formatRate(bytesPerSecond) {
    const value = Number(bytesPerSecond)
    if (!isFinite(value) || value < 1) return "0 B/s"
    const units = ["B/s", "KB/s", "MB/s", "GB/s"]
    let unit = 0
    let scaled = value
    while (scaled >= 1000 && unit < units.length - 1) { scaled /= 1000; unit += 1 }
    return (scaled >= 100 || unit === 0 ? Math.round(scaled) : scaled.toFixed(1)) + " " + units[unit]
}
