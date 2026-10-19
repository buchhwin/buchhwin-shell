.pragma library

// Network drives, as the VPN popup lists them: the shares that are mounted
// and the automount points that would mount one when opened, read from
// /proc/self/mountinfo and from nothing else. A path under an automount is
// never looked at - not listed, not tested, not opened - while no VPN is up:
// touching one with its server out of reach starts a mount that hangs the
// caller (Dolphin hung about a minute), and a few such tries leave the
// automount failed until an administrator resets it.

// File systems that live on another machine. An automount point itself is
// "autofs" until something mounts on it.
var NETWORK_TYPES = ["cifs", "smb3", "nfs", "nfs4", "fuse.sshfs", "davfs"]

// Automount points of the system's own, never a drive: systemd's binfmt_misc
// under /proc, an EFI or boot partition mounted on first use.
var SYSTEM_PREFIXES = ["/proc", "/sys", "/dev", "/run", "/boot", "/efi"]

// mountinfo writes a space, a tab, a newline and a backslash in a path as
// octal escapes (\040, \011, \012, \134).
function unescape(text) {
    return String(text || "").replace(/\\([0-7]{3})/g, (match, code) => String.fromCharCode(parseInt(code, 8)))
}

// The lines of /proc/self/mountinfo → [{ point, fstype, source }]. A line is
// "ID PARENT MAJ:MIN ROOT POINT OPTIONS [OPTIONAL...] - FSTYPE SOURCE SUPER";
// the optional fields end at the lone "-".
function parseMountinfo(text) {
    const mounts = []
    for (const line of String(text || "").split("\n")) {
        const fields = line.trim().split(" ")
        const dash = fields.indexOf("-")
        if (dash < 6 || fields.length < dash + 3) continue
        mounts.push({ point: unescape(fields[4]), fstype: fields[dash + 1], source: unescape(fields[dash + 2]) })
    }
    return mounts
}

function isSystemPoint(point) {
    const path = String(point || "")
    if (path === "/" || !path.startsWith("/")) return true
    return SYSTEM_PREFIXES.some(prefix => path === prefix || path.startsWith(prefix + "/"))
}

function isNetwork(fstype) {
    return NETWORK_TYPES.indexOf(String(fstype || "")) >= 0
}

// The last part of a path: "/mnt/zim/H" → "H".
function nameOf(point) {
    const parts = String(point || "").split("/").filter(part => part.length)
    return parts.length ? parts[parts.length - 1] : String(point || "")
}

// Mounts → the drives to list, by path: [{ point, name, mounted, automount }].
// An automount point with a network share on it is mounted; one with nothing
// on it is not; one with a local file system on it (a USB disk the system
// mounts on first use) is not a network drive and left out. A network share
// mounted without an automount (a plain fstab line) is listed as mounted.
function shares(mounts) {
    const byPoint = {}
    for (const mount of mounts || []) {
        if (!mount || isSystemPoint(mount.point)) continue
        const entry = byPoint[mount.point] || { automount: false, network: false, local: false }
        if (mount.fstype === "autofs") entry.automount = true
        else if (isNetwork(mount.fstype)) entry.network = true
        else entry.local = true
        byPoint[mount.point] = entry
    }
    return Object.keys(byPoint).sort()
        .filter(point => byPoint[point].network || (byPoint[point].automount && !byPoint[point].local))
        .map(point => ({ point: point, name: nameOf(point), mounted: byPoint[point].network,
                         automount: byPoint[point].automount }))
}

// "H", "H and I", "H, I and X".
function names(list) {
    const words = (list || []).map(share => share.name)
    if (words.length <= 1) return words.join("")
    return words.slice(0, -1).join(", ") + " and " + words[words.length - 1]
}

// What the list says under its title, with no VPN up or with one.
// → { line, warning }: `warning` the hang to expect when a share is mounted
// while no tunnel is up (if its server is out of reach, everything that
// touches it waits); otherwise `line` says which drives need the VPN.
function summary(list, vpnUp) {
    const all = list || []
    if (!all.length) return { line: "", warning: "" }
    if (vpnUp === true)
        return { line: all.some(share => !share.mounted) ? "A drive mounts when it is opened." : "", warning: "" }
    const mounted = all.filter(share => share.mounted)
    if (mounted.length)
        return { line: "", warning: names(mounted) + (mounted.length === 1 ? " is" : " are")
                 + " mounted with no VPN up. If the server is out of reach, the file manager hangs on "
                 + (mounted.length === 1 ? "it." : "them.") }
    return { line: names(all) + (all.length === 1 ? " needs" : " need") + " the VPN. Opening "
             + (all.length === 1 ? "it" : "one") + " without it can hang the file manager.", warning: "" }
}

// The row's line under the name.
function status(share) {
    if (!share) return ""
    return share.point + " · " + (share.mounted ? "Mounted" : "Not mounted")
}

// Whether a drive gets an Open button: only with a VPN up, and only for an
// absolute path - the file manager goes there and mounts it.
function openable(share, vpnUp) {
    return vpnUp === true && !!share && String(share.point || "").startsWith("/")
}
