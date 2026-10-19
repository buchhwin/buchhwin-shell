.pragma library

// The busiest processes for the system popup (SystemStatsService), from
// /proc itself: one `cat` of /proc/stat and every /proc/<pid>/stat per tick,
// each process's CPU time against the one before. `top -b -n 2 -d 0.5`
// gave the same list at 26-64 ms of CPU and 0.77 s per run, every three
// seconds while the popup was open - its second iteration only there to get
// a current %CPU, which the tick before already gives here.

// The reader's output: a first line "<its pid> <page size>", then /proc/stat,
// then one line per process →
// { reader, pageSize, cpus, elapsed, processes: { "<pid>:<start>": { pid, name, ticks, rss } } }.
// `elapsed` is the machine's jiffies summed over all CPUs, as /proc/stat's
// first line counts them; a process's `ticks` (utime + stime) are in the same
// unit. Keyed by pid and start time, so a pid used again is a new process.
function snapshot(text) {
    const lines = String(text || "").split("\n")
    const head = (lines[0] || "").trim().split(/\s+/).map(Number)
    const result = { reader: head[0] || -1, pageSize: head[1] > 0 ? head[1] : 4096, cpus: 0, elapsed: -1, processes: {} }
    for (let i = 1; i < lines.length; ++i) {
        const line = lines[i]
        if (line.startsWith("cpu ")) {
            // user nice system idle iowait irq softirq steal; guest time is
            // counted in user already.
            const fields = line.trim().split(/\s+/).slice(1, 9).map(Number)
            if (fields.length >= 4 && fields.every(value => !isNaN(value)))
                result.elapsed = fields.reduce((sum, value) => sum + value, 0)
            continue
        }
        if (/^cpu\d+\s/.test(line)) { result.cpus += 1; continue }
        const open = line.indexOf(" (")
        const close = line.lastIndexOf(")")
        if (open <= 0 || close < open) continue
        const pid = Number(line.slice(0, open))
        if (!(pid > 0)) continue
        // After the name: state is field 3, utime 14, stime 15, starttime 22,
        // rss 24 (proc(5)); the name may hold spaces and parentheses itself.
        const rest = line.slice(close + 2).split(" ")
        const ticks = Number(rest[11]) + Number(rest[12])
        const start = rest[19] || "0"
        const rss = Number(rest[21])
        if (isNaN(ticks) || isNaN(rss)) continue
        result.processes[pid + ":" + start] = { pid: pid, name: line.slice(open + 2, close), ticks: ticks, rss: rss }
    }
    result.cpus = Math.max(1, result.cpus)
    return result
}

// The `count` busiest processes between two snapshots, as top's list was:
// [{ pid, name, cpu, memory }] with cpu in percent of one CPU (top's Irix
// mode; the popup shares it out, SystemLogic.processShare) and memory in
// percent of `memTotalKiB`. null without a usable pair - the first tick, or
// no time between them. A process new since the last tick ran only since
// then, so all its time counts. The reader itself is left out, as top
// left itself out.
function busiest(previous, current, memTotalKiB, count) {
    if (!previous || !current || previous.elapsed < 0 || current.elapsed <= previous.elapsed) return null
    const perCpu = (current.elapsed - previous.elapsed) / Math.max(1, current.cpus)
    const memory = Number(memTotalKiB) > 0 ? Number(memTotalKiB) * 1024 : 0
    const list = []
    for (const key of Object.keys(current.processes)) {
        const item = current.processes[key]
        if (item.pid === current.reader) continue
        const before = previous.processes[key]
        const used = Math.max(0, item.ticks - (before ? before.ticks : 0))
        list.push({
            pid: item.pid, name: item.name,
            cpu: Math.round(used / perCpu * 1000) / 10,
            memory: memory > 0 ? Math.round(item.rss * current.pageSize / memory * 1000) / 10 : 0
        })
    }
    list.sort((a, b) => (b.cpu - a.cpu) || (b.memory - a.memory) || (a.pid - b.pid))
    return list.slice(0, count || 5)
}
