import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/distro/DistroLogic.js" as D

ShellRoot {
    Component.onCompleted: {
        // os-release as the supported systems ship it.
        const fedora = D.parseOsRelease('NAME="Fedora Linux"\nVERSION_ID=44\nID=fedora\nPRETTY_NAME="Fedora Linux 44 (KDE Plasma Desktop Edition)"\n')
        const leap = D.parseOsRelease('NAME="openSUSE Leap"\nVERSION="16.0"\nID="opensuse-leap"\nID_LIKE="suse opensuse"\nVERSION_ID="16.0"\n')
        T.eq([fedora.ID, fedora.NAME, fedora.VERSION_ID], ["fedora", "Fedora Linux", "44"], "Fedora parsed, quotes dropped")
        T.eq([leap.ID, leap.ID_LIKE, leap.VERSION_ID], ["opensuse-leap", "suse opensuse", "16.0"], "Leap parsed")
        T.eq(D.parseOsRelease("# comment\nbroken line\nX='single'\n"), { X: "single" }, "comments and broken lines dropped")
        const arch = D.parseOsRelease('NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling\n')
        T.eq([arch.ID, arch.NAME], ["arch", "Arch Linux"], "Arch parsed")

        T.eq([D.family(fedora), D.family(leap)], ["fedora", "opensuse"], "family from ID")
        T.eq(D.family({ ID: "nobara", ID_LIKE: "fedora" }), "fedora", "family from ID_LIKE")
        T.eq(D.family({ ID: "opensuse-tumbleweed" }), "opensuse", "any openSUSE")
        T.eq([D.family(arch), D.family({ ID: "endeavouros", ID_LIKE: "arch" })], ["arch", "arch"], "Arch and its derivatives")
        T.eq([D.family({ ID: "debian" }), D.family({}), D.family(null)], ["", "", ""], "unknown is empty")

        T.eq([D.packageTool("fedora"), D.packageTool("opensuse"), D.packageTool("arch"), D.packageTool("")],
             ["dnf", "zypper", "pacman", ""], "package tool")
        T.eq(D.installCommand("arch", "wf-recorder"), "sudo pacman -S wf-recorder", "Arch install command")
        T.eq(D.installCommand("arch", "hyprland-guiutils"), "sudo pacman -S hyprland-guiutils", "Arch packages Hyprland's dialogs")
        T.eq([D.installCommand("arch", "ollama"), D.installCommand("fedora", "ollama"), D.installCommand("opensuse", "ollama")],
             ["sudo pacman -S ollama", "sudo dnf install ollama", ""], "Ollama for the assistant, where it is packaged")
        T.eq(D.installCommand("fedora", "wf-recorder"), "sudo dnf install wf-recorder", "Fedora install command")
        T.eq(D.installCommand("opensuse", "wf-recorder"), "sudo zypper install wf-recorder", "openSUSE install command")
        T.eq(D.installCommand("opensuse", "hyprland-guiutils"), "", "no package, no command")
        T.eq(D.installHint("fedora", "wf-recorder"), "Install with: sudo dnf install wf-recorder", "hint")
        T.eq(D.installHint("", "wf-recorder"), "Install wf-recorder with your package manager.", "hint without a distribution")

        T.eq(D.fingerprintOffCommand("fedora"), "sudo authselect disable-feature with-fingerprint", "Fedora PAM switch")
        T.eq(D.fingerprintOffCommand("opensuse"), "sudo pam-config --delete --fprintd", "openSUSE PAM switch")
        T.eq(D.fingerprintOffCommand("arch"), "sudo sed -i '/^\\s*auth\\s[^#]*pam_fprintd\\.so/s/^/#/' /etc/pam.d/buchhwin-lock /etc/pam.d/system-auth",
             "Arch PAM switch: the hand-made line is commented out in the lock's file and in system-auth, indented too")
        T.eq(D.fingerprintOffCommand(""), "", "no switch without a distribution")
        // Arch turns the reader on by hand, for the lock screen only: the line
        // goes above the include of buchhwin-lock, never into system-auth
        // (SDDM and sudo include that). FingerprintTest runs it on a copy.
        T.eq(D.fingerprintOnCommand("arch"),
             "sudo sed -i '/^\\s*auth\\s[^#]*pam_fprintd\\.so/,$b; /^auth\\s\\+include\\s\\+system-auth\\s*$/i auth       sufficient   pam_fprintd.so' /etc/pam.d/buchhwin-lock",
             "Arch: the reader into the lock's own PAM file")
        T.ok(D.fingerprintOnCommand("arch").indexOf("/etc/pam.d/system-auth") < 0, "and nowhere near system-auth")
        T.eq([D.fingerprintOnCommand("fedora"), D.fingerprintOnCommand("opensuse"), D.fingerprintOnCommand("")],
             ["", "", ""], "Fedora and openSUSE have their own tools")
        T.eq([D.upgradesInTerminal("arch"), D.upgradesInTerminal("fedora"), D.upgradesInTerminal("opensuse")],
             [true, false, false], "only Arch upgrades in a terminal")
        T.eq(D.packagesDescription(fedora), "Fedora Linux packages from dnf. Discover asks for the administrator password before installing.",
             "Fedora updates description")
        T.eq(D.packagesDescription(leap), "openSUSE Leap packages from zypper. Discover asks for the administrator password before installing.",
             "Leap updates description")
        T.eq(D.packagesDescription(arch), "Arch Linux packages from pacman and the AUR. The upgrade runs in a terminal and asks for the administrator password there.",
             "Arch updates description")
        T.finish("DistroTest")
    }
}
