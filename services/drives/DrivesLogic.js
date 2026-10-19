.pragma library

// Removable drives and MTP phones: JSON lines from scripts/drives.py, labels,
// udisksctl and gio argv and readable error messages. Pure functions, unit
// tested in DrivesTest.qml. A LUKS passphrase never passes through here: it
// goes to `udisksctl unlock --key-file /dev/stdin` over the process' stdin.

// One helper line → message object, or null for noise.
function parseLine(line) {
    let message = null
    try { message = JSON.parse(line) } catch (error) { return null }
    if (!message || typeof message !== "object" || typeof message.kind !== "string") return null
    if (message.kind === "drives")
        return { kind: "drives", drives: normalizeDrives(message.drives), phones: normalizePhones(message.phones),
                 mtp: message.mtp !== false }
    return message
}

function normalizeDrives(list) {
    if (!Array.isArray(list)) return []
    return list.filter(item => item && typeof item.id === "string" && Array.isArray(item.volumes))
        .map(item => ({
            id: item.id,
            name: String(item.name || ""),
            bus: String(item.bus || ""),
            size: Number(item.size) || 0,
            canPowerOff: item.canPowerOff === true,
            ejectable: item.ejectable === true,
            volumes: item.volumes.filter(volume => volume && validDevice(volume.device)).map(volume => ({
                id: String(volume.id || ""),
                device: volume.device,
                label: String(volume.label || ""),
                fsType: String(volume.fsType || ""),
                size: Number(volume.size) || 0,
                mountPoints: Array.isArray(volume.mountPoints) ? volume.mountPoints.filter(path => typeof path === "string" && path.startsWith("/")) : [],
                readOnly: volume.readOnly === true,
                encrypted: volume.encrypted === true,
                // Unlocked LUKS volumes carry the cleartext device that holds the filesystem.
                unlocked: volume.encrypted === true && volume.unlocked === true && validDevice(volume.clearDevice),
                clearDevice: volume.encrypted === true && validDevice(volume.clearDevice) ? volume.clearDevice : ""
            }))
        }))
        .filter(item => item.volumes.length > 0)
}

// MTP phones from the gvfs volume monitor; UDisks2 never sees them.
function normalizePhones(list) {
    if (!Array.isArray(list)) return []
    return list.filter(item => item && typeof item.id === "string" && item.id.length > 0 && validMtpUri(item.uri))
        .map(item => ({
            id: item.id,
            name: String(item.name || "").trim() || "Phone",
            uri: item.uri,
            mountPoint: typeof item.mountPoint === "string" && item.mountPoint.startsWith("/") ? item.mountPoint : "",
            mounted: item.mounted === true
        }))
}

// Device nodes go to udisksctl as separate argv entries; still refuse anything
// that is not a plain /dev path.
function validDevice(device) {
    return typeof device === "string" && /^\/dev\/[A-Za-z0-9_.:+\-\/]+$/.test(device) && device.indexOf("..") < 0
}

// gvfs MTP URIs look like mtp://SERIAL/ or mtp://%5Busb%3A001%2C005%5D/.
function validMtpUri(uri) {
    return typeof uri === "string" && uri.length > 6 && uri.length <= 512
        && /^mtp:\/\/[A-Za-z0-9%._~:@,\[\]\/-]+$/.test(uri) && uri.indexOf("..") < 0
}

// Decimal units like KDE and GNOME ("16 GB" for a 16 GB stick).
function formatSize(bytes) {
    const value = Number(bytes) || 0
    if (value <= 0) return ""
    const units = ["B", "KB", "MB", "GB", "TB"]
    let index = 0
    let amount = value
    while (amount >= 1000 && index < units.length - 1) { amount /= 1000; index += 1 }
    const digits = amount >= 10 || index === 0 ? 0 : 1
    return amount.toFixed(digits).replace(/\.0$/, "") + " " + units[index]
}

function fsLabel(type) {
    const names = { vfat: "FAT", exfat: "exFAT", ntfs: "NTFS", ntfs3: "NTFS", ext2: "ext2", ext3: "ext3", ext4: "ext4",
                    btrfs: "Btrfs", xfs: "XFS", f2fs: "F2FS", hfsplus: "HFS+", apfs: "APFS", iso9660: "ISO 9660", udf: "UDF",
                    crypto_LUKS: "LUKS" }
    return names[type] || type || ""
}

// "sd" for SD/MMC cards, "usb" for USB sticks and disks, otherwise "disk".
function kind(drive) {
    if (!drive) return "disk"
    if (drive.bus === "sdio" || /(^|[^A-Za-z])(SD|MMC)([^A-Za-z]|$)/.test(drive.name)) return "sd"
    if (drive.bus === "usb") return "usb"
    return "disk"
}

function icon(drive) {
    const type = kind(drive)
    return type === "sd" ? "󰟜" : type === "usb" ? "󰕓" : "󰋊"
}

// Freedesktop icon name for notifications.
function notifyIcon(drive) {
    const type = kind(drive)
    return type === "sd" ? "media-flash-sd-mmc" : type === "usb" ? "drive-removable-media-usb" : "drive-harddisk"
}

function mounted(volume) {
    return !!volume && volume.mountPoints.length > 0
}

function mountedVolumes(drive) {
    return drive ? drive.volumes.filter(mounted) : []
}

// An encrypted volume that still needs its passphrase.
function locked(volume) {
    return !!volume && volume.encrypted === true && volume.unlocked !== true
}

function unlockedVolumes(drive) {
    return drive ? drive.volumes.filter(volume => volume.encrypted && volume.unlocked) : []
}

// The device that carries the filesystem: the cleartext device for an
// unlocked LUKS volume, the block itself otherwise.
function fsDevice(volume) {
    if (!volume) return ""
    return volume.encrypted && volume.unlocked && volume.clearDevice.length ? volume.clearDevice : volume.device
}

function driveTitle(drive) {
    if (!drive) return ""
    if (drive.volumes.length === 1 && drive.volumes[0].label.length) return drive.volumes[0].label
    if (drive.name.length) return drive.name
    const type = kind(drive)
    return type === "sd" ? "SD card" : type === "usb" ? "USB drive" : "External drive"
}

function driveSubtitle(drive) {
    if (!drive) return ""
    const parts = []
    if (drive.volumes.length === 1 && drive.volumes[0].label.length && drive.name.length) parts.push(drive.name)
    const size = formatSize(drive.size)
    if (size.length) parts.push(size)
    // A single volume shows its own mount state in the row below.
    const count = mountedVolumes(drive).length
    if (drive.volumes.length > 1) parts.push(count === 0 ? "Not mounted" : count + " of " + drive.volumes.length + " mounted")
    return parts.join(" · ")
}

function volumeTitle(volume) {
    if (!volume) return ""
    if (volume.label.length) return volume.label
    if (volume.encrypted) return "Encrypted volume"
    const size = formatSize(volume.size)
    return size.length ? size + " volume" : volume.device
}

function volumeSubtitle(volume) {
    if (!volume) return ""
    const parts = [formatSize(volume.size)]
    if (volume.encrypted) parts.push("Encrypted")
    // A locked volume only knows "crypto_LUKS", which "Encrypted" already says.
    if (volume.fsType !== "crypto_LUKS") parts.push(fsLabel(volume.fsType))
    if (volume.readOnly) parts.push("Read-only")
    parts.push(locked(volume) ? "Locked"
        : mounted(volume) ? "Mounted at " + volume.mountPoints[0]
        : volume.encrypted ? "Unlocked · Not mounted" : "Not mounted")
    return parts.filter(part => part.length).join(" · ")
}

// ---- MTP phones --------------------------------------------------------------

function phoneTitle(phone) {
    return phone ? phone.name : ""
}

function phoneSubtitle(phone) {
    if (!phone) return ""
    if (phone.mounted) return "MTP · Files open"
    return "MTP · Allow file access on the phone, then press Open"
}

function phoneIcon() {
    return "󰄜"
}

function phoneNotifyIcon() {
    return "phone"
}

function phoneConnectedBody(phone) {
    return phone ? phone.name + " · MTP" : ""
}

function connectedTitle(drive) {
    const type = kind(drive)
    return type === "sd" ? "SD card inserted" : type === "usb" ? "USB drive connected" : "Drive connected"
}

// Notification body: "STICK · SanDisk Ultra · 16 GB".
function connectedBody(drive) {
    if (!drive) return ""
    const parts = [driveTitle(drive)]
    if (drive.name.length && parts[0] !== drive.name) parts.push(drive.name)
    const size = formatSize(drive.size)
    if (size.length) parts.push(size)
    return parts.join(" · ")
}

function summary(drives, phones) {
    const list = drives || []
    const devices = phones || []
    if (!list.length && !devices.length) return "No removable drives"
    if (list.length === 1 && !devices.length) {
        const single = list[0]
        const state = mountedVolumes(single).length ? "Mounted"
            : single.volumes.every(locked) ? "Locked" : "Not mounted"
        return driveTitle(single) + " · " + state
    }
    if (!list.length && devices.length === 1) return phoneTitle(devices[0]) + " · " + (devices[0].mounted ? "Open" : "Not open")
    const parts = []
    if (list.length) parts.push(list.length + (list.length === 1 ? " drive" : " drives"))
    if (devices.length) parts.push(devices.length + (devices.length === 1 ? " phone" : " phones"))
    return parts.join(" and ") + " connected"
}

// action: mount, unmount, unlock, lock, powerOff. The unlock passphrase is
// never an argument: udisksctl reads it from stdin through --key-file.
function command(action, device) {
    if (!validDevice(device)) return null
    if (action === "mount") return ["udisksctl", "mount", "--block-device", device]
    if (action === "unmount") return ["udisksctl", "unmount", "--block-device", device]
    if (action === "unlock") return ["udisksctl", "unlock", "--block-device", device, "--key-file", "/dev/stdin"]
    if (action === "lock") return ["udisksctl", "lock", "--block-device", device]
    if (action === "powerOff") return ["udisksctl", "power-off", "--block-device", device]
    return null
}

// action: mount, unmount. gvfs mounts phones under $XDG_RUNTIME_DIR/gvfs.
function phoneCommand(action, uri) {
    if (!validMtpUri(uri)) return null
    if (action === "mount") return ["gio", "mount", uri]
    if (action === "unmount") return ["gio", "mount", "-u", uri]
    return null
}

// `gio mount` prints nothing on success; the mount point comes from the helper.
function phoneErrorText(action, name, output) {
    const value = String(output || "")
    if (/already mounted/i.test(value)) return ""
    if (/Unable to open MTP device|LIBMTP|No such (device|file or directory)|Device not found/i.test(value))
        return "“" + name + "” did not answer. Unlock the phone, allow file transfer and connect it again."
    if (/Operation not supported|not supported/i.test(value))
        return "“" + name + "” does not offer file transfer over MTP."
    let detail = value.trim().split("\n")[0] || ""
    detail = detail.replace(/^gio:\s*/, "").replace(/^[a-z]+:\/\/\S*:\s*/, "").replace(/^Error mounting location:\s*/, "")
    return "Could not " + (action === "unmount" ? "close" : "open") + " “" + name + "”" + (detail.length ? ": " + detail : ".")
}

function phoneHarmless(action, output) {
    const value = String(output || "")
    return (action === "mount" && /already mounted/i.test(value))
        || (action === "unmount" && /(not|isn't) mounted|Nothing to unmount/i.test(value))
}

// "Mounted /dev/sdb1 at /run/media/user/STICK" → the mount point.
function parseMountPoint(output) {
    const match = /^Mounted \S+ at (\/.*?)\s*$/m.exec(String(output || ""))
    return match ? match[1] : ""
}

// "Unlocked /dev/sdb1 as /dev/dm-0." → the cleartext device.
function parseCleartext(output) {
    const match = /^Unlocked \S+ as (\/dev\/\S+?)\.?\s*$/m.exec(String(output || ""))
    return match && validDevice(match[1]) ? match[1] : ""
}

// udisksctl errors are "Error unmounting /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: …".
function errorKind(output) {
    if (/target is busy|device is busy|DeviceBusy/i.test(output)) return "DeviceBusy"
    // cryptsetup wording differs by version; all of them mean the same thing.
    if (/incorrect passphrase|wrong passphrase|failed to activate device|no key available|no usable keyslot/i.test(output))
        return "WrongPassphrase"
    if (/is not unlocked|NotUnlocked/i.test(output)) return "NotUnlocked"
    const match = /org\.freedesktop\.UDisks2\.Error\.([A-Za-z]+)/.exec(String(output || ""))
    if (match) return match[1]
    if (/Error looking up object/i.test(output)) return "NotFound"
    return output && String(output).trim().length ? "Failed" : ""
}

// Unmounting something already unmounted (or mounting twice) is not a failure.
function harmless(action, output) {
    const type = errorKind(output)
    return (action === "unmount" && type === "NotMounted") || (action === "mount" && type === "AlreadyMounted")
        || (action === "unlock" && type === "AlreadyUnlocked") || (action === "lock" && type === "NotUnlocked")
}

function errorText(action, name, output) {
    const type = errorKind(output)
    const verb = action === "mount" ? "mount" : action === "unmount" ? "unmount"
        : action === "unlock" ? "unlock" : action === "lock" ? "lock" : "safely remove"
    if (type === "WrongPassphrase" && action === "unlock")
        return "Wrong passphrase for “" + name + "”. Try again."
    if (type === "DeviceBusy")
        return "“" + name + "” is in use. Close the files and apps that use it, then try again."
    if (type === "NotAuthorized" || type === "NotAuthorizedCanObtain" || type === "NotAuthorizedDismissed")
        return "Not allowed to " + verb + " “" + name + "”."
    if (type === "NotFound") return "“" + name + "” is no longer connected."
    if (type === "NotSupported") return "“" + name + "” cannot be " + (action === "powerOff" ? "powered off" : verb + "ed") + " here."
    const lines = String(output || "").trim().split("\n")
    let detail = lines[0] || ""
    // Keep the kernel/udisks reason after the last "Error …:" prefix.
    detail = detail.replace(/^Error [^:]*:\s*/, "").replace(/GDBus\.Error:[A-Za-z0-9_.]+:\s*/, "")
        .replace(/^Error [^:]*:\s*/, "").replace(/\s*\([a-z-]+-quark, \d+\)$/, "")
    return "Could not " + verb + " “" + name + "”" + (detail.length ? ": " + detail : ".")
}

// Actions run as `sh -c '"$@" 2>&1; printf "\n@exit %s\n" "$?"'` so the output
// and the exit code arrive together on stdout.
function wrap(argv) {
    return ["sh", "-c", "\"$@\" 2>&1; printf '\\n@exit %s\\n' \"$?\"", "sh"].concat(argv)
}

function parseResult(text) {
    const value = String(text || "")
    const match = /\n?@exit (\d+)\s*$/.exec(value)
    if (!match) return { code: -1, output: value.trim() }
    return { code: parseInt(match[1]), output: value.slice(0, match.index).trim() }
}

// ---- reading the list ------------------------------------------------------------
// DrivesService reads the list with the one-shot `drives.py list` whenever a
// watcher (`udisksctl monitor`, `gio mount -o`) prints a line, 400 ms after
// the last of a burst. What a read means - the list to show, events for what
// came and went, an error - is decided here, from the read before it; it used
// to be decided in a resident python process that held 20 MB for events that
// come a few times a week. A watcher's line only says "read again", and every
// read is the whole state, so a line too many costs a read and nothing else.
var DEBOUNCE_MS = 400
// After a failed read (udisksd restarting, a call that timed out while a disk
// hung): the next tries, the last one repeating.
var RETRY_MS = [2000, 5000, 15000, 30000, 60000]

// What the service starts from. `stale`: the shell has not shown this list
// (at the start, and after every error). `first`: no read has succeeded yet.
function emptyReadState() {
    return { drives: [], phones: [], mtp: true, stale: true, first: true, retries: 0 }
}

// The answer of one `drives.py list`: its last list or error line, as
// parseLine reads it. No such line (the helper crashed, no python3) is an
// error as well.
function readResult(text) {
    const lines = String(text || "").split("\n")
    for (let i = lines.length - 1; i >= 0; --i) {
        const message = parseLine(lines[i].trim())
        if (message && (message.kind === "drives" || message.kind === "error")) return message
    }
    return { kind: "error", message: "The drive list could not be read." }
}

// Events between two drive lists: added/removed drives, mounted/unmounted
// volumes (an unlock is a mount: the volume's mount points appear).
function diff(before, after) {
    const events = []
    const old = Object.create(null)
    const now = Object.create(null)
    for (const drive of before || []) old[drive.id] = drive
    for (const drive of after || []) now[drive.id] = drive
    for (const id in now) if (!(id in old)) events.push({ kind: "added", id: id })
    for (const id in old) if (!(id in now)) events.push({ kind: "removed", id: id })
    for (const id in now) {
        const previous = Object.create(null)
        for (const volume of (old[id] || { volumes: [] }).volumes) previous[volume.id] = volume
        for (const volume of now[id].volumes) {
            const was = !!previous[volume.id] && previous[volume.id].mountPoints.length > 0
            const is = volume.mountPoints.length > 0
            if (is && !was) events.push({ kind: "mounted", id: volume.id, drive: id })
            else if (was && !is) events.push({ kind: "unmounted", id: volume.id, drive: id })
        }
    }
    return events
}

// Events between two phone lists.
function diffPhones(before, after) {
    const events = []
    const old = Object.create(null)
    const now = Object.create(null)
    for (const phone of before || []) old[phone.id] = phone
    for (const phone of after || []) now[phone.id] = phone
    for (const id in now) if (!(id in old)) events.push({ kind: "phoneAdded", id: id })
    for (const id in old) if (!(id in now)) events.push({ kind: "phoneRemoved", id: id })
    for (const id in now) {
        if (!(id in old) || old[id].mounted === now[id].mounted) continue
        events.push({ kind: now[id].mounted ? "phoneMounted" : "phoneUnmounted", id: id })
    }
    return events
}

// One read, given the state of the reads before it → { state, say, events }:
// say "error" when it failed, "drives" when the shell has to show the list,
// "" when nothing changed. The shell shows the drives as unavailable from an
// error until it is shown the list again, and the list after a failed read
// is mostly the one from before - unchanged, it used to go unsaid, and
// "Drives are unavailable" stayed until something was plugged in. What is
// there at the first read that succeeds was not plugged in just now: no
// events for it (they would notify and open every drive the session starts
// with).
function settle(state, result) {
    const previous = state || emptyReadState()
    if (!result || result.kind !== "drives")
        return { state: Object.assign({}, previous, { stale: true, retries: previous.retries + 1 }), say: "error", events: [] }
    const events = previous.first ? []
        : diff(previous.drives, result.drives).concat(diffPhones(previous.phones, result.phones))
    const changed = events.length > 0 || result.mtp !== previous.mtp
        || JSON.stringify(result.drives) !== JSON.stringify(previous.drives)
        || JSON.stringify(result.phones) !== JSON.stringify(previous.phones)
    return {
        state: { drives: result.drives, phones: result.phones, mtp: result.mtp, stale: false, first: false, retries: 0 },
        say: changed || previous.stale ? "drives" : "",
        events: events
    }
}

// Milliseconds until the next try after this many failed reads in a row.
function retryDelay(retries) {
    return RETRY_MS[Math.min(Math.max(retries, 1), RETRY_MS.length) - 1]
}

// A watcher's line that is its banner, not news. The rest - an object added,
// a property changed, the daemon gone or back - asks for a read.
function watcherNews(line) {
    const text = String(line || "")
    return text.trim().length > 0 && !/^Monitoring /.test(text)
}

// The pause before a watcher that ended starts again: 5 s, doubling, and -1
// after the fifth end in a row (one that ran for a minute counts anew).
function watcherRestartDelay(failures) {
    if (failures < 1) return 0
    if (failures > 5) return -1
    return 5000 * Math.pow(2, failures - 1)
}

// ---- opening by itself -------------------------------------------------------------
// What a drive or phone that has just appeared does with Settings > Drives
// "open automatically": "open"; "wait" while the screen is locked - mounting
// it then has the kernel read a stick nobody at the screen chose, and the
// file manager's thumbnailers read its files, behind the lock (GNOME does not
// automount while locked either) - and it opens once the lock is gone; or
// "none". `openable`: not every volume of it is locked (a passphrase is
// needed first, so nothing is opened by itself). The notice shows either way.
function autoOpenAction(autoOpen, openable, screenLocked) {
    if (!autoOpen || !openable) return "none"
    return screenLocked ? "wait" : "open"
}
