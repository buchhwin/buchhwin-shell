.pragma library

// The distribution the shell runs on, from /etc/os-release, and the few
// strings that differ between them. Fedora and openSUSE Leap share every QML
// file; what a page tells the user to type (the package manager, the PAM
// switch) comes from here and nowhere else. The installer has the same
// knowledge in install/lib/distro.sh. Unit tested (tests/qml/DistroTest.qml).

var FAMILIES = ["fedora", "opensuse"]

// Package names for the install hints the interface shows. Only what a hint
// names; the installer keeps the full lists (install/packages/).
var PACKAGES = {
    fedora: { "wf-recorder": "wf-recorder", "hyprland-guiutils": "hyprland-guiutils" },
    opensuse: { "wf-recorder": "wf-recorder" }
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

// "fedora", "opensuse" or "" from the parsed file. ID first, ID_LIKE as the
// fallback, so a respin that keeps the base's package manager still counts.
function family(info) {
    const ids = [String((info || {}).ID || "")].concat(String((info || {}).ID_LIKE || "").split(/\s+/))
    for (const id of ids) {
        if (id === "fedora") return "fedora"
        if (id === "opensuse" || id.indexOf("opensuse-") === 0 || id === "suse") return "opensuse"
    }
    return ""
}

function packageTool(family_) {
    return family_ === "fedora" ? "dnf" : family_ === "opensuse" ? "zypper" : ""
}

// "sudo dnf install X" / "sudo zypper install X"; "" when the package has no
// name on this distribution or the distribution is unknown.
function installCommand(family_, package_) {
    const tool = packageTool(family_)
    const name = (PACKAGES[family_] || {})[package_]
    return tool && name ? "sudo " + tool + " install " + name : ""
}

// Readable "Install with: …", or a neutral sentence where there is no package.
function installHint(family_, package_) {
    const command = installCommand(family_, package_)
    return command ? "Install with: " + command : "Install " + package_ + " with your package manager."
}

// The one host command that takes pam_fprintd out of the system-wide PAM
// stack. Fedora generates it with authselect, openSUSE with pam-config.
function fingerprintOffCommand(family_) {
    if (family_ === "fedora") return "sudo authselect disable-feature with-fingerprint"
    if (family_ === "opensuse") return "sudo pam-config --delete --fprintd"
    return ""
}

// What Settings > Updates calls the system packages.
function packagesDescription(info) {
    const family_ = family(info)
    const name = String((info || {}).NAME || "").trim() || "System"
    const tool = packageTool(family_)
    return tool ? name + " packages from " + tool + ". Discover asks for the administrator password before installing."
        : "System packages. Discover asks for the administrator password before installing."
}
