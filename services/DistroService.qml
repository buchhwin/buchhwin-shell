pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "distro/DistroLogic.js" as Logic

// The distribution the session runs on, read once from /etc/os-release. Pages
// ask this for the commands they show instead of naming dnf, zypper or pacman
// themselves, so Fedora, openSUSE and Arch run the same QML.
Singleton {
    id: root

    property var info: ({})
    property bool known: false
    readonly property string family: Logic.family(info)
    readonly property string name: info.NAME || ""
    readonly property string packageTool: Logic.packageTool(family)
    readonly property string fingerprintOffCommand: Logic.fingerprintOffCommand(family)
    readonly property string fingerprintOnCommand: Logic.fingerprintOnCommand(family)
    readonly property string packagesDescription: Logic.packagesDescription(info)
    readonly property bool upgradesInTerminal: Logic.upgradesInTerminal(family)

    function installHint(package_) { return Logic.installHint(family, package_) }

    FileView {
        path: "/etc/os-release"
        printErrors: false
        onLoaded: { root.info = Logic.parseOsRelease(text()); root.known = true }
        onLoadFailed: root.known = true
    }
}
