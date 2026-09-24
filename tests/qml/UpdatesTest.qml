import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/updates/UpdatesLogic.js" as U

ShellRoot {
    // Synthetic report in the format of scripts/updates-check.sh.
    FileView { id: sample; path: Qt.resolvedUrl("../fixtures/updates-report.txt").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        const H = U.HOUR

        // Sections
        const sections = U.parseSections("noise\n@dnf 100\n{}\n@dnf-stderr 1\nline one\nline two\n\n@end 0\n")
        T.eq(Object.keys(sections), ["dnf", "dnf-stderr", "end"], "section names")
        T.eq(sections["dnf"], { code: 100, text: "{}" }, "section code and text")
        T.eq(sections["dnf-stderr"].text, "line one\nline two", "multi-line section trimmed")
        T.eq(U.parseSections(""), {}, "empty report")
        T.ok(U.succeeded({ code: 100 }) && U.succeeded({ code: 0 }) && !U.succeeded({ code: 1 }) && !U.succeeded(undefined), "dnf exit codes")

        // dnf5 JSON
        T.eq(U.parseDnf("{}"), [], "no upgrades is an empty object")
        T.eq(U.parseDnf(""), [], "empty output")
        T.eq(U.parseDnf("Unknown argument \"--json\""), null, "non-JSON output")
        T.eq(U.parseDnf("[1]"), null, "array is not a dnf result")
        T.eq(U.parseDnf(JSON.stringify({ upgrades: [
            { name: "a", arch: "x86_64", evr: "0:1.0-1", repository: "updates" },
            { name: "a", arch: "x86_64", evr: "1.0-2", repository: "updates" },
            { name: "bad name", arch: "x86_64", evr: "1" }, null,
            { name: "b", arch: "noarch", evr: "2:3-4" }] })),
            [{ name: "a", arch: "x86_64", version: "1.0-1", repository: "updates" },
             { name: "b", arch: "noarch", version: "2:3-4", repository: "" }], "upgrades parsed, duplicates and junk dropped")
        T.eq(U.cleanEvr("(none):26.1.8-1.fc44"), "26.1.8-1.fc44", "rpm epoch placeholder")
        T.eq(U.cleanEvr("1:3.5.3-2.fc44"), "1:3.5.3-2.fc44", "real epoch kept")
        T.eq(U.splitNevra("sudo-1.9.17-3.p2.fc44.x86_64"), { name: "sudo", arch: "x86_64", version: "1.9.17-3.p2.fc44" }, "nevra with dotted release")
        T.eq(U.splitNevra("openssl-libs-1:3.5.4-1.fc44.x86_64").name, "openssl-libs", "nevra with epoch")
        T.eq(U.splitNevra("broken"), null, "invalid nevra")
        T.eq(U.parseAdvisories("[]"), {}, "no advisories")
        T.eq(U.parseAdvisories("oops"), {}, "broken advisories")
        T.eq(U.parseInstalled("a.x86_64\t(none):1-1\njunk\n\nb.noarch\t2:3-4"), { "a.x86_64": "1-1", "b.noarch": "2:3-4" }, "installed versions")

        // Full report
        const result = U.parseReport(sample.text())
        T.ok(result.packagesKnown && result.flatpaksKnown && result.checked, "report known and checked")
        T.eq([result.packageError, result.flatpakError, result.offline], ["", "", false], "no errors")
        T.eq(result.packages.map(item => item.name),
             ["sudo", "openssl-libs", "example-browser", "kernel-core", "libexample", "mesa-dri-drivers", "python3-example"],
             "security first by severity, then by name")
        const sudo = result.packages[0]
        T.eq([sudo.security, sudo.severity, sudo.advisory], [true, "critical", "FEDORA-2026-0000000003"], "most severe advisory wins")
        T.eq(result.packages[1].from + " → " + result.packages[1].to, "1:3.5.3-2.fc44 → 1:3.5.4-1.fc44", "epoch versions")
        T.eq(result.packages.find(item => item.name === "mesa-dri-drivers").security, false, "bugfix is not security")
        T.eq(result.packages.find(item => item.name === "python3-example").from, "", "missing installed version")
        T.eq(U.securityCount(result), 2, "security count")
        T.eq(result.flatpaks.map(item => item.name + "/" + item.installation),
             ["Example Chat/system", "Example Office/user", "Mesa/system", "Mesa/user"], "apps before runtimes")
        T.eq(result.flatpaks[0].from, "1.0.160", "installed flatpak version")
        T.eq(result.flatpaks[2].from, "26.2.1", "installed version per installation")
        T.eq(U.userFlatpaks(result).length, 2, "user flatpaks")
        T.eq(U.total(result), 11, "total")
        T.eq(U.installationsText(result), "2 system · 2 user", "mixed installations")
        T.eq(U.installationsText({ flatpaks: [{ installation: "system" }] }), "System installation", "system only")
        T.eq(U.installationsText({ flatpaks: [{ installation: "user" }] }), "User installation", "user only")
        T.eq(U.installationsText({ flatpaks: [] }), "", "no flatpaks")

        // Labels
        T.eq(U.packageSubtitle(result.packages[2]), "2.4.0-1 → 2.4.1-1 · example-browser", "package subtitle")
        T.eq(U.packageSubtitle(result.packages[6]), "0.9.2-1.fc44 · updates", "package without installed version")
        T.eq(U.flatpakSubtitle(result.flatpaks[0]), "1.0.160 · new build · App · System", "same version is a new build")
        T.eq(U.flatpakSubtitle(result.flatpaks[1]), "9.4.0 → 9.5.0 · App · User", "flatpak subtitle")
        T.eq(U.flatpakSubtitle({ from: "", to: "", branch: "25.08-extra", kind: "runtime", installation: "user" }), "25.08-extra · Runtime · User", "no version")
        T.eq(U.severityLabel("important"), "Important", "severity label")
        T.eq(U.severityLabel(""), "Security", "unknown severity")
        T.eq(U.summary(result), "11 updates available", "summary")
        T.eq(U.summary(U.emptyResult()), "Not checked yet", "unchecked summary")
        T.eq(U.summary(Object.assign(U.emptyResult(), { packagesKnown: true })), "Up to date", "up to date")
        T.eq(U.notifyTitle(result), "11 updates available", "notification title")
        T.eq(U.notifyBody(result), "7 system packages · 4 Flatpaks · 2 security updates", "notification body")
        T.eq(U.notifyBody(Object.assign(U.emptyResult(), { flatpaks: [{}] })), "1 Flatpak", "singular body")

        // Empty and failing checks
        const empty = U.parseReport("@dnf 0\n{}\n@installed 0\n\n@flatpak-system 0\n\n@flatpak-user 0\n\n@flatpak-installed 0\n\n@end 0\n")
        T.eq([empty.packages.length, empty.flatpaks.length, empty.checked, U.summary(empty)], [0, 0, true, "Up to date"], "nothing to update")
        const offline = U.parseReport([
            "@dnf 1", "", "@dnf-stderr 1", "Updating and loading repositories:",
            "Failed to download metadata (metalink: \"https://mirrors.example.org/metalink\") for repository \"updates\": Download failed: Curl error (6): Could not resolve hostname",
            "@dnf-cached 0", "{\"upgrades\":[{\"name\":\"a\",\"arch\":\"x86_64\",\"evr\":\"2-1\",\"repository\":\"updates\"}]}",
            "@installed 0", "a.x86_64\t(none):1-1",
            "@flatpak-system 1", "", "@flatpak-system-stderr 1", "error: Unable to load summary from remote flathub: While fetching https://dl.example.org/summary.idx: [6] Could not resolve hostname",
            "@flatpak-system-cached 0", "org.example.App\tApp\t2.0\tstable\tflathub\tapp/org.example.App/x86_64/stable",
            "@flatpak-user 0", "", "@end 0"].join("\n"))
        T.eq([offline.offline, offline.packagesCached, offline.flatpaksCached], [true, true, true], "offline uses the cache")
        T.eq(offline.packageError, "Offline: the update servers could not be reached", "offline text")
        T.eq(offline.flatpakError, "Offline: the update servers could not be reached", "flatpak offline text")
        T.eq([offline.packages.length, offline.packages[0].from, offline.flatpaks.length], [1, "1-1", 1], "cached data shown")
        T.ok(offline.checked, "user installation answered")
        const allOffline = U.parseReport("@dnf 1\n\n@dnf-stderr 1\nCurl error (7): Could not connect to server\n@flatpak-system 1\n\n@flatpak-user 1\n\n@end 0")
        T.eq([allOffline.checked, allOffline.packagesKnown, allOffline.flatpaksKnown], [false, false, false], "nothing known offline without a cache")
        const missing = U.parseReport("@dnf 127\n@flatpak-system 127\n@flatpak-user 127\n@flatpak-installed 127\n@end 0")
        T.eq([missing.packageError, missing.flatpakError], ["dnf5 is not installed", "Flatpak is not installed"], "missing tools")
        T.eq(U.errorText("dnf", { code: 124 }, ""), "System packages: the check timed out", "timeout")
        T.eq(U.errorText("dnf", { code: 1 }, "Updating and loading repositories:\nerror: Cannot open repository file"), "System packages: check failed (Cannot open repository file)", "generic error")
        T.eq(U.errorText("flatpak", { code: 1 }, ""), "Flatpaks: check failed (exit 1)", "error without text")
        T.eq(U.parseReport("@dnf 0\nnot json\n@end 0").packageError, "System packages: unreadable dnf output", "unreadable output")

        // The shell itself: scripts/shell-update.sh check
        const shellOk = U.parseShellReport(["@repo 0", "ok", "/home/x/.local/share/buchhwin-shell", "main", "origin/main", "abc1234",
            "@fetch 0", "", "@behind 0", "2", "@ahead 0", "0", "@dirty 0", "",
            "@log 0", "def5678\tfeat: a shell change", "0123abc\tdocs: a line", "@end 0"].join("\n"))
        T.eq([shellOk.known, shellOk.repo, shellOk.branch, shellOk.upstream, shellOk.head], [true, "ok", "main", "origin/main", "abc1234"], "shell report header")
        T.eq([shellOk.behind, shellOk.ahead, shellOk.dirty, shellOk.fetched], [2, 0, false, true], "shell counts")
        T.eq(shellOk.commits, [{ hash: "def5678", subject: "feat: a shell change" }, { hash: "0123abc", subject: "docs: a line" }], "shell commits")
        T.eq(U.shellSummary(shellOk), "2 commits behind origin/main", "shell summary")
        T.eq(U.shellSubtitle(shellOk), "main at abc1234", "shell subtitle")
        T.ok(U.shellUpdatable(shellOk), "clean and behind is updatable")
        const shellDirty = Object.assign({}, shellOk, { dirty: true, ahead: 1 })
        T.ok(!U.shellUpdatable(shellDirty), "local changes or local commits are not")
        T.eq(U.shellSubtitle(shellDirty), "main at abc1234 · 1 local commit · local changes", "the subtitle says why")
        const shellOffline = U.parseShellReport("@repo 0\nok\n/x\nmain\norigin/main\nabc1234\n@fetch 128\nfatal: unable to access: Could not resolve host\n@behind 0\n1\n@ahead 0\n0\n@dirty 0\n\n@log 0\nabc\tx\n@end 0")
        T.eq([shellOffline.error, shellOffline.fetched, shellOffline.behind], ["Offline: the shell's remote could not be reached", false, 1], "offline keeps what was fetched last")
        const shellSkipped = U.parseShellReport("@repo 0\nok\n/x\nmain\norigin/main\nabc1234\n@fetch 0\nskipped\n@behind 0\n0\n@ahead 0\n0\n@dirty 0\n\n@log 0\n\n@end 0")
        T.eq([shellSkipped.fetched, shellSkipped.error, U.shellSummary(shellSkipped)], [false, "", "Up to date"], "an offline check is not a fetch")
        const shellLocal = U.parseShellReport("@repo 0\nlocal\n/x/stable\nstable\n\nabc1234\n@end 0")
        T.eq([shellLocal.repo, U.shellSummary(shellLocal), U.shellUpdatable(shellLocal)], ["local", "Development checkout, follows no remote", false], "the development machine")
        const shellNone = U.parseShellReport("@repo 0\nnone\n/x\n@end 0")
        T.eq([shellNone.repo, U.shellSummary(shellNone), U.shellSubtitle(shellNone)], ["none", "Not a git checkout", "/x"], "no checkout")
        T.eq([U.parseShellReport("").known, U.shellSummary(U.emptyShell())], [false, "Not checked yet"], "no report")
        T.eq(U.shellCheckCommand("/s", true), ["/s", "check", "--offline"], "offline check command")
        T.eq(U.shellUpdateCommand("/s").slice(-2), ["/s", "apply"], "the update runs the script's apply")
        T.eq(U.shellUpdateCommand("/s")[0], "systemd-run", "through a transient unit")
        const stateWithShell = U.parseState(U.serializeState(Object.assign(U.parseState(""), { shell: shellOk })))
        T.eq([stateWithShell.shell.behind, stateWithShell.shell.commits.length], [2, 2], "the shell state survives the state file")
        T.eq(U.parseState("").shell, null, "and is null before the first check")

        // Time labels (local time)
        const now = new Date(2026, 8, 17, 14, 30).getTime()
        T.eq(U.checkedText(0, now), "Never", "never checked")
        T.eq(U.checkedText(now - 20000, now), "Just now", "just now")
        T.eq(U.checkedText(now - 5 * U.MINUTE, now), "5 minutes ago", "minutes")
        T.eq(U.checkedText(now - U.MINUTE, now), "1 minute ago", "one minute")
        T.eq(U.checkedText(new Date(2026, 8, 17, 9, 5).getTime(), now), "Today, 09:05", "today")
        T.eq(U.checkedText(new Date(2026, 8, 16, 22, 40).getTime(), now), "Yesterday, 22:40", "yesterday")
        T.eq(U.checkedText(new Date(2026, 8, 12, 18, 0).getTime(), now), "Sep 12, 18:00", "older")
        T.eq(U.checkedText(new Date(2025, 11, 31, 8, 0).getTime(), now), "Dec 31 2025, 08:00", "other year")
        // Calendar days, not 24-hour windows. On the night the clocks go back
        // (25 hours long where this runs with DST) "yesterday" measured as
        // dayStart - 24h started an hour into it; on the night they go
        // forward it reached an hour into the day before.
        const afterFallBack = new Date(2026, 9, 26, 0, 30).getTime()
        T.eq(U.checkedText(new Date(2026, 9, 25, 0, 10).getTime(), afterFallBack), "Yesterday, 00:10",
             "the first minutes of yesterday are yesterday on a 25-hour day")
        const afterSpringForward = new Date(2026, 2, 30, 0, 30).getTime()
        T.eq(U.checkedText(new Date(2026, 2, 28, 23, 30).getTime(), afterSpringForward), "Mar 28, 23:30",
             "the day before yesterday is not yesterday on a 23-hour day")
        T.eq(U.checkedText(new Date(2026, 8, 17, 23, 59).getTime(), now), "Today, 23:59", "a later time today is today")

        // Schedule
        T.ok(U.checkDue(now, { lastCheck: 0, lastAttempt: 0 }, 24), "never checked is due")
        T.ok(!U.checkDue(now, { lastCheck: now - 23 * H, lastAttempt: now - 23 * H }, 24), "within interval")
        T.ok(U.checkDue(now, { lastCheck: now - 25 * H, lastAttempt: now - 25 * H }, 24), "interval passed")
        T.ok(!U.checkDue(now, { lastCheck: now - 25 * H, lastAttempt: now - 10 * U.MINUTE }, 24), "failed attempt waits for the retry")
        T.ok(U.checkDue(now, { lastCheck: now - 25 * H, lastAttempt: now - 2 * H }, 24), "retry after an hour")
        T.ok(!U.checkDue(now, { lastCheck: 0, lastAttempt: 0 }, 0), "off")
        T.ok(!U.checkDue(now, { lastCheck: 0, lastAttempt: 0 }, 5), "invalid interval")
        T.ok(U.refreshDue(now, { lastRefresh: now - 7 * H }, 6), "refresh after the interval")
        T.ok(!U.refreshDue(now, { lastRefresh: now - 5 * H }, 6), "no refresh within the interval")
        T.ok(!U.refreshDue(now, { lastRefresh: now - 12 * H }, 0), "24 h while automatic checks are off")
        T.eq([U.validHours(12), U.validHours(3)], [12, 24], "valid hours")

        // Notification sets
        const keys = U.itemKeys(result)
        T.eq(keys.length, 11, "one key per update")
        T.ok(keys.indexOf("rpm:sudo.x86_64@1.9.17-3.p2.fc44") >= 0 && keys.indexOf("flatpak:user/org.example.Office/stable@9.5.0") >= 0, "key format")
        T.eq(U.newKeys(keys, keys), [], "same set is not new")
        T.eq(U.newKeys(keys, keys.slice(1)), [keys[0]], "one new update")
        T.eq(U.newKeys(keys.slice(1), keys), [], "a smaller set is not new")
        T.eq(U.newKeys(["a"], undefined), ["a"], "nothing notified yet")

        // State file
        const state = U.parseState(U.serializeState({ lastCheck: 5, lastAttempt: 6, lastRefresh: 7, notified: ["a"], result: result }))
        T.eq([state.lastCheck, state.lastAttempt, state.lastRefresh, state.notified], [5, 6, 7, ["a"]], "state round trip")
        T.eq(state.result.packages.length, 7, "stored result")
        T.eq(U.parseState("{\"version\":2,\"lastCheck\":5}").lastCheck, 0, "unknown version")
        T.eq(U.parseState("garbage"), { lastCheck: 0, lastAttempt: 0, lastRefresh: 0, notified: [], result: null, shell: null }, "broken state")
        T.eq(U.parseState("{\"version\":1,\"lastCheck\":-3,\"notified\":[1,\"x\"],\"result\":{\"packages\":1}}"),
             { lastCheck: 0, lastAttempt: 0, lastRefresh: 0, notified: ["x"], result: null, shell: null }, "invalid values dropped")

        // Commands
        T.eq(U.checkCommand("/s/updates-check.sh", false, false), ["/s/updates-check.sh"], "normal check")
        T.eq(U.checkCommand("/s/updates-check.sh", true, false), ["/s/updates-check.sh", "--refresh"], "forced refresh")
        T.eq(U.checkCommand("/s/updates-check.sh", true, true), ["/s/updates-check.sh", "--cache-only"], "cache only never refreshes")
        T.eq(U.discoverCommand(), ["plasma-discover", "--mode", "update"], "Discover update mode")
        T.eq(U.flatpakUpdateCommand("/s/launch-kitty.sh"), ["/s/launch-kitty.sh", "--hold", "flatpak", "update", "--user", "-y"], "user flatpak update")
        T.finish("UpdatesTest")
    }
}
