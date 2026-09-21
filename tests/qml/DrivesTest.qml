import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/drives/DrivesLogic.js" as D

ShellRoot {
    // Synthetic drives in the format of scripts/drives.py.
    FileView { id: sample; path: Qt.resolvedUrl("../fixtures/drives-sample.json").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // Helper lines
        const parsed = D.parseLine(sample.text())
        T.eq(parsed.kind, "drives", "snapshot kind")
        const [stick, disk, card, secure] = parsed.drives
        T.eq(parsed.drives.length, 4, "four drives")
        T.eq(parsed.phones.length, 1, "one phone")
        T.ok(parsed.mtp, "gvfs-mtp flag")
        T.eq(D.parseLine("{\"kind\":\"added\",\"id\":\"x\"}"), { kind: "added", id: "x" }, "event passes through")
        T.eq(D.parseLine("{\"kind\":\"phoneMounted\",\"id\":\"mtp-x\"}"), { kind: "phoneMounted", id: "mtp-x" }, "phone event passes through")
        T.eq(D.parseLine("not json"), null, "noise ignored")
        T.eq(D.parseLine("[1,2]"), null, "non-object ignored")
        T.eq(D.parseLine("{\"kind\":\"drives\",\"drives\":\"bad\"}").drives, [], "broken list")
        T.eq(D.parseLine("{\"kind\":\"drives\",\"drives\":[]}").phones, [], "missing phone list")
        T.ok(!D.parseLine("{\"kind\":\"drives\",\"drives\":[],\"mtp\":false}").mtp, "gvfs-mtp missing")
        const unsafe = D.parseLine(JSON.stringify({ kind: "drives", drives: [
            { id: "a", volumes: [{ device: "/dev/../etc/passwd" }, { device: "sdb1" }] },
            { id: "b", volumes: [{ device: "/dev/sdd1", mountPoints: ["relative", "/run/media/u/X"] }] },
            { id: "c", volumes: [{ device: "/dev/sde1", encrypted: true, unlocked: true, clearDevice: "; rm -rf ~" }] }] }))
        T.eq(unsafe.drives.map(item => item.id), ["b", "c"], "drives without valid devices dropped")
        T.eq(unsafe.drives[0].volumes[0].mountPoints, ["/run/media/u/X"], "relative mount points dropped")
        T.ok(!unsafe.drives[1].volumes[0].unlocked && unsafe.drives[1].volumes[0].clearDevice === "",
             "an invalid cleartext device leaves the volume locked")
        T.ok(!unsafe.drives[0].volumes[0].encrypted, "plain volumes are not encrypted")

        // Labels
        T.eq(D.formatSize(32000000000), "32 GB", "gigabytes")
        T.eq(D.formatSize(1500000000), "1.5 GB", "one decimal below 10")
        T.eq(D.formatSize(2000000000000), "2 TB", "terabytes")
        T.eq(D.formatSize(0), "", "unknown size")
        T.eq(D.fsLabel("vfat"), "FAT", "FAT label")
        T.eq(D.fsLabel("zfs_member"), "zfs_member", "unknown type kept")
        T.eq([D.kind(stick), D.kind(card), D.kind({ bus: "", name: "Disk" })], ["usb", "sd", "disk"], "kinds")
        T.eq(D.notifyIcon(card), "media-flash-sd-mmc", "SD icon name")
        T.eq(D.driveTitle(stick), "PHOTOS", "single labelled volume names the drive")
        T.eq(D.driveTitle(disk), "Example External Disk", "several volumes use the model")
        T.eq(D.driveTitle(card), "SD/MMC Reader", "unlabelled volume uses the model")
        T.eq(D.driveTitle({ name: "", bus: "usb", volumes: [{ label: "" }] }), "USB drive", "fallback name")
        T.eq(D.driveSubtitle(stick), "Example Flash Drive · 32 GB", "stick subtitle")
        T.eq(D.driveSubtitle(disk), "2 TB · 1 of 2 mounted", "disk subtitle")
        T.eq(D.driveSubtitle(card), "64 GB", "card subtitle")
        T.eq(D.driveSubtitle(Object.assign({}, disk, { volumes: disk.volumes.map(volume => Object.assign({}, volume, { mountPoints: [] })) })),
             "2 TB · Not mounted", "nothing mounted")
        T.eq(D.volumeTitle(card.volumes[0]), "64 GB volume", "unlabelled volume")
        T.eq(D.volumeSubtitle(disk.volumes[0]), "1.5 TB · NTFS · Mounted at /run/media/user/Data", "mounted volume")
        T.eq(D.volumeSubtitle(card.volumes[0]), "64 GB · FAT · Read-only · Not mounted", "read-only volume")
        T.eq(D.connectedTitle(stick), "USB drive connected", "USB notification title")
        T.eq(D.connectedTitle(card), "SD card inserted", "SD notification title")
        T.eq(D.connectedBody(stick), "PHOTOS · Example Flash Drive · 32 GB", "notification body")
        T.eq(D.connectedBody(disk), "Example External Disk · 2 TB", "body without duplicate name")
        T.eq(D.summary([]), "No removable drives", "empty summary")
        T.eq(D.summary([stick]), "PHOTOS · Mounted", "one drive")
        T.eq(D.summary([secure]), "Example Secure Drive · Mounted", "drive with an unlocked volume")
        T.eq(D.summary([Object.assign({}, secure, { volumes: [secure.volumes[0]] })]), "VAULT · Locked", "only a locked volume")
        T.eq(D.summary(parsed.drives), "4 drives connected", "several drives")
        T.eq(D.summary(parsed.drives, parsed.phones), "4 drives and 1 phone connected", "drives and a phone")
        T.eq(D.summary([], parsed.phones), "Example Phone · Not open", "one phone")

        // Encrypted volumes
        const [vault, archive] = secure.volumes
        T.ok(D.locked(vault) && !D.locked(archive), "locked state")
        T.eq(D.unlockedVolumes(secure).map(item => item.id), ["sdd2"], "unlocked volumes")
        T.eq(D.fsDevice(vault), "/dev/sdd1", "a locked volume acts on the block device")
        T.eq(D.fsDevice(archive), "/dev/dm-1", "an unlocked volume acts on the cleartext device")
        T.eq(D.volumeTitle(vault), "VAULT", "labelled LUKS volume")
        T.eq(D.volumeTitle({ label: "", encrypted: true, size: 0, device: "/dev/sdd1" }), "Encrypted volume", "unlabelled LUKS volume")
        T.eq(D.volumeSubtitle(vault), "64 GB · Encrypted · Locked", "locked subtitle")
        T.eq(D.volumeSubtitle(archive), "64 GB · Encrypted · ext4 · Mounted at /run/media/user/Archive", "unlocked subtitle")
        T.eq(D.volumeSubtitle(Object.assign({}, archive, { mountPoints: [] })), "64 GB · Encrypted · ext4 · Unlocked · Not mounted",
             "unlocked but not mounted")
        T.eq(D.fsLabel("crypto_LUKS"), "LUKS", "LUKS label")

        // Commands
        T.eq(D.command("mount", "/dev/sdb1"), ["udisksctl", "mount", "--block-device", "/dev/sdb1"], "mount argv")
        T.eq(D.command("unmount", "/dev/sdb1"), ["udisksctl", "unmount", "--block-device", "/dev/sdb1"], "unmount argv")
        T.eq(D.command("powerOff", "/dev/mmcblk0p1"), ["udisksctl", "power-off", "--block-device", "/dev/mmcblk0p1"], "power-off argv")
        // The passphrase is written to stdin, so it never appears in argv.
        T.eq(D.command("unlock", "/dev/sdd1"), ["udisksctl", "unlock", "--block-device", "/dev/sdd1", "--key-file", "/dev/stdin"], "unlock argv")
        T.eq(D.command("lock", "/dev/sdd1"), ["udisksctl", "lock", "--block-device", "/dev/sdd1"], "lock argv")
        T.eq(D.command("format", "/dev/sdb1"), null, "unknown action")
        T.eq(D.command("mount", "--help"), null, "option-like device rejected")
        T.eq(D.command("mount", "/dev/sdb1; rm -rf ~"), null, "shell characters rejected")
        T.eq(D.command("unlock", "/dev/sdb1 --key-file /etc/shadow"), null, "unlock device with options rejected")
        T.eq(D.parseCleartext("Unlocked /dev/sdd1 as /dev/dm-1."), "/dev/dm-1", "cleartext device from the output")
        T.eq(D.parseCleartext("Error unlocking /dev/sdd1"), "", "no cleartext device")
        T.eq(D.wrap(["udisksctl", "mount"]).slice(3), ["sh", "udisksctl", "mount"], "argv stays separate behind sh -c")
        T.eq(D.parseResult("Mounted /dev/sdb1 at /run/media/user/My Stick\n\n@exit 0\n"),
             { code: 0, output: "Mounted /dev/sdb1 at /run/media/user/My Stick" }, "result with exit code")
        T.eq(D.parseResult("partial").code, -1, "missing exit code")
        T.eq(D.parseMountPoint("Mounted /dev/sdb1 at /run/media/user/My Stick"), "/run/media/user/My Stick", "mount point with a space")
        T.eq(D.parseMountPoint("Error mounting"), "", "no mount point")

        // Errors
        const busy = "Error unmounting /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: Error unmounting /dev/sdb1: target is busy"
        T.eq(D.errorKind(busy), "DeviceBusy", "busy kind")
        T.eq(D.errorText("unmount", "PHOTOS", busy), "“PHOTOS” is in use. Close the files and apps that use it, then try again.", "busy text")
        T.eq(D.errorText("powerOff", "PHOTOS", "Error powering off drive: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Error syncing /dev/sdb: target is busy (udisks-error-quark, 0)"),
             "“PHOTOS” is in use. Close the files and apps that use it, then try again.", "busy while powering off")
        T.eq(D.errorText("mount", "Data", "Error mounting /dev/sdc1: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedCanObtain: Not authorized"),
             "Not allowed to mount “Data”.", "not authorized")
        T.eq(D.errorText("mount", "Data", "Error looking up object for device /dev/sdc1"), "“Data” is no longer connected.", "vanished device")
        T.eq(D.errorText("mount", "Data", "Error mounting /dev/sdc1: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Error mounting /dev/sdc1 at /run/media/user/Data: wrong fs type, bad option"),
             "Could not mount “Data”: wrong fs type, bad option", "generic error keeps the reason")
        T.eq(D.errorText("powerOff", "X", ""), "Could not safely remove “X”.", "empty output")
        T.ok(D.harmless("unmount", "GDBus.Error:org.freedesktop.UDisks2.Error.NotMounted: not mounted"), "already unmounted")
        T.ok(D.harmless("mount", "GDBus.Error:org.freedesktop.UDisks2.Error.AlreadyMounted: at /x"), "already mounted")
        T.ok(!D.harmless("unmount", busy), "busy is not harmless")

        // Unlock errors
        const wrong = "Error unlocking /dev/sdd1: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Error unlocking /dev/sdd1: Failed to activate device: Incorrect passphrase"
        T.eq(D.errorKind(wrong), "WrongPassphrase", "wrong passphrase kind")
        T.eq(D.errorText("unlock", "VAULT", wrong), "Wrong passphrase for “VAULT”. Try again.", "wrong passphrase text")
        T.eq(D.errorKind("Error unlocking /dev/sdd1: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: No key available with this passphrase"),
             "WrongPassphrase", "other cryptsetup wording")
        T.eq(D.errorText("unlock", "VAULT", "Error unlocking /dev/sdd1: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedDismissed: Not authorized"),
             "Not allowed to unlock “VAULT”.", "unlock not authorized")
        T.eq(D.errorText("lock", "VAULT", busy), "“VAULT” is in use. Close the files and apps that use it, then try again.", "busy while locking")
        T.ok(D.harmless("unlock", "GDBus.Error:org.freedesktop.UDisks2.Error.AlreadyUnlocked: x"), "already unlocked")
        T.ok(D.harmless("lock", "GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Device /dev/sdd1 is not unlocked"), "already locked")
        T.ok(!D.harmless("unlock", wrong), "a wrong passphrase is not harmless")

        // MTP phones
        const phone = parsed.phones[0]
        T.eq(phone.id, "mtp-example_phone_0005", "phone id")
        T.eq(D.phoneTitle(phone), "Example Phone", "phone title")
        T.eq(D.phoneSubtitle(phone), "MTP · Allow file access on the phone, then press Open", "phone not open")
        T.eq(D.phoneSubtitle(Object.assign({}, phone, { mounted: true })), "MTP · Files open", "phone open")
        T.eq(D.phoneConnectedBody(phone), "Example Phone · MTP", "phone notification body")
        T.eq(D.normalizePhones([{ id: "mtp-x", name: "", uri: "mtp://x/", mountPoint: "relative", mounted: true }]),
             [{ id: "mtp-x", name: "Phone", uri: "mtp://x/", mountPoint: "", mounted: true }], "phone defaults")
        T.eq(D.normalizePhones([{ id: "a", uri: "file:///tmp" }, { id: "b", uri: "mtp://x/../../etc" },
                                { id: "", uri: "mtp://x/" }, { id: "d", uri: "mtp://x y/" }]), [], "unsafe phones dropped")
        T.eq(D.normalizePhones("bad"), [], "broken phone list")
        T.ok(D.validMtpUri("mtp://%5Busb%3A001%2C005%5D/"), "encoded legacy URI")
        T.ok(!D.validMtpUri("mtp://x/;reboot"), "shell characters rejected")
        T.eq(D.phoneCommand("mount", phone.uri), ["gio", "mount", "mtp://example_phone_0005/"], "phone mount argv")
        T.eq(D.phoneCommand("unmount", phone.uri), ["gio", "mount", "-u", "mtp://example_phone_0005/"], "phone unmount argv")
        T.eq(D.phoneCommand("mount", "mtp://x/ --foo"), null, "unsafe phone URI rejected")
        T.eq(D.phoneCommand("format", phone.uri), null, "unknown phone action")
        T.eq(D.phoneErrorText("mount", "Pixel", "gio: mtp://x/: Unable to open MTP device '[usb:001,005]'"),
             "“Pixel” did not answer. Unlock the phone, allow file transfer and connect it again.", "phone not ready")
        T.eq(D.phoneErrorText("mount", "Pixel", "gio: mtp://x/: Error mounting location: No route"),
             "Could not open “Pixel”: No route", "generic phone error")
        T.eq(D.phoneErrorText("unmount", "Pixel", ""), "Could not close “Pixel”.", "empty phone error")
        T.ok(D.phoneHarmless("mount", "Location is already mounted"), "phone already mounted")
        T.ok(D.phoneHarmless("unmount", "Location is not mounted"), "phone already unmounted")
        T.ok(!D.phoneHarmless("unmount", "Unable to open MTP device"), "real phone error stays an error")
        T.finish("DrivesTest")
    }
}
