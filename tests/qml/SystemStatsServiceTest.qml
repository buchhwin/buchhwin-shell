import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T

// SystemStatsService itself: a sample's figures come out of the read that the
// sample started, not the one before it. The service reads /proc/stat,
// meminfo and loadavg once when it is created, so the CPU times are known
// before anything tracks; one `sample()` then has to move them on. A
// `reload()` followed by `text()` in the same tick never did - it handed
// back the previous read, and every meter ran one tick behind.
ShellRoot {
    id: root
    property int waits: 0
    property int tries: 0
    property real firstTotal: -1

    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            const settled = SystemStatsService.lastCpu !== null && SystemStatsService.memory !== null
                && SystemStatsService.load.length === 3
            if (!settled && root.waits < 100) return
            stop()
            T.ok(SystemStatsService.lastCpu !== null, "the first read of /proc/stat reaches the service")
            T.ok(SystemStatsService.memory !== null && SystemStatsService.memory.total > 0, "and meminfo")
            T.eq(SystemStatsService.load.length, 3, "and loadavg")
            root.firstTotal = SystemStatsService.lastCpu ? SystemStatsService.lastCpu.total : -1
            SystemStatsService.sample()
            settle.start()
        }
    }

    Timer {
        id: settle
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            const times = SystemStatsService.lastCpu
            const moved = times !== null && times.total > root.firstTotal
            if (!moved && root.tries < 40) return
            stop()
            T.ok(moved, "one sample moves the CPU times on - the figure is the read it started, not the one before ("
                        + root.firstTotal + " -> " + (times ? times.total : "null") + ")")
            T.finish("SystemStatsService")
        }
    }
}
