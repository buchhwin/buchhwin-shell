.pragma library

// The distribution the shell runs on, from /etc/os-release, and the few
// strings that differ between them. Fedora, openSUSE Leap and Arch share
// every QML file; what a page tells the user to type (the package manager, the PAM
// switch) comes from here and nowhere else. The installer has the same
// knowledge in install/lib/distro.sh. Unit tested (tests/qml/DistroTest.qml).

var FAMILIES = ["fedora", "opensuse", "arch"]

// Package names for the install hints the interface shows. Only what a hint
// names; the installer keeps the full lists (install/packages/).
var PACKAGES = {
    fedora: { "wf-recorder": "wf-recorder", "ollama": "ollama", "hyprland-guiutils": "hyprland-guiutils" },
    opensuse: { "wf-recorder": "wf-recorder" },
    arch: { "wf-recorder": "wf-recorder", "ollama": "ollama", "hyprland-guiutils": "hyprland-guiutils", "qalc": "libqalculate" }
}

// KEY=value lines; values may be quoted. Unknown keys are kept, comments and
// broken lines are not.
function parseOsRelease(text) {
    const result = {}
    for (const line of String(text || "").split("\n")) {
        const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim())
        if (!match) continue
        let value = match[2]
        if (/^".*"$/.test(value) || /^'.*'$/.test(value)) value = value.slice(1, -1)
        result[match[1]] = value.replace(/\\(["\\$`])/g, "$1")
    }
    return result
}

// "fedora", "opensuse", "arch" or "" from the parsed file. ID first, ID_LIKE
// as the fallback, so a respin that keeps the base's package manager still
// counts (EndeavourOS, CachyOS: ID_LIKE=arch).
function family(info) {
    const ids = [String((info || {}).ID || "")].concat(String((info || {}).ID_LIKE || "").split(/\s+/))
    for (const id of ids) {
        if (id === "fedora") return "fedora"
        if (id === "opensuse" || id.indexOf("opensuse-") === 0 || id === "suse") return "opensuse"
        if (id === "arch") return "arch"
    }
    return ""
}

function packageTool(family_) {
    return family_ === "fedora" ? "dnf" : family_ === "opensuse" ? "zypper" : family_ === "arch" ? "pacman" : ""
}

// "sudo dnf install X" / "sudo zypper install X" / "sudo pacman -S X"; ""
// when the package has no name on this distribution or the distribution is
// unknown.
function installCommand(family_, package_) {
    const tool = packageTool(family_)
    const name = (PACKAGES[family_] || {})[package_]
    if (!tool || !name) return ""
    return "sudo " + tool + (tool === "pacman" ? " -S " : " install ") + name
}

// Readable "Install with: …", or a neutral sentence where there is no package.
function installHint(family_, package_) {
    const command = installCommand(family_, package_)
    return command ? "Install with: " + command : "Install " + package_ + " with your package manager."
}

// The one host command that takes pam_fprintd out of the system-wide PAM
// stack. Fedora generates it with authselect, openSUSE with pam-config. Arch
// has neither: the line was added by hand, to the lock's own buchhwin-lock
// (fingerprintOnCommand below, where it belongs) or to system-auth, so the
// command comments it out in both - only an active auth line naming
// pam_fprintd, the same lines FingerprintLogic.systemFingerprintPam reads as
// on: indented or not, and not where the name is only in a trailing comment.
// Taking the # away again is the way back.
function fingerprintOffCommand(family_) {
    if (family_ === "fedora") return "sudo authselect disable-feature with-fingerprint"
    if (family_ === "opensuse") return "sudo pam-config --delete --fprintd"
    if (family_ === "arch") return "sudo sed -i '/^\\s*auth\\s[^#]*pam_fprintd\\.so/s/^/#/' /etc/pam.d/buchhwin-lock /etc/pam.d/system-auth"
    return ""
}

// Arch only: the command that gives the lock screen the reader, as Settings >
// Lock Screen offers it. The line goes into /etc/pam.d/buchhwin-lock directly
// above its `include system-auth`, never into system-auth itself - SDDM and
// sudo include that too and would wait for a finger first, and a finger login
// cannot open the wallet (FingerprintLogic, "Arch"). From the first active
// pam_fprintd line to the end of the file sed branches past the insert, so
// with the line already above the include a second run adds nothing, and
// nothing else in the file changes. Fedora and openSUSE have their own tools.
var FINGERPRINT_PAM_LINE = "auth       sufficient   pam_fprintd.so"
function fingerprintOnCommand(family_) {
    if (family_ !== "arch") return ""
    return "sudo sed -i '/^\\s*auth\\s[^#]*pam_fprintd\\.so/,$b; /^auth\\s\\+include\\s\\+system-auth\\s*$/i "
        + FINGERPRINT_PAM_LINE + "' /etc/pam.d/buchhwin-lock"
}

// Arch upgrades the whole system at once, in a terminal (pacman or an AUR
// helper); Discover cannot install pacman's packages without PackageKit.
// Everywhere else system packages go through Discover.
function upgradesInTerminal(family_) {
    return family_ === "arch"
}

// What Settings > Updates calls the system packages.
function packagesDescription(info) {
    const family_ = family(info)
    const name = String((info || {}).NAME || "").trim() || "System"
    const tool = packageTool(family_)
    if (upgradesInTerminal(family_))
        return name + " packages from " + tool + " and the AUR. The upgrade runs in a terminal and asks for the administrator password there."
    return tool ? name + " packages from " + tool + ". Discover asks for the administrator password before installing."
        : "System packages. Discover asks for the administrator password before installing."
}
