import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T

// A dock surface that goes (its screen unplugged, the shell exiting) while a
// window covers it - the pattern shell/dock/Dock.qml and services/
// DockService.qml are built on, with stand-ins: the real ones need the
// compositor and the layout, and those reach the session (testing.md
// pitfall 82).
//
// The dock takes its body back from the service as it goes. Without the body
// nothing covers it any more, the dock wants to show, and showing reports the
// body again - from inside the change of the service's coveredOn that taking
// it away set off. That was "Binding loop detected for property coveredOn" in
// the log of every exit with a covered dock, and the gone dock's body stayed
// in the service. The surface reports nothing once it is leaving.
//
// And Dock.qml as it is: the flag is set before the service forgets it, and
// every report returns on it.
ShellRoot {
    id: root

    // DockService's part: the bodies the docks report, and which screens a
    // window covers (a window over every reported body here).
    component Service: QtObject {
        property var bodies: ({})
        property int reports: 0
        readonly property var coveredOn: {
            const result = {}
            for (const name of ["A"]) result[name] = !!bodies[name]
            return result
        }
        function covered(name) { return coveredOn[name] === true }
        function reportBody(name, rect) {
            reports += 1
            if (JSON.stringify(bodies[name] || null) === JSON.stringify(rect || null)) return
            const next = Object.assign({}, bodies)
            if (rect) next[name] = rect
            else delete next[name]
            bodies = next
        }
        function forget(name) { reportBody(name, null) }
    }

    // Dock.qml's part: shown once the body is in, hidden while covered,
    // shown again as soon as nothing covers it, and reporting on each change.
    component Surface: Item {
        id: surface
        required property var modelData
        required property var service
        readonly property string screenName: modelData
        property bool leaving: false
        readonly property bool covered: service.covered(screenName)
        readonly property bool want: !covered
        property bool shown: false
        property bool decided: false
        function decide() {
            if (decided || !service.bodies[screenName]) return
            decided = true
            shown = want
        }
        Component.onCompleted: { report(); decide() }
        onWantChanged: {
            if (!decided) {
                decide()
                return
            }
            if (want) shown = true
            else if (shown) shown = false
        }
        onShownChanged: report()
        function report() {
            if (leaving) return
            service.reportBody(screenName, { x: 0, y: 1150, width: 400, height: 50 })
            decide()
        }
        Component.onDestruction: {
            leaving = true
            service.forget(screenName)
        }
    }

    Service { id: dockService }
    property var screens: ["A"]
    Variants {
        model: root.screens
        Surface { service: dockService }
    }

    // The runner copies the whole tree beside the test (PanelServiceTest's way).
    Component { id: fileReader; FileView { blockLoading: true; printErrors: false } }
    function read(path) {
        const view = fileReader.createObject(root, { path: Quickshell.shellPath(path) })
        const text = view.text()
        view.destroy()
        return text
    }
    // The body of a function or handler in a QML file, from its first line
    // to the closing brace at the same indentation.
    function block(text, head) {
        const start = text.indexOf(head)
        if (start < 0) return ""
        const lineStart = text.lastIndexOf("\n", start) + 1
        const indent = text.slice(lineStart, start)
        const end = text.indexOf("\n" + indent + "}", start)
        return end < 0 ? "" : text.slice(start, end)
    }

    Timer {
        id: gone
        interval: 100
        onTriggered: {
            T.eq(dockService.bodies, {}, "the gone dock's body is not reported back")
            T.ok(dockService.reports >= 2, "it reported its body, then took it back")

            const dock = root.read("shell/dock/Dock.qml")
            T.ok(dock.length > 0, "Dock.qml is read")
            const teardown = root.block(dock, "Component.onDestruction: {")
            T.ok(teardown.indexOf("leaving = true") >= 0
                 && teardown.indexOf("leaving = true") < teardown.indexOf("DockService.forget(screenName)"),
                 "Dock.qml sets leaving before the service forgets it")
            for (const head of ["function report() {", "function reportPlace() {", "function reportZones() {"])
                T.ok(root.block(dock, head).split("\n")[1].trim() === "if (leaving) return", head + " returns once leaving")
            T.ok(dock.indexOf("onAppsRoomChanged: if (!leaving) DockService.reportAppsRoom") >= 0,
                 "and so does the room it reports on its own")
            T.finish("DockTeardown")
        }
    }

    Component.onCompleted: {
        T.eq(dockService.covered("A"), true, "a window covers the dock at first")
        root.screens = []
        gone.start()
    }
}
