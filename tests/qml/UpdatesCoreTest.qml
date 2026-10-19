import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/updates/UpdatesLogic.js" as U

// Settings > Updates around the shell itself: the "Shell core" tag and its
// note, Arch's news before the upgrade and the .pacnew files after it (from
// tests/fixtures/updates-arch-extras.txt), what updates.json keeps of them,
// and the version line and recent changes Settings > About shows.
ShellRoot {
    FileView { id: extras; path: Qt.resolvedUrl("../fixtures/updates-arch-extras.txt").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // ---- shell core ------------------------------------------------------------
        T.eq(["hyprland", "hyprland-git", "aquamarine", "hyprutils", "xdg-desktop-portal-hyprland", "hyprlang"].map(U.coreKind),
             ["session", "session", "session", "session", "session", "session"], "the compositor and its libraries")
        T.eq(["quickshell", "quickshell-git", "qt6-base", "qt6-declarative", "qt6-wayland", "qt6-qtbase", "qt6-qtdeclarative",
              "libQt6Quick6"].map(U.coreKind), ["shell", "shell", "shell", "shell", "shell", "shell", "shell", "shell"],
             "Quickshell and its Qt, as Arch, Fedora and openSUSE name them")
        T.eq(["firefox", "qt6-svg", "hyprpaper", "quickshell-extra", "", "linux"].map(U.coreKind), ["", "", "", "", "", ""], "anything else")
        const result = { packages: [{ name: "linux" }, { name: "qt6-base" }, { name: "quickshell" }], flatpaks: [] }
        T.eq(U.corePackages(result).map(item => item.name), ["qt6-base", "quickshell"], "the core packages of an upgrade")
        T.eq(U.coreNote(result), "Shell core in this upgrade: qt6-base, quickshell. Restart the shell afterwards (Super+Ctrl+R). The shell checks itself after its next start.", "shell only: a restart")
        const session = { packages: ["hyprland", "aquamarine", "hyprutils", "hyprlang", "quickshell", "qt6-base"].map(name => ({ name: name })) }
        T.eq(U.coreNote(session), "Shell core in this upgrade: hyprland, aquamarine, hyprutils, hyprlang and 2 more. Log out and back in afterwards - the compositor keeps running the old version until then. The shell checks itself after its next start.", "the compositor: log in again")
        T.eq(U.coreNote({ packages: [{ name: "linux" }] }), "", "no note without one")

        // ---- Arch news and .pacnew --------------------------------------------------------
        const parsed = U.parseExtras(extras.text())
        T.eq(parsed.news.map(item => [item.date, item.title]),
             [["2026-10-02", "example-package >= 2.0-1 update requires manual intervention"], ["2026-09-14", "Sample news without a body"]], "news titles")
        T.eq(parsed.news[0].summary, "The example-package package moved its configuration to /etc/example.d. Move your changes over before upgrading.", "first paragraph")
        T.eq(parsed.news[1].summary, "", "and none without a body")
        T.eq(parsed.pacnew, ["/etc/pacman.conf.pacnew", "/etc/locale.gen.pacnew"], "pacnew files")
        T.eq([parsed.newsKnown, parsed.pacnewKnown], [true, true], "both known")
        T.eq(U.parseNews("No new news\n"), [], "no news")
        T.eq(U.parseExtras("@news 1\nNo new news\n@end 0").newsKnown, true, "an exit 1 with no news is an answer")
        T.eq(U.parseExtras("@news 1\n\n@news-stderr 1\nno new news\n@end 0").newsKnown, true, "and so is paru's, said on stderr")
        T.eq(U.parseExtras("@news 1\n\n@news-stderr 1\nerror: failed to fetch\n@end 0").newsKnown, false, "a failed fetch is none")
        T.eq(U.parseExtras("@dnf 0\n{}\n@end 0"), U.emptyExtras(), "another system has neither")
        T.eq(U.parsePacnew("/etc/a.pacsave\n/etc/b.pacsave.1\n/etc/c.conf\nrelative.pacnew\n/etc/d.pacorig\n"),
             ["/etc/a.pacsave", "/etc/b.pacsave.1", "/etc/d.pacorig"], "only paths of upgrade copies")
        const kept = U.mergeExtras(parsed, U.parseExtras("@dnf 0\n{}\n@end 0"))
        T.eq([kept.news.length, kept.pacnew.length], [2, 2], "a check without the sections keeps the last answer")
        const cleared = U.mergeExtras(parsed, U.parseExtras("@news 1\n\n@news-stderr 1\nno new news\n@pacnew 0\n\n@end 0"))
        T.eq([cleared.news.length, cleared.pacnew.length], [0, 0], "an answer of none clears them")
        T.eq(U.pacnewNote(["/etc/a.pacnew"]), "1 configuration file from upgrades waits beside the system's own (.pacnew). Look at them and merge what you want with:", "one file")
        T.eq(U.pacnewNote([]), "", "no note without one")
        T.eq(U.PACDIFF_COMMAND, "pacdiff -s", "pacdiff as the user, sudo where it replaces")

        // updates.json keeps them, checked.
        const state = U.parseState(U.serializeState(Object.assign(U.parseState(""), { extras: parsed })))
        T.eq(state.extras, parsed, "state round trip")
        T.eq(U.parseState(JSON.stringify({ version: 1, extras: { news: [{ date: 1 }, { date: "2026-01-01", title: "t", summary: 5 }], pacnew: ["../x", "/etc/y.pacnew"] } })).extras,
             { news: [{ date: "2026-01-01", title: "t", summary: "" }], pacnew: ["/etc/y.pacnew"], newsKnown: false, pacnewKnown: false },
             "what a state file holds is checked")
        T.eq(U.parseState(JSON.stringify({ version: 1 })).extras, undefined, "an old state file has none")

        // ---- the shell's version (Settings > About) --------------------------------------------
        const log = U.parseLog("490661a\t2026-10-19\tWorkspaces that stay until closed\ne5a68ce\t2026-10-19\tDo Not Disturb ends with the mode\nbad line\nzzz\t2026-10-01\tnot a hash\n")
        T.eq(log.map(item => item.hash), ["490661a", "e5a68ce"], "commits from git log")
        T.eq(log[1].subject, "Do Not Disturb ends with the mode", "with their subjects")
        const now = new Date(2026, 9, 20).getTime()
        T.eq(U.versionLine(log, now), "490661a · Oct 19", "the version line, the day as the Updates page writes one")
        T.eq(U.shortDate("2025-12-31", now), "Dec 31 2025", "another year says so")
        T.eq([U.versionLine([], now), U.shortDate("19.10.2026", now)], ["", ""], "nothing for nothing")
        T.eq(U.logCommand("/x/shell"), ["git", "-C", "/x/shell", "log", "-10", "--format=%h%x09%cs%x09%s"], "one git call")
        T.finish("UpdatesCoreTest")
    }
}
