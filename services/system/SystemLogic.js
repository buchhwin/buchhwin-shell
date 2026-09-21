.pragma library

// Parsing for CPU, memory and disk usage and the busiest processes
// (SystemStatsService, the CPU/RAM/disk widgets and the system popup).

// First line of /proc/stat → { idle, total } jiffies (idle includes iowait).
function cpuTimes(statText) {
    const line = String(statText || "").split("\n")[0].trim()
    if (!line.startsWith("cpu ")) return null
    const fields = line.split(/\s+/).slice(1).map(Number)
    if (fields.length < 4 || fields.some(value => isNaN(value))) return null
    return { idle: fields[3] + (fields[4] || 0), total: fields.reduce((sum, value) => sum + value, 0) }
}

// Share of busy time between two samples (0..1); -1 without a usable pair.
function cpuUsage(previous, current) {
    if (!previous || !current || current.total <= previous.total) return -1
    const busy = 1 - (current.idle - previous.idle) / (current.total - previous.total)
    return Math.max(0, Math.min(1, busy))
}

// /proc/meminfo → { total, used, usage } in KiB; used = total - available.
function memory(meminfoText) {
    const values = {}
    for (const line of String(meminfoText || "").split("\n")) {
        const match = line.match(/^(\w+):\s+(\d+)/)
        if (match) values[match[1]] = Number(match[2])
    }
    if (!values.MemTotal) return null
    const available = values.MemAvailable !== undefined ? values.MemAvailable : (values.MemFree || 0)
    const used = Math.max(0, values.MemTotal - available)
    return { total: values.MemTotal, used: used, usage: used / values.MemTotal }
}

// `df -B1 --output=size,used /` → { total, used, usage } in bytes.
function disk(dfText) {
    const line = String(dfText || "").split("\n").slice(1).find(item => item.trim().length)
    if (!line) return null
    const [total, used] = line.trim().split(/\s+/).map(Number)
    if (!(total > 0) || isNaN(used)) return null
    return { total: total, used: used, usage: Math.min(1, used / total) }
}

// /proc/loadavg → [1 min, 5 min, 15 min].
function loadAverage(text) {
    const values = String(text || "").trim().split(/\s+/).slice(0, 3).map(Number)
    return values.length === 3 && values.every(value => !isNaN(value)) ? values : []
}

// `top -b -n 2 -o %CPU` output (LC_ALL=C): the rows of the LAST iteration
// (the first one averages since each process started) → [{ pid, name, cpu, memory }]
// with cpu and memory in percent. The top process itself is skipped.
function topProcesses(text, count) {
    const lines = String(text || "").split("\n")
    let header = -1
    for (let i = lines.length - 1; i >= 0; --i) {
        if (/^\s*PID\s+USER\b/.test(lines[i])) { header = i; break }
    }
    if (header < 0) return []
    const columns = lines[header].trim().split(/\s+/)
    const cpuColumn = columns.indexOf("%CPU")
    const memoryColumn = columns.indexOf("%MEM")
    const nameColumn = columns.indexOf("COMMAND")
    if (cpuColumn < 0 || memoryColumn < 0 || nameColumn < 0) return []
    const result = []
    for (const line of lines.slice(header + 1)) {
        const fields = line.trim().split(/\s+/)
        if (fields.length <= nameColumn) continue
        const name = fields.slice(nameColumn).join(" ")
        const cpu = Number(fields[cpuColumn].replace(",", "."))
        const mem = Number(fields[memoryColumn].replace(",", "."))
        if (name === "top" || isNaN(cpu) || isNaN(mem)) continue
        result.push({ pid: Number(fields[0]), name: name, cpu: cpu, memory: mem })
        if (result.length >= (count || 5)) break
    }
    return result
}

// Bytes → "512 MB", "7.4 GB", "1.9 TB" (decimal units like df -H and KDE).
function formatBytes(bytes) {
    const value = Number(bytes)
    if (!(value > 0)) return "0 B"
    const units = ["B", "KB", "MB", "GB", "TB"]
    let unit = 0
    let scaled = value
    while (scaled >= 1000 && unit < units.length - 1) { scaled /= 1000; unit += 1 }
    return (scaled >= 100 || unit === 0 ? Math.round(scaled) : scaled.toFixed(1)) + " " + units[unit]
}

function percent(ratio) {
    return Math.round(Math.max(0, Math.min(1, Number(ratio) || 0)) * 100) + "%"
}
