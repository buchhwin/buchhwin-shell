import Quickshell
import QtQuick
import qs.shell.components
import "Harness.js" as T

// The third tooltip attempt, held to account where it can be: the walk that
// finds the layer, which control may take the bubble away, and where the
// bubble is put. Whether it is *seen* cannot be tested here - a hover inside a
// panel's card does not register in a nested session (docs/testing.md).
ShellRoot {
    id: root

    // A window's content, with the layer named on an ancestor of it the way
    // ShellPanel names it on its card, and the buttons several levels down.
    Item {
        id: host
        width: 400
        height: 300
        readonly property Item toolTipLayer: layer

        Item {
            anchors.fill: parent
            Item {
                anchors.fill: parent
                ShellButton { id: button; x: 150; y: 20; icon: "x"; toolTip: "Explain me" }
                ShellButton { id: low; x: 20; y: 264; icon: "x"; toolTip: "Near the bottom" }
                ShellButton { id: edge; x: 390; y: 20; icon: "x"; toolTip: "Against the right edge" }
                ShellButton { id: silent; x: 20; y: 20; icon: "x" }
                // The "i" beside a setting's name raises the same bubble
                // through the same machinery, so it is held to the same
                // account. It is not a button and never acts.
                InfoTip { id: mark; x: 200; y: 60; text: "What this setting does" }
                InfoTip { id: unmarked; x: 240; y: 60; text: "" }
            }
        }
        ToolTipLayer { id: layer }
    }

    // An item with no layer anywhere above it, the way a window that has not
    // got one yet looks: asking must be harmless, not an error.
    ShellButton { id: orphan; icon: "x"; toolTip: "Nobody draws me" }

    Component.onCompleted: {
        T.eq(button.tipLayer(), layer, "a control finds the layer through every level above it")
        T.eq(orphan.tipLayer(), null, "and finds nothing where there is nothing")
        orphan.showTip()
        T.eq(layer.label, "", "a control with no layer shows nothing and breaks nothing")

        T.eq([layer.label, layer.target], ["", null], "the layer starts empty")
        button.showTip()
        T.eq([layer.label, layer.target === button], ["Explain me", true], "the control it belongs to")

        // Only the control that is showing may take it away, or a control the
        // pointer has already left closes the one that replaced it.
        low.hideTip()
        T.eq(layer.label, "Explain me", "another control cannot take the bubble away")
        button.hideTip()
        T.eq([layer.label, layer.target], ["", null], "its own control can")

        silent.showTip()
        T.eq(layer.label, "", "a control with nothing to say says nothing")

        // Where it lands.
        button.showTip()
        T.eq(layer.above, false, "there is room below a control near the top")
        T.near(layer.bubbleX + layer.bubbleWidth / 2, 150 + button.width / 2, "centred on the control", 0.5)
        T.ok(layer.bubbleY > 20 + button.height, "and below it")
        T.ok(layer.bubbleWidth > 0, "and it has been measured")
        T.ok(layer.bubbleX >= 4, "never off the left edge")

        silent.toolTip = "Against the left edge"
        silent.showTip()
        T.eq(layer.bubbleX, 4, "a control against the left edge clamps the bubble to the edge")
        silent.hideTip()
        silent.toolTip = ""

        edge.showTip()
        T.ok(layer.bubbleX + layer.bubbleWidth <= host.width, "nor off the right one")
        T.ok(layer.bubbleX + layer.bubbleWidth / 2 < 390 + edge.width / 2, "even where that means not being centred")

        low.showTip()
        T.eq(layer.above, true, "a control near the bottom is explained from above")
        T.ok(layer.bubbleY < low.y, "and the bubble sits over it")
        low.hideTip()

        // ---- the "i" after a setting's name ------------------------------

        // A name with nothing to explain gets no mark at all, which is the
        // whole point of moving the explanation out of the label: the column
        // says where there is something to read.
        T.eq(mark.visible, true, "a hint puts a mark after the name")
        T.eq(unmarked.visible, false, "no hint, no mark")
        T.ok(mark.implicitWidth > 0 && mark.implicitHeight > 0, "and the mark takes room, so the name does not jump when it appears")

        // Same layer, same walk, same bubble.
        T.eq(mark.findLayer(), layer, "the mark finds the same layer the buttons do")
        mark.show()
        T.eq([layer.label, layer.target === mark], ["What this setting does", true], "the mark raises the bubble and owns it")
        low.hideTip()
        T.eq(layer.label, "What this setting does", "and a control that is not showing cannot take it away")
        mark.hide()
        T.eq([layer.label, layer.target], ["", null], "the mark can")

        // A mark whose hint is taken away mid-hover must not leave a bubble
        // behind: nothing would be left to dismiss it.
        mark.show()
        T.eq(layer.label, "What this setting does", "showing again")
        mark.text = ""
        T.eq([layer.label, mark.visible], ["", false], "losing its hint takes the bubble with it")
        mark.text = "What this setting does"

        T.finish("ToolTipTest")
    }
}
