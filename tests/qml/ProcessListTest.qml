import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/system/ProcessLogic.js" as P

// The system popup's busiest processes from two reads of /proc
// (services/system/ProcessLogic.js), the way top's second iteration gave
// them.
ShellRoot {
    // A read as SystemStatsService's reader prints it: its pid and the page
    // size, /proc/stat (two CPUs), then one stat line per process.
    function read(elapsed, rows) {
        const lines = ["900 4096", "cpu  " + [elapsed / 2, 0, 0, elapsed / 2, 0, 0, 0, 0, 0, 0].join(" "),
                       "cpu0 1 0 0 1 0 0 0 0 0 0", "cpu1 1 0 0 1 0 0 0 0 0 0", "intr 12345 0 0", "ctxt 999"]
        for (const row of rows) {
            // pid (comm) state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt
            // utime stime cutime cstime priority nice threads itreal starttime vsize rss ...
            lines.push(row.pid + " (" + row.name + ") S 1 1 1 0 -1 4194560 10 0 0 0 " + row.utime + " " + row.stime
                       + " 0 0 20 0 1 0 " + (row.start || 100) + " 123456 " + row.rss + " 18446744073709551615 0 0")
        }
        return lines.join("\n") + "\n"
    }

    Component.onCompleted: {
        const first = P.snapshot(read(1000, [
            { pid: 10, name: "quickshell", utime: 500, stime: 100, rss: 50000 },
            { pid: 20, name: "Web Content (x)", utime: 100, stime: 0, rss: 25000 },
            { pid: 30, name: "idle", utime: 7, stime: 0, rss: 100 },
            { pid: 900, name: "cat", utime: 0, stime: 0, rss: 10 }
        ]))
        T.eq([first.reader, first.pageSize, first.cpus, first.elapsed], [900, 4096, 2, 1000], "the reader, the page size, two CPUs, the jiffies")
        T.eq(first.processes["20:100"].name, "Web Content (x)", "a name with spaces and parentheses stays whole")
        T.eq(P.busiest(null, first, 8000000, 5), null, "a first read alone has nothing to compare with")

        // 200 jiffies later over two CPUs: 100 per CPU. quickshell used 50,
        // the web content 100 (all of one CPU), idle nothing; a new process
        // used 20 since it started; pid 20's number came back as another
        // process (another start time), which counts from nothing.
        const second = P.snapshot(read(1200, [
            { pid: 10, name: "quickshell", utime: 540, stime: 110, rss: 50000 },
            { pid: 20, name: "Web Content (x)", utime: 200, stime: 0, rss: 25000 },
            { pid: 30, name: "idle", utime: 7, stime: 0, rss: 100 },
            { pid: 40, name: "new", utime: 15, stime: 5, rss: 1000 },
            { pid: 900, name: "cat", utime: 3, stime: 0, rss: 10 }
        ]))
        const list = P.busiest(first, second, 8000000, 5)
        T.eq(list.map(item => item.name), ["Web Content (x)", "quickshell", "new", "idle"],
             "busiest first, the reader left out")
        T.eq(list.map(item => item.cpu), [100, 50, 20, 0], "percent of one CPU, as top's %CPU")
        // 50000 pages of 4096 bytes of 8 000 000 KiB.
        T.near(list[1].memory, 2.5, "resident memory in percent of the machine's", 0.051)
        T.eq(P.busiest(first, second, 8000000, 2).length, 2, "as many as asked for")
        T.eq(P.busiest(first, second, 0, 5)[1].memory, 0, "no memory total yet: 0 %")

        const reused = P.snapshot(read(1400, [{ pid: 30, name: "other", utime: 9, stime: 0, rss: 100, start: 5000 }]))
        T.eq(P.busiest(second, reused, 8000000, 5)[0].cpu, 9, "a pid used again by another process counts from nothing")
        T.eq(P.busiest(second, second, 8000000, 5), null, "no time between two reads: no answer")
        T.eq(P.snapshot("garbage").elapsed, -1, "no /proc/stat: no answer")
        T.eq(P.busiest(P.snapshot(""), P.snapshot(""), 1, 5), null, "nor from nothing")

        T.finish("ProcessListTest")
    }
}
