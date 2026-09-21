pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Settings > Default Apps: session defaults for links, files and the app
// hotkeys through scripts/default-apps.py (buchhwin-shell-mimeapps.list, so
// Plasma keeps its own defaults). Loaded only while the page is open.
Singleton {
    id: root

    property var categories: []
    property bool loading: false
    property string error: ""
    property var pending: []

    function refresh() {
        if (listProc.running) return
        loading = true
        listProc.running = true
    }

    function setDefault(category, desktopId) { run(["set", category, desktopId]) }
    function reset(category) { run(["unset", category]) }

    function run(args) {
        pending = pending.concat([args])
        next()
    }

    function next() {
        if (actionProc.running || !pending.length) return
        actionProc.command = ["python3", Paths.script("default-apps.py")].concat(pending[0])
        pending = pending.slice(1)
        actionProc.running = true
    }

    Process {
        id: listProc
        stderr: ErrorLog { label: "DefaultAppsService.listProc" }
        command: ["python3", Paths.script("default-apps.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const result = JSON.parse(text)
                    root.error = result.error || ""
                    if (result.categories) root.categories = result.categories
                } catch (error) {
                    root.error = "Default apps could not be read"
                }
            }
        }
    }

    Process {
        id: actionProc
        stderr: ErrorLog { label: "DefaultAppsService.actionProc" }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.error = JSON.parse(text).error || "" } catch (error) { root.error = "Default app could not be saved" }
            }
        }
        onExited: {
            root.refresh()
            root.next()
        }
    }
}
