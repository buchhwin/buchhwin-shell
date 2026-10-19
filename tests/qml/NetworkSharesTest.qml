import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/ShareLogic.js" as S

// Network drives in the VPN popup (services/network/ShareLogic.js): read
// from mountinfo alone, the automount points that are drives, and what the
// popup says with and without a VPN.
ShellRoot {
    Component.onCompleted: {
        // Three systemd automounts of network drives (fd and pipe numbers as
        // mountinfo prints them), systemd's own binfmt_misc automount and a
        // /boot mounted on first use, which are not drives.
        const idle = [
            "22 1 0:21 / / rw,relatime shared:1 - btrfs /dev/nvme0n1p2 rw,ssd,space_cache=v2,subvol=/@",
            "39 26 0:37 / /proc/sys/fs/binfmt_misc rw,relatime shared:13 - autofs systemd-1 rw,fd=44,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=13471",
            "48 32 0:42 / /mnt/work/H rw,relatime shared:21 - autofs systemd-1 rw,fd=84,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=5486",
            "54 32 0:47 / /mnt/work/I rw,relatime shared:91 - autofs systemd-1 rw,fd=86,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=5492",
            "57 32 0:48 / /mnt/work/X rw,relatime shared:94 - autofs systemd-1 rw,fd=87,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=5498",
            "60 22 0:50 / /boot rw,relatime shared:30 - autofs systemd-1 rw,fd=90,direct"
        ].join("\n") + "\n"
        const mounts = S.parseMountinfo(idle)
        T.eq(mounts.length, 6, "every line")
        T.eq(mounts[2], { point: "/mnt/work/H", fstype: "autofs", source: "systemd-1" }, "point, type and source")
        T.eq(S.shares(mounts), [
            { point: "/mnt/work/H", name: "H", mounted: false, automount: true },
            { point: "/mnt/work/I", name: "I", mounted: false, automount: true },
            { point: "/mnt/work/X", name: "X", mounted: false, automount: true }
        ], "the three drives, none mounted; binfmt_misc and /boot are the system's")

        // H mounted: a cifs line on the same point. A USB disk on an
        // automount is local and left out; a plain fstab share is listed.
        const busy = idle
            + "70 48 0:60 / /mnt/work/H rw,relatime shared:99 - cifs //files.example.test/home rw,vers=3.1.1,sec=ntlmssp\n"
            + "71 32 0:61 / /mnt/usb rw,relatime shared:100 - autofs systemd-1 rw,fd=91,direct\n"
            + "72 71 8:17 / /mnt/usb rw,relatime shared:101 - ext4 /dev/sdb1 rw\n"
            + "73 32 0:62 / /srv/nfs\\040data rw,relatime shared:102 - nfs4 server.example.test:/data rw,vers=4.2\n"
        const list = S.shares(S.parseMountinfo(busy))
        T.eq(list.map(share => share.name + ":" + share.mounted + ":" + share.automount),
             ["H:true:true", "I:false:true", "X:false:true", "nfs data:true:false"],
             "H mounted, the USB disk left out, an NFS share with a space in its path")
        T.eq(list[3].point, "/srv/nfs data", "mountinfo's octal escapes")
        T.eq(S.parseMountinfo("garbage\n\n1 2 3\n"), [], "lines that are not mountinfo's")

        T.eq([S.names([]), S.names(list.slice(0, 1)), S.names(list.slice(0, 2)), S.names(list.slice(0, 3))],
             ["", "H", "H and I", "H, I and X"], "names as a list")

        // No VPN, nothing mounted: which drives need it. Mounted without a
        // VPN: the hang to expect. With a VPN: how they mount.
        const three = S.shares(mounts)
        T.eq(S.summary(three, false), { line: "H, I and X need the VPN. Opening one without it can hang the file manager.", warning: "" },
             "the drives that need the VPN")
        T.eq(S.summary(three.slice(0, 1), false).line, "H needs the VPN. Opening it without it can hang the file manager.", "one drive")
        T.eq(S.summary(list, false).warning,
             "H and nfs data are mounted with no VPN up. If the server is out of reach, the file manager hangs on them.",
             "the Dolphin-hang state, warned")
        T.eq(S.summary(list.slice(0, 1), false).warning,
             "H is mounted with no VPN up. If the server is out of reach, the file manager hangs on it.", "one mounted")
        T.eq(S.summary(three, true), { line: "A drive mounts when it is opened.", warning: "" }, "with the VPN up")
        T.eq(S.summary([list[0]], true), { line: "", warning: "" }, "with the VPN up and all mounted")
        T.eq(S.summary([], false), { line: "", warning: "" }, "no drives, nothing to say")

        T.eq([S.status(three[0]), S.status(list[0])], ["/mnt/work/H · Not mounted", "/mnt/work/H · Mounted"], "the row's line")
        T.eq([S.openable(three[0], true), S.openable(three[0], false), S.openable(null, true),
              S.openable({ point: "relative" }, true)], [true, false, false, false], "Open only with a VPN up")

        T.finish("NetworkSharesTest")
    }
}
