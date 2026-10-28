import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T

// The screen corners go while a fullscreen window shows on their screen and
// come back when it ends: any mapped Overlay surface keeps Hyprland
// compositing the whole screen under a fullscreen window (353 against 207 ms
// of its GPU time per second, measured nested on a 4K screen).
//
// ScreenCorners needs a PanelWindow backend, which offscreen has not, so its
// file is read for the three lines that decide it, and a stand-in with those
// lines - over the real screens, the strips as plain objects - shows what they
// do. The compositor's answer (`coveredOn`) is given here per screen name,
// so nothing reaches the session (testing.md pitfall 82).
//
// Per screen, so a fullscreen window on one screen never takes another's
// corners; and with nothing fed back, so a strip's mapping never changes the
// answer that maps it (a binding loop fails the run).
ShellRoot {
    id: root

    FileView {
        id: cornersFile
        path: Quickshell.shellPath("shell/desktop/ScreenCorners.qml")
        blockLoading: true
    }

    // Which screens show a fullscreen window, by name.
    property var fullscreen: ({})

    // ScreenCorners with its lines as they are, the strips as plain objects
    // (an Item without a parent does not report its visibility back).
    Variants {
        id: corners
        model: Quickshell.screens
        property var coveredOn: screen => root.fullscreen[screen.name] === true

        Scope {
            id: screenScope
            required property var modelData
            readonly property int radius: 16
            readonly property bool shown: radius > 0 && !corners.coveredOn(modelData)
            property QtObject top: QtObject { property bool visible: screenScope.shown }
            property QtObject bottom: QtObject { property bool visible: screenScope.shown }
        }
    }

    function mapped(scope) {
        return [scope.top.visible, scope.bottom.visible]
    }

    property int step: 0
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            const scope = corners.instances[0]
            const name = scope ? scope.modelData.name : ""
            switch (root.step++) {
            case 0: {
                // The lines the stand-in copies, in the shipped file.
                const source = cornersFile.text()
                T.ok(source.indexOf("property var coveredOn: screen => HyprlandService.fullscreenOn(screen)") >= 0,
                     "the corners ask the dock's and the notch's question, per screen")
                T.ok(source.indexOf("readonly property bool shown: radius > 0 && !corners.coveredOn(modelData)") >= 0,
                     "of their own scope's screen, and shown only while it is not covered")
                T.eq(source.split("visible: screenScope.shown").length - 1, 1,
                     "the one strip component maps by that and nothing else")
                T.eq(source.indexOf("visible: screenScope.radius > 0"), -1,
                     "not by the radius alone, which kept them over a fullscreen window")

                T.ok(corners.instances.length > 0, "there are corners for a screen")
                T.eq(scope.shown, true, "nothing fullscreen: the corners show")
                T.eq(mapped(scope), [true, true], "both strips mapped")
                root.fullscreen = { [name]: true }
                break
            }
            case 1:
                T.eq(scope.shown, false, "a fullscreen window on this screen: the corners go")
                T.eq(mapped(scope), [false, false], "both strips unmapped, not just made transparent")
                root.fullscreen = {}
                break
            case 2:
                T.eq(scope.shown, true, "it ends (unfullscreen, closed, another workspace): they come back")
                T.eq(mapped(scope), [true, true], "both strips mapped again")
                root.fullscreen = { "another screen": true }
                break
            case 3:
                T.eq(scope.shown, true, "a fullscreen window on another screen leaves these corners alone")
                T.eq(mapped(scope), [true, true], "and their strips mapped")
                root.fullscreen = { [name]: true, "another screen": true }
                break
            case 4:
                T.eq(scope.shown, false, "this screen's own fullscreen still counts beside another's")
                root.fullscreen = { "another screen": true }
                break
            case 5:
                T.eq(scope.shown, true, "and when only the other one is left, these come back")
                T.eq(mapped(scope), [true, true], "mapped again")
                T.finish("ScreenCornersTest")
                break
            }
        }
    }
}
