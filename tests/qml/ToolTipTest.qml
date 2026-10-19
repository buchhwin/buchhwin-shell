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
                InfoTip { id: other; x: 280; y: 60; text: "Another setting" }
            }
        }
        ToolTipLayer { id: layer }
    }

    // An item with no layer anywhere above it, the way a window that has not
    // got one yet looks: asking must be harmless, not an error.
    ShellButton { id: orphan; icon: "x"; toolTip: "Nobody draws me" }

    // A panel's window as ShellPanel builds it: the surface is the card and a
    // little room (300 x 200 here), the layer the whole screen, moved by the
    // surface's offset. A bubble kept inside the screen ran past the
    // surface's edge and was cut off.
    FloatingWindow {
        visible: true
        implicitWidth: 300
        implicitHeight: 200
        Item {
            id: stage
            x: -500
            y: -300
            width: 1920
            height: 1200
            readonly property Item toolTipLayer: shifted
            ShellButton { id: nearRight; x: 760; y: 330; icon: "x"; toolTip: "Dismiss all from this app, every one of them" }
            ShellButton { id: nearBottom; x: 600; y: 460; icon: "x"; toolTip: "Near the surface's bottom" }
            ToolTipLayer { id: shifted }
        }
    }
    Timer {
        id: windowed
        interval: 200
        onTriggered: {
            // ---- on the way out --------------------------------------------
            // A bubble fades where it was, saying what it said: it used to
            // jump to the window's corner as an empty plate for the whole fade.
            T.eq(layer.bubbleOpacity, 1, "the bubble is all there")
            const before = [layer.bubbleX, layer.bubbleY, layer.bubbleWidth]
            button.hideTip()
            T.eq([layer.label, layer.target], ["", null], "hidden, the layer holds nobody")
            T.ok(layer.visible, "while the bubble fades")
            T.eq([layer.bubbleX, layer.bubbleY, layer.bubbleWidth], before, "where it was, as wide as it was")
            T.eq(layer.shownLabel, "Explain me", "with its words")

            nearRight.showTip()
            T.ok(shifted.shownBounds.x === 500 && shifted.shownBounds.width === 300,
                 "the layer knows what part of it the window shows: " + JSON.stringify(shifted.shownBounds))
            T.ok(shifted.bubbleX + shifted.bubbleWidth <= 800 - 4 + 0.5,
                 "a bubble near the surface's right edge stays inside it: " + (shifted.bubbleX + shifted.bubbleWidth))
            T.ok(shifted.bubbleX >= 504, "and inside its left edge")
            nearRight.hideTip()
            nearBottom.showTip()
            T.eq(shifted.above, true, "a control near the surface's bottom is explained from above, not past it")
            nearBottom.hideTip()
            T.finish("ToolTipTest")
        }
    }

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

        // ---- the wait --------------------------------------------------------
        // One timer for the window, not one per control: the control under
        // the pointer starts it, every way out stops it, and only for itself.
        mark.arm()
        T.ok(layer.pending !== null, "the pointer arriving starts the layer's wait")
        mark.hide()
        T.eq(layer.pending, null, "and leaving stops it")
        mark.arm()
        const waiting = layer.pending
        other.arm()
        T.ok(layer.pending !== waiting && layer.pending !== null, "the next control under the pointer takes the wait over")
        mark.hide()
        T.ok(layer.pending !== null, "and the one the pointer left cannot stop it")
        other.hide()
        T.eq(layer.pending, null, "its own control can")
        silent.showTip()
        T.eq(layer.pending, null, "a control with nothing to say waits for nothing")

        // Shown now and taken away once it is all there (the timer below).
        button.showTip()
        windowed.start()
    }
}
