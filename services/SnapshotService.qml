pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "snapshot/SnapshotLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// Copies of the whole setup (scripts/snapshot.py): one on the first write of
// each day, kept for 14 days, Restore from Settings > Profiles, and the setup
// exported to one file and imported from one. Nothing runs until something
// asks: SettingsService and LayoutService call beforeWrite() as they write
// (one helper run a day), the page lists the snapshots while it is open.
//
// The day's snapshot takes settings.json and layout.json as the shell held
// them a moment before it rewrote them (their fileText), handed over on
// stdin: the helper starts slower than the write timers, and a copy made
// from disk after them would be of the files just written - the reason
// LayoutService.backupToday does the same. Everything else comes from disk.
//
// A restore or an import keeps a copy of now first and is followed by a
// restart of the shell, so that every part of it reads the files again
// (some read theirs only at the start). Files are chosen with kdialog after
// Settings has closed (a dialog under a panel with the keyboard is unusable,
// pitfall 6), and Settings comes back on Profiles with the answer. Not in the
// lock process, and nothing automatic in a QML test (no BUCHHWIN_SHELL_PATH).
Singleton {
    id: root

    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell.shellId)
    readonly property bool automatic: !lockProcess && (Quickshell.env("BUCHHWIN_SHELL_PATH") || "").length > 0

    property var snapshots: []
    property bool listed: false
    property bool showAll: false
    readonly property var shownSnapshots: showAll ? snapshots : snapshots.slice(0, Logic.SHOWN)
    // "take", "restore", "import", "export" while one runs.
    property string working: ""
    readonly property bool busy: working.length > 0 || exportPick.running || importPick.running || inspectProc.running
    property string message: ""
    property bool messageError: false
    // An import waiting for its confirmation: the file and what it replaces.
    property string importPath: ""
    property var importPlan: null
    property string importCreated: ""

    function find(name) { return snapshots.find(item => item.name === name) || null }
    function subtitle(item) { return Logic.subtitle(item) }
    function whenText(item) { return item ? Logic.whenText(item.created, Date.now()) : "" }
    readonly property string importText: Logic.importText(importPlan)

    function say(text, isError) {
        message = text
        messageError = isError
    }

    function helper(args) {
        return ["python3", Paths.script("snapshot.py")].concat(args)
            .concat(["--config-dir", Paths.configDir, "--state-dir", Paths.stateDir])
    }

    // ---- the day's snapshot ------------------------------------------------------
    property string takenDay: ""
    // After a failed run, the next try waits an hour: a layout edit writes
    // many times a minute, and a helper that fails for good (a state
    // directory that cannot be written) would otherwise run on every write.
    property real retryAfter: 0
    function beforeWrite() {
        if (!automatic) return
        const day = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (takenDay === day || dailyProc.running || Date.now() < retryAfter) return
        takenDay = day
        dailyProc.request = JSON.stringify({ "settings.json": SettingsService.fileText, "layout.json": LayoutService.fileText })
        dailyProc.running = true
    }
    Process {
        id: dailyProc
        property string request: "{}"
        command: root.helper(["daily", "--stdin"])
        stdinEnabled: true
        stderr: ErrorLog { label: "SnapshotService.dailyProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                const answer = Logic.parseAnswer(text)
                // Tried again on a write an hour on rather than counted as
                // the day's.
                if (!answer || answer.ok !== true) {
                    root.takenDay = ""
                    root.retryAfter = Date.now() + Logic.RETRY_MS
                } else if (root.listed && answer.name) {
                    root.refresh()
                }
            }
        }
        onStarted: {
            write(request + "\n")
            stdinEnabled = false
        }
        onExited: stdinEnabled = true
    }

    // ---- the list (Settings > Profiles) --------------------------------------------
    function refresh() {
        if (lockProcess) return
        if (listProc.running) { refreshQueued = true; return }
        listProc.running = true
    }
    property bool refreshQueued: false
    Process {
        id: listProc
        command: root.helper(["list"])
        stderr: ErrorLog { label: "SnapshotService.listProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                root.snapshots = Logic.snapshots(Logic.parseAnswer(text))
                root.listed = true
                if (root.refreshQueued) {
                    root.refreshQueued = false
                    Qt.callLater(root.refresh)
                }
            }
        }
    }

    // ---- by hand, back, out and in ---------------------------------------------------
    function run(kind, args) {
        if (lockProcess || working.length || jobProc.running) return false
        working = kind
        say("", false)
        jobProc.command = helper(args)
        jobProc.running = true
        return true
    }

    function takeNow() { return run("take", ["take"]) }

    function restore(name) {
        if (!Logic.validName(name) || !find(name)) return false
        return run("restore", ["restore", name])
    }

    function exportSetup() {
        if (busy || lockProcess) return
        say("", false)
        PanelService.close()
        exportPick.command = [Paths.script("launch-app.sh"), "org.kde.kdialog", "kdialog", "--title", "Export the setup",
                              "--getsavefilename", Logic.exportName(Paths.home, new Date()), "*.tar.gz|buchhwin-shell setup"]
        exportPick.running = true
    }

    function importSetup() {
        if (busy || lockProcess) return
        say("", false)
        cancelImport()
        PanelService.close()
        importPick.running = true
    }

    // The second step of an import, once the page has said what it replaces.
    function confirmImport() {
        if (!importPath.length) return false
        const path = importPath
        cancelImport()
        return run("import", ["import", path])
    }

    function cancelImport() {
        importPath = ""
        importPlan = null
        importCreated = ""
    }

    function backToPage() {
        if (!PanelService.active.length) PanelService.open("settings", { page: "profiles" })
    }

    Process {
        id: jobProc
        stderr: ErrorLog { label: "SnapshotService.jobProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                const kind = root.working
                const answer = Logic.parseAnswer(text)
                // The answer before the end of the work, so whatever watches
                // `working` reads it.
                root.say(Logic.resultText(kind, answer), !answer || answer.ok !== true)
                root.working = ""
                root.refresh()
                if (kind === "export" || kind === "import") root.backToPage()
                if ((kind === "restore" || kind === "import") && Logic.needsRestart(answer)) restartTimer.restart()
            }
        }
    }
    // A moment for the page to say what happened before the shell goes.
    Timer { id: restartTimer; interval: 1500; onTriggered: SessionService.restartShell() }

    // kdialog through launch-app.sh, for the session's environment; a scope
    // keeps its stdout, which is the answer.
    Process {
        id: exportPick
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (!path.length) { root.backToPage(); return }
                root.run("export", ["export", path])
            }
        }
    }
    Process {
        id: importPick
        command: [Paths.script("launch-app.sh"), "org.kde.kdialog", "kdialog", "--title", "Import a setup",
                  "--getopenfilename", Paths.home || "/", "*.tar.gz|buchhwin-shell setup\n*|All files"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (!path.length) { root.backToPage(); return }
                inspectProc.path = path
                inspectProc.command = root.helper(["inspect", path])
                inspectProc.running = true
            }
        }
    }
    Process {
        id: inspectProc
        property string path: ""
        stderr: ErrorLog { label: "SnapshotService.inspectProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                const answer = Logic.parseAnswer(text)
                if (answer && answer.ok === true) {
                    root.importPath = inspectProc.path
                    root.importPlan = Logic.importPlan(answer.files)
                    root.importCreated = typeof answer.created === "string" ? answer.created : ""
                } else {
                    root.say("Not imported: " + (answer && answer.error ? answer.error : "the file could not be read"), true)
                }
                root.backToPage()
            }
        }
    }
}
