import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/snapshot/SnapshotLogic.js" as S

// Settings > Profiles "Backups" (SnapshotLogic): the helper's answers, the
// names it may be handed back, the rows' words, what an import says before it
// replaces anything, and when the shell restarts after one.
ShellRoot {
    Component.onCompleted: {
        T.ok(S.validName("daily-2026-10-19.tar.gz") && S.validName("before-restore-2026-10-19-093000.tar.gz")
             && S.validName("manual-2026-10-19-093000-2.tar.gz"), "the helper's names")
        T.ok(!S.validName("../daily-2026-10-19.tar.gz") && !S.validName("daily-2026-10-19.tar.gz/x") && !S.validName("")
             && !S.validName("export-2026-10-19.tar.gz") && !S.validName(5), "nothing else is handed to it")

        T.eq(S.parseAnswer('noise\n{"ok": true, "name": "daily-2026-10-19.tar.gz"}\n'), { ok: true, name: "daily-2026-10-19.tar.gz" }, "the last JSON line")
        T.eq([S.parseAnswer(""), S.parseAnswer("[1]"), S.parseAnswer("{broken")], [null, null, null], "no answer")

        const listed = S.snapshots({ ok: true, snapshots: [
            { name: "daily-2026-10-19.tar.gz", kind: "daily", created: "2026-10-19T09:30:00", files: 9, size: 12345 },
            { name: "../evil", kind: "daily", created: "", files: 1, size: 1 },
            { name: "manual-2026-10-18-180200.tar.gz", kind: "weird", created: 5, files: "x", size: -3 }] })
        T.eq(listed.map(item => item.name), ["daily-2026-10-19.tar.gz", "manual-2026-10-18-180200.tar.gz"], "names checked")
        T.eq(listed[1], { name: "manual-2026-10-18-180200.tar.gz", kind: "manual", created: "", files: 0, size: 0 }, "fields checked")
        T.eq(S.snapshots({ ok: false, error: "x" }), [], "a failed list is empty")

        T.eq(S.subtitle(listed[0]), "Daily · 9 files · 12 KB", "row subtitle")
        T.eq(S.subtitle({ kind: "before-import", files: 1, size: 900 }), "Before an import · 1 file · 900 B", "one file")
        T.eq([S.sizeText(1500000), S.sizeText(2000000)], ["1.5 MB", "2 MB"], "sizes")
        const now = new Date(2026, 9, 19, 12, 0).getTime()
        T.eq(S.whenText("2026-10-19T09:30:00", now), "Today, 09:30", "when")
        T.eq(S.whenText("2026-10-18T18:02:00", now), "Yesterday, 18:02", "yesterday")
        T.eq(S.whenText("", now), "Unknown time", "no time")

        // Import: what it replaces, said before it does.
        const plan = S.importPlan([{ path: "config/settings.json", state: "differs" }, { path: "config/layout.json", state: "same" },
                                   { path: "state/state.json", state: "differs" }, { path: "xdg/buchhwin-shell-mimeapps.list", state: "new" },
                                   { path: 5, state: "new" }])
        T.eq(plan, { replaced: ["settings.json", "notification rules"], added: ["buchhwin-shell-mimeapps.list"], same: 1 }, "the plan")
        T.eq(S.importText(plan), "Replaces settings.json, notification rules; adds buchhwin-shell-mimeapps.list; 1 unchanged. A copy of your setup now is kept first, and the shell restarts.", "its words")
        T.eq(S.importText({ replaced: [], added: [], same: 4 }), "Holds nothing that differs from your setup now.", "nothing to do")
        T.eq(S.importText(S.importPlan([1, 2, 3, 4, 5, 6, 7, 8].map(n => ({ path: "config/f" + n + ".json", state: "differs" })))).indexOf("and 2 more") > 0, true, "a long list is cut")

        // After a restore or an import.
        T.eq([S.needsRestart({ ok: true, written: ["config/settings.json"] }), S.needsRestart({ ok: true, written: [] }),
              S.needsRestart({ ok: false }), S.needsRestart(null)], [true, false, false, false], "the shell restarts only for written files")
        T.eq(S.resultText("restore", { ok: true, written: ["a", "b"] }), "Restored 2 files. The shell restarts to read them.", "restored")
        T.eq(S.resultText("import", { ok: true, written: [] }), "Nothing differed - your setup is as it was", "nothing differed")
        T.eq(S.resultText("export", { ok: true, files: 9, path: "/media/stick/setup.tar.gz" }), "Exported 9 files to /media/stick/setup.tar.gz", "exported")
        T.eq(S.resultText("import", { ok: false, error: "it is not a buchhwin-shell setup" }), "it is not a buchhwin-shell setup", "the helper's reason")
        T.eq(S.resultText("take", null), "The snapshot helper did not answer", "no answer")
        T.eq(S.exportName("/home/sample", new Date(2026, 9, 9)), "/home/sample/buchhwin-shell-setup-2026-10-09.tar.gz", "the export's name")
        T.finish("SnapshotTest")
    }
}
