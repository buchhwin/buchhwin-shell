import Quickshell
import QtQuick
import qs.shell.widgets
import "Harness.js" as T
import "../../services/notch/NotchLogic.js" as N

// The strip leaves out a part with nothing to say (NotchStrip.qml: the
// delegate's `visible`, NotchLogic.stripShows). Built the strip's way - a
// Loader per part in a Row, a widget part a Loader in that Loader, the
// widget's own `hasData` read through both - with stand-ins for what the
// strip loads: a privacy item while nothing listens took 146 px of the strip
// and pushed the clock aside. The Row goes by the explicit flag, so a part
// left out takes no room and no gap, and under a hidden parent (a fullscreen
// window, pitfall 89) nothing moves.
ShellRoot {
    id: root
    property bool arranging: false
    property bool recording: false

    component Part: Loader {
        id: part
        property string type: ""
        readonly property var widget: item && item.item !== undefined ? item.item : null
        visible: N.stripShows(part.type, part.widget === null || part.widget.hasData !== false,
                              root.recording, false, root.arranging)
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 120

        Item {
            id: content
            Row {
                id: row
                spacing: 8
                Part {
                    id: quiet
                    type: "privacy"
                    sourceComponent: Loader {
                        sourceComponent: WidgetBase { hasData: false; icon: "x"; label: "Microphone active"; inGroup: true }
                    }
                }
                Part {
                    id: clock
                    type: "clock"
                    sourceComponent: Rectangle { width: 40; height: 10 }
                }
                Part {
                    id: talking
                    type: "battery"
                    sourceComponent: Loader {
                        sourceComponent: WidgetBase { hasData: true; icon: "y"; label: "42%"; inGroup: true }
                    }
                }
                Part {
                    id: chip
                    type: "recording"
                    sourceComponent: Rectangle { width: 20; height: 10 }
                }
            }
        }
    }

    function shownWidth() { return clock.width + talking.width + row.spacing }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            T.ok(quiet.widget !== null && quiet.widget.hasData === false && quiet.width > 0,
                 "the quiet widget is loaded and has a size")
            T.eq([quiet.visible, clock.visible, talking.visible, chip.visible], [false, true, true, false],
                 "the quiet widget and the placed recording item are left out")
            T.eq(row.implicitWidth, root.shownWidth(), "the strip is as wide as what it shows, no room and no gap for the rest")
            T.ok(clock.x === 0, "and the clock is where the quiet part was")
            content.visible = false
            hidden.start()
        }
    }
    Timer {
        id: hidden
        interval: 50
        onTriggered: {
            T.eq(row.implicitWidth, root.shownWidth(), "under a hidden parent the strip keeps its width")
            content.visible = true
            root.recording = true
            recordingOn.start()
        }
    }
    Timer {
        id: recordingOn
        interval: 50
        onTriggered: {
            T.ok(chip.visible, "the recording item shows while recording")
            T.eq(row.implicitWidth, root.shownWidth() + row.spacing + chip.width, "and takes its room")
            root.recording = false
            root.arranging = true
            arranged.start()
        }
    }
    Timer {
        id: arranged
        interval: 50
        onTriggered: {
            T.eq([quiet.visible, chip.visible], [true, true], "arranged, every part is there")
            T.eq(row.implicitWidth, quiet.width + clock.width + talking.width + chip.width + row.spacing * 3,
                 "and the strip is the whole list")
            T.finish("NotchStripTest")
        }
    }
}
