import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/drives/DrivesLogic.js" as D

// The system disk filling up (DrivesLogic, "the system disk filling up"):
// df's lines, the limit per size, told once per filesystem and again only
// after it had room, and the words. Invented numbers.
ShellRoot {
    Component.onCompleted: {
        const GIB = D.GIB
        T.eq(D.spaceCommand(), ["df", "-B1", "--output=source,target,avail,size", "/", "/home"], "one df for the root and /home")

        // df as it answers: a header, / and /home on one btrfs device.
        const both = D.parseSpace("Filesystem     Mounted on Avail    1B-blocks\n"
            + "/dev/nvme0n1p6 /          128517963776 207568764928\n"
            + "/dev/nvme0n1p6 /home      128517963776 207568764928\n")
        T.eq(both, [{ source: "/dev/nvme0n1p6", mounts: ["/", "/home"], free: 128517963776, size: 207568764928 }],
             "one disk for both mount points")
        const apart = D.parseSpace("Filesystem Mounted on Avail 1B-blocks\n/dev/sda2 / 1000 50000\n/dev/sda3 /home 9000 900000\n")
        T.eq(apart.map(item => item.source + ":" + item.mounts.join(",")), ["/dev/sda2:/", "/dev/sda3:/home"], "two disks apart")
        T.eq(D.parseSpace("/dev/x /mnt/My Disk 10 100\n")[0].mounts, ["/mnt/My Disk"], "a mount point with a space")
        T.eq(D.parseSpace("garbage\n\n/dev/x / - 100\n/dev/y / 5 0\n"), [], "nothing that is not a filesystem with a size")

        // The limit: a tenth, between 5 and 20 GiB, never above a quarter.
        T.near(D.spaceLimit(200 * GIB), 20 * GIB, "a tenth of 200 GiB", 1)
        T.near(D.spaceLimit(2000 * GIB), 20 * GIB, "at most 20 GiB on a big disk", 1)
        T.near(D.spaceLimit(30 * GIB), 5 * GIB, "at least 5 GiB on a small one", 1)
        T.near(D.spaceLimit(8 * GIB), 2 * GIB, "but never more than a quarter of a tiny one", 1)
        T.eq(D.spaceLimit(0), 0, "no size, no limit")
        T.ok(D.spaceLow({ free: 4 * GIB, size: 200 * GIB }) && !D.spaceLow({ free: 120 * GIB, size: 200 * GIB }), "low and not low")

        // Told once, again only after it had room.
        const low = { source: "/dev/a", mounts: ["/", "/home"], free: 3 * GIB, size: 200 * GIB }
        let step = D.spaceStep([low], {})
        T.eq([step.warn.length, step.warned], [1, { "/dev/a": true }], "a low disk is told about")
        step = D.spaceStep([Object.assign({}, low, { free: 2 * GIB })], step.warned)
        T.eq(step.warn.length, 0, "and not again while it stays low")
        step = D.spaceStep([Object.assign({}, low, { free: 22 * GIB })], step.warned)
        T.eq([step.warn.length, step.warned], [0, { "/dev/a": true }], "just above the line it is still the same story")
        step = D.spaceStep([Object.assign({}, low, { free: 60 * GIB })], step.warned)
        T.eq(step.warned, {}, "room again ends it")
        step = D.spaceStep([low], step.warned)
        T.eq(step.warn.length, 1, "and the next drop is news")
        T.eq(D.spaceStep([], { "/dev/a": true }).warned, {}, "a disk that is gone is forgotten")

        // The words.
        T.eq(D.mountsText(["/"]), "/", "one mount")
        T.eq(D.mountsText(["/", "/home"]), "/ and /home", "two")
        T.eq(D.mountsText(["/", "/home", "/var"]), "/, /home and /var", "three")
        T.eq(D.spacePercent({ free: 3 * GIB, size: 200 * GIB }), 2, "percent free")
        T.eq(D.spaceTitle(low), "Disk almost full", "title")
        T.eq(D.spaceTitle({ free: 0.5 * GIB, size: 200 * GIB }), "Disk full", "under a gigabyte it is full")
        T.eq(D.spaceBody({ source: "/dev/a", mounts: ["/", "/home"], free: 3200000000, size: 200000000000 }),
             "Only 3.2 GB left on / and /home (2%). Snapshots, caches and recordings are the usual places to look.", "body")
        T.eq(D.spaceBody({ mounts: ["/"], free: 0, size: 100 }), "Only 0 B left on / (0%). Snapshots, caches and recordings are the usual places to look.", "nothing left")
        T.finish("LowSpaceTest")
    }
}
