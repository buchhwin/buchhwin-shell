import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.shell.widgets
import "Harness.js" as T

// The notch and the pill bar stay mapped under a fullscreen window and hide
// their content instead (Notch.qml and PillBar.qml, `active`): unmapping
// destroyed the window and its GL context on every fullscreen toggle. Under
// the hidden content every item's `visible` reads false, so nothing that
// sizes the strip or a pill may be measured from it - the notch's collapsed
// width and a pill's width spring would follow the hidden surface down and
// spring back on its return. Positioners and layouts go by the explicit flag;
// ClockWidget read its lines' `visible` and has its own conditions now.
ShellRoot {
    id: root
    property var before: ({})

    function sizes() {
        return { row: row.implicitWidth, rowLayout: rowLayout.implicitWidth,
                 widget: widget.implicitWidth, clock: clock.implicitWidth, clockHeight: clock.implicitHeight }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 240

        Item {
            id: content
            Row {
                id: row
                spacing: 4
                Rectangle { width: 30; height: 10 }
                Rectangle { width: 40; height: 10 }
            }
            RowLayout {
                id: rowLayout
                spacing: 4
                Rectangle { implicitWidth: 30; implicitHeight: 10 }
                Rectangle { implicitWidth: 40; implicitHeight: 10 }
            }
            WidgetBase { id: widget; sizeClass: "large"; icon: "x"; label: "42%"; detail: "2 h left" }
            // A pill's clock with its date line (display "expanded"): the
            // line is wider than the time, so a width measured from its
            // `visible` would shrink while hidden.
            ClockWidget { id: clock; inGroup: true; sizeClass: "expanded" }
        }
    }

    Timer {
        id: measure
        interval: 100
        running: true
        onTriggered: {
            root.before = root.sizes()
            T.ok(root.before.row > 0 && root.before.rowLayout > 0 && root.before.widget > 0, "measured while shown")
            T.ok(clock.detailShown, "the pill clock shows its date line")
            content.visible = false
            hidden.start()
        }
    }
    Timer {
        id: hidden
        interval: 50
        onTriggered: {
            T.ok(!clock.visible, "the content reads as hidden")
            const after = root.sizes()
            T.eq(after.row, root.before.row, "a Row keeps its width under a hidden parent")
            T.eq(after.rowLayout, root.before.rowLayout, "and a RowLayout")
            T.eq(after.widget, root.before.widget, "and a widget (a GridLayout)")
            T.eq(after.clock, root.before.clock, "and the clock: its date line is still counted")
            T.eq(after.clockHeight, root.before.clockHeight, "in height too")
            content.visible = true
            T.eq(root.sizes(), root.before, "shown again, nothing moved")
            T.finish("HiddenContentTest")
        }
    }
}
