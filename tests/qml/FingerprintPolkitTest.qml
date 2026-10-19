import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/fingerprint/FingerprintLogic.js" as F

// The reader for polkit's password dialogs only (FingerprintLogic, "the
// reader for admin prompts only"): which systems get the commands, how the
// file is read back, what the page says - and the commands run for real on
// copies of polkit's file (tests/fixtures/pam/polkit-1, as Arch and Fedora
// ship it), in both places it can be: in /etc (Fedora), on twice is one line
// above the include and off the file as it was; only in the vendor directory
// (Arch), on makes the copy in /etc with that line, the read follows the copy,
// and off takes the copy away again.
ShellRoot {
    id: root
    FileView { id: polkit; path: Qt.resolvedUrl("../fixtures/pam/polkit-1").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        T.eq(["arch", "fedora", "opensuse", ""].map(F.polkitSupported), [true, true, false, false], "Arch and Fedora only")
        T.eq([F.polkitOnCommand("opensuse"), F.polkitOffCommand(""), F.polkitReadCommand("opensuse")], ["", "", []], "nothing elsewhere")
        const read = F.polkitReadCommand("arch")
        T.eq([read[0], read[1], read.slice(3)], ["sh", "-c", ["sh", "/etc/pam.d/polkit-1", "/usr/lib/pam.d/polkit-1"]],
             "read: the file in /etc, else the vendor's")
        T.ok(F.polkitOnCommand("arch").indexOf("sudo sh -c ") === 0 && F.polkitOnCommand("arch").indexOf(F.POLKIT_PAM_LINE) > 0
             && F.polkitOnCommand("fedora") === F.polkitOnCommand("arch"), "the on command names the line and the file")
        T.ok(F.polkitOffCommand("arch").indexOf(" && if cmp -s ") > 0 && F.polkitOffCommand("fedora").indexOf("cmp") < 0
             && F.polkitOffCommand("fedora").indexOf("rm ") < 0, "only Arch's way back removes the copy")
        T.ok(F.POLKIT_PAM_LINE.indexOf("max-tries=1 timeout=10") > 0, "one touch, ten seconds")

        const shipped = polkit.text()
        T.eq(F.parsePolkit(shipped, 0), false, "as shipped: no reader")
        T.eq(F.parsePolkit(shipped.replace("auth       include", F.POLKIT_PAM_LINE + "\nauth       include"), 0), true, "with the line: the reader")
        T.eq(F.parsePolkit("#" + F.POLKIT_PAM_LINE + "\n" + shipped, 0), false, "a commented line is none")
        T.eq(F.parsePolkit("", 1), null, "a file that could not be read says nothing")

        T.eq(F.polkitState("opensuse", true, false), "unsupported", "openSUSE: not offered")
        T.eq(F.polkitState("arch", null, null), "unknown", "not read yet")
        T.eq(F.polkitState("arch", false, true), "system", "system-wide already")
        T.eq([F.polkitState("fedora", true, false), F.polkitState("arch", false, false)], ["on", "off"], "on and off")
        T.ok(F.polkitText("off").indexOf("password only") > 0 && F.polkitText("unknown") === "", "the words")

        // On twice, then off, in both places; sudo and the paths are the only
        // things changed.
        const local = command => command.split("sudo ").join("").split(F.POLKIT_VENDOR_PAM).join("vendor/polkit-1")
            .split(F.POLKIT_PAM).join("etc/polkit-1")
        pamRun.expected = shipped
        pamRun.command = ["bash", "-c", pamRun.script, "bash", polkit.path,
                          local(F.polkitOnCommand("fedora")), local(F.polkitOffCommand("fedora")),
                          local(F.polkitOnCommand("arch")), local(F.polkitOffCommand("arch")), read[2]]
        pamRun.running = true
    }

    Process {
        id: pamRun
        property string expected: ""
        readonly property string script: 'd=$(mktemp -d) || exit 1; trap \'rm -rf "$d"\' EXIT; cd "$d" && mkdir etc vendor || exit 1\n'
            + 'mark() { printf "%s\\n" "-- $1"; }\n'
            + 'cp "$1" etc/polkit-1 || exit 1\n'
            + 'eval "$2" && eval "$2" || exit 1\n'
            + 'mark fedora-on; cat etc/polkit-1\n'
            + 'eval "$3" || exit 1\n'
            + 'mark fedora-off; cat etc/polkit-1\n'
            + 'rm etc/polkit-1 && cp "$1" vendor/polkit-1 || exit 1\n'
            + 'mark arch-read; sh -c "$6" sh etc/polkit-1 vendor/polkit-1\n'
            + 'eval "$4" && eval "$4" || exit 1\n'
            + 'mark arch-on; cat etc/polkit-1\n'
            + 'mark arch-read-on; sh -c "$6" sh etc/polkit-1 vendor/polkit-1\n'
            + 'mark arch-vendor; cat vendor/polkit-1\n'
            + 'eval "$5" || exit 1\n'
            + 'mark arch-off; ls etc\n'
            + 'mark end\n'
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = {}
                let name = ""
                for (const line of text.split("\n")) {
                    const mark = /^-- ([a-z-]+)$/.exec(line)
                    if (mark) { name = mark[1]; parts[name] = []; continue }
                    if (name.length) parts[name].push(line)
                }
                const part = key => parts[key] ? parts[key].join("\n") + "\n" : null
                T.ok(parts["end"] !== undefined, "the commands ran")
                const want = pamRun.expected.replace("\nauth       include", "\n" + F.POLKIT_PAM_LINE + "\nauth       include")
                T.eq(part("fedora-on"), want, "Fedora, on twice: exactly one line, directly above the auth include, the rest unchanged")
                T.eq(F.parsePolkit(part("fedora-on"), 0), true, "and the shell reads it back as on")
                T.eq(part("fedora-off"), pamRun.expected, "off: the file as it shipped, still in /etc")
                T.eq(F.parsePolkit(part("fedora-off"), 0), false, "which the shell reads back as off")
                T.eq(part("arch-read"), pamRun.expected, "Arch: the vendor's file is read while /etc has none")
                T.eq(part("arch-on"), want, "on, twice: a copy in /etc with exactly that line")
                T.eq(part("arch-read-on"), want, "which the read follows")
                T.eq(part("arch-vendor"), pamRun.expected, "and the vendor's file is left as it is")
                T.eq(part("arch-off"), "\n", "off: the copy is gone, PAM reads the vendor's file again")
                T.finish("FingerprintPolkitTest")
            }
        }
    }
}
