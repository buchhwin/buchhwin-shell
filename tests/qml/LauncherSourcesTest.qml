import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/WindowResults.js" as W
import "../../services/launcher/RecentFiles.js" as R
import "../../services/launcher/CodeFolders.js" as C
import "../../services/launcher/RunCommand.js" as Run
import "../../services/launcher/ResultsLogic.js" as Results

// What the launcher's plain search finds besides apps - open windows,
// recent files, VS Code's folders - and "$ command": what each source makes
// of its input and how its rows are started. Plain objects stand in for
// Quickshell's windows and desktop entries; paths are under an invented home.
ShellRoot {
    // The launcher's own scoring (LauncherService.score), copied: the
    // sources take it as an argument.
    function score(text, query) {
        const value = (text || "").toLowerCase()
        if (!query.length) return 1
        if (value === query) return 100
        if (value.startsWith(query)) return 80
        if (value.split(/[\s\-_.]+/).some(word => word.startsWith(query))) return 60
        if (value.includes(query)) return 40
        return 0
    }
    readonly property string home: "/home/sample"
    function script(name) { return "/s/" + name }

    Component.onCompleted: {
        // ---- open windows ------------------------------------------------------
        const toplevels = [
            { address: "5609d24b6a10", title: "buchhwin-shell - Visual Studio Code", wayland: { appId: "code" },
              workspace: { id: 2, name: "2" } },
            { address: "0x5609aa", title: "Inbox - Outlook", wayland: { appId: "brave-outlook" }, workspace: { id: 1, name: "1" } },
            { address: "77", title: "", wayland: { appId: "xwaylandvideobridge" }, workspace: { id: 1, name: "1" } },
            { address: "78", title: "Bridge", wayland: { appId: "other" }, workspace: { id: -99, name: "special:buchhwin-hidden" } },
            { address: "79", title: "Scratch notes", wayland: null, workspace: { id: -98, name: "special:scratch" } },
            { address: "not-hex", title: "Broken", wayland: { appId: "x" }, workspace: null },
            null
        ]
        const windows = W.entries(toplevels)
        T.eq(windows.map(window => window.address), ["0x5609d24b6a10", "0x5609aa", "0x79"],
             "the windows with an address, as HyprCommands wants it; the hidden helpers left out")
        T.eq(windows[2], { address: "0x79", title: "Scratch notes", appId: "", workspace: "scratch" },
             "a special workspace by its name, a window without a Wayland handle still there")
        const names = { "code": "Visual Studio Code", "brave-outlook": "Outlook (PWA)" }
        const appName = appId => names[appId] || appId
        T.eq(W.matches(windows, "outl", score, appName).map(window => window.address), ["0x5609aa"], "found by its app")
        T.eq(W.matches(windows, "buchhwin", score, appName).map(window => window.address), ["0x5609d24b6a10"], "and by its title")
        T.eq(W.matches(windows, "o", score, appName), [], "not before two letters")
        T.eq(W.matches(windows.concat(windows, windows), "code", score, appName, 2).length, 2, "a handful at most")
        T.eq(W.subtitle(windows[0], appName), "Switch to window · Visual Studio Code · Workspace 2", "what Enter does, and where")
        T.eq(W.subtitle({ appId: "code", workspace: "Minimized" }, appName), "Switch to window · Visual Studio Code · minimized",
             "a minimized window says so, not the workspace it is parked on")
        T.eq(W.entries(undefined), [], "no windows")
        T.eq(W.entries([{ address: "5a", title: "Mail", wayland: { appId: "thunderbird" }, workspace: { id: 12, name: "12" },
                          monitor: { name: "DP-2" } }], ["eDP-1", "DP-2"])[0].workspace, "2",
             "with blocks per monitor a window's workspace by the number of its pip")

        // ---- recent files ------------------------------------------------------
        const xbel = '<?xml version="1.0" encoding="UTF-8"?>\n<xbel version="1.0">\n'
            + '  <bookmark href="file:///home/sample/Documents/Report%202026.pdf" added="2026-10-14T05:25:03Z" modified="2026-10-14T05:25:03Z" visited="2026-10-14T05:25:03Z">\n'
            + '    <info><metadata owner="http://freedesktop.org"><mime:mime-type type="application/pdf"/>'
            + '<bookmark:applications><bookmark:application name="okular" exec="&apos;okular %u&apos;" modified="2026-10-14T05:25:03Z" count="1"/></bookmark:applications>'
            + '</metadata></info>\n  </bookmark>\n'
            + '  <bookmark href="file:///home/sample/Pictures/a&amp;b.png" added="2026-10-16T10:00:00Z" modified="2026-10-16T10:00:00Z" visited="2026-10-16T10:00:00Z">\n'
            + '    <info><metadata owner="http://freedesktop.org"><mime:mime-type type="image/png"/></metadata></info>\n  </bookmark>\n'
            + '  <bookmark href="https://example.org/page" added="2026-10-17T10:00:00Z" modified="2026-10-17T10:00:00Z" visited="2026-10-17T10:00:00Z">\n'
            + '    <info><metadata owner="http://freedesktop.org"><mime:mime-type type="text/html"/></metadata></info>\n  </bookmark>\n'
            + '  <bookmark href="file:///home/sample/.local/share/Trash/files/old.txt" added="2026-10-18T10:00:00Z" modified="2026-10-18T10:00:00Z" visited="2026-10-18T10:00:00Z">\n'
            + '  </bookmark>\n'
            + '  <bookmark href="file:///home/sample/Documents/Report%202026.pdf" added="2026-10-12T05:25:03Z" modified="2026-10-12T05:25:03Z" visited="2026-10-12T05:25:03Z">\n'
            + '  </bookmark>\n'
            + '  <bookmark href="file:///home/sample/git" added="2026-10-15T10:00:00Z" modified="2026-10-15T10:00:00Z" visited="2026-10-15T10:00:00Z">\n'
            + '    <info><metadata owner="http://freedesktop.org"><mime:mime-type type="inode/directory"/></metadata></info>\n  </bookmark>\n'
            + '  <bookmark href="file:///home/sample/bad%E0%A4%A.txt" added="2026-10-19T10:00:00Z"></bookmark>\n'
            + '  <bookmark href="file://otherhost/srv/share.txt" added="2026-10-19T10:00:00Z"></bookmark>\n'
            + '</xbel>\n'
        const recent = R.parse(xbel, home)
        T.eq(recent.map(file => file.path),
             ["/home/sample/Pictures/a&b.png", "/home/sample/git", "/home/sample/Documents/Report 2026.pdf"],
             "local files newest first, each once; no web pages, no trash, no remote host, no broken URL")
        T.eq(recent[2], { path: "/home/sample/Documents/Report 2026.pdf", name: "Report 2026.pdf", folder: "~/Documents",
                          kind: "pdf", time: Date.parse("2026-10-14T05:25:03Z") },
             "a file: its name, where it is with the home as ~, its kind, its newest time")
        T.eq(recent.map(file => file.kind), ["image", "folder", "pdf"], "kinds by MIME type")
        T.eq(recent[1].folder, "~", "a folder right under home")
        T.eq(R.matches(recent, "report", score).map(file => file.name), ["Report 2026.pdf"], "found by name")
        T.eq(R.matches(recent, "r", score), [], "not before two letters")
        T.eq(R.parse("", home), [], "no file, nothing")
        T.eq(R.parse("<xbel><bookmark href='x'>", home), [], "nothing it can read")

        // ---- VS Code's folders ---------------------------------------------------
        const apps = [
            { id: "org.kde.kate", command: ["kate"], noDisplay: false },
            { id: "com.microsoft.VSCode.UrlHandler", command: ["/usr/share/code/code", "--open-url"], noDisplay: true },
            { id: "com.microsoft.VSCode", name: "Visual Studio Code", icon: "vscode", command: ["/usr/bin/code"], noDisplay: false },
            { id: "codium", command: ["codium"], noDisplay: false }
        ]
        const editor = C.editorEntry(apps)
        T.eq(editor ? [editor.app.id, editor.editor] : null, ["com.microsoft.VSCode", "Code"],
             "the editor by the program its entry runs, hidden handlers left out, VS Code before Codium")
        T.eq(C.editorEntry(apps.slice(3)).editor, "VSCodium", "Codium on its own")
        T.eq(C.editorEntry(apps.slice(0, 2)), null, "no editor installed")
        const found = C.parse(JSON.stringify({ editors: { "Code": ["/home/sample/work/site", "/home/sample/git/shell/", "relative"],
                                                          "VSCodium": ["/home/sample/other"] },
                                               projects: ["/home/sample/git/dots", "/home/sample/git/shell", 7] }))
        T.eq(found.editors["Code"], ["/home/sample/work/site", "/home/sample/git/shell/"], "absolute paths only")
        const folders = C.folders(found, "Code", home)
        T.eq(folders.map(folder => folder.place), ["~/work/site", "~/git/shell", "~/git/dots"],
             "the editor's recent ones first, then the projects, each once")
        T.eq(C.parse("not json"), { editors: {}, projects: [] }, "an answer it cannot read is none")
        T.eq(C.folders(C.parse(JSON.stringify({ editors: { "Code": ["/home/sample/x.code-workspace"] }, projects: [] })), "Code", home)[0],
             { path: "/home/sample/x.code-workspace", name: "x", place: "~/x.code-workspace", workspace: true },
             "a workspace file by its name")
        T.eq(C.matches(folders, "shell", score).map(folder => folder.name), ["shell"], "found by the folder's name")
        T.eq(C.openContext(editor.app, "/home/sample/git/shell", script),
             { command: ["/s/launch-app.sh", "com.microsoft.VSCode", "/usr/bin/code", "/home/sample/git/shell"] },
             "opened by the editor's own launch, named after its entry, with the folder after it")
        T.eq(C.openContext(editor.app, "relative", script), null, "never a relative path")

        // ---- "$ command" ---------------------------------------------------------
        T.eq([Run.parse("$ htop"), Run.parse("$"), Run.parse("htop")], ["htop", "", ""], "the line after the $")
        T.eq(Run.context("htop", script, false), { command: ["/s/launch-app.sh", "htop", "htop"] },
             "a plain command runs as it is, in a unit named after it")
        T.eq(Run.context("/usr/bin/kate --new notes.txt", script, false).command,
             ["/s/launch-app.sh", "kate", "/usr/bin/kate", "--new", "notes.txt"], "by its program's name")
        T.eq(Run.context("sleep 2 && notify-send done", script, false).command,
             ["/s/launch-app.sh", "sleep", "sh", "-c", "sleep 2 && notify-send done"], "a shell line goes to sh -c")
        T.eq(Run.context("FOO=1 make", script, false).command, ["/s/launch-app.sh", "sh", "sh", "-c", "FOO=1 make"],
             "a variable in front is the shell's, and the unit is sh")
        T.eq(Run.context("ls ~/git", script, false).command[2], "sh", "\"~\" needs the shell")
        T.eq(Run.context("make -C ~/git/x", script, true).command,
             ["/s/launch-terminal.sh", "--hold", "--title", "make -C ~/git/x", "--", "sh", "-c", "make -C ~/git/x"],
             "in a terminal that stays open for the output, titled after the command")
        T.eq(Run.context("htop", script, true, false).command,
             ["/s/launch-terminal.sh", "--title", "htop", "--", "sh", "-c", "htop"],
             "a terminal program started by Enter closes with its terminal")
        T.eq(Run.context("brave --incognito", script, false), { command: ["/s/launch-brave.sh", "--incognito"] },
             "a browser through its session launcher (the wallet's password store, pitfall 32)")
        T.eq(Run.context("brave", script, true), { command: ["/s/launch-brave.sh"] }, "even when a terminal is asked for")
        T.eq(Run.context("   ", script, false), null, "nothing typed, nothing run")
        const terminalApps = [{ id: "htop", command: ["/usr/bin/htop"], runInTerminal: true },
                              { id: "org.kde.kate", command: ["kate"], runInTerminal: false }]
        T.eq([Run.needsTerminal("htop -d 10", terminalApps), Run.needsTerminal("kate", terminalApps),
              Run.needsTerminal("FOO=1 htop", terminalApps), Run.needsTerminal("htop", undefined)], [true, false, false, false],
             "a program whose entry says Terminal=true goes to a terminal by itself")
        T.eq(Run.title("x".repeat(80)).length, 60, "a long command's title is cut")

        // ---- where they go in the list -------------------------------------------
        const app = (id) => ({ kind: "app", title: id, appId: id })
        const window = { kind: "window", key: "window:0x1", title: "Inbox" }
        const command = { kind: "command", key: "command:Settings", title: "Settings" }
        T.eq(Results.appsMode([], null, false, [app("a"), app("b")], [command], [window]).map(Results.keyOf),
             ["app:a", "command:Settings", "window:0x1", "app:b"],
             "after the best app and the commands, before the rest of the apps")
        T.eq(Results.appsMode([], null, false, [app("a")], [], undefined).map(Results.keyOf), ["app:a"], "none given")

        T.finish("LauncherSourcesTest")
    }
}
