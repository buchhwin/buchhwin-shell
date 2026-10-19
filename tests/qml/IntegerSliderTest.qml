import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/settings/WholeStepLogic.js" as Step

// Whole-number sliders (Border width 1-8, Gap between windows 0-30, the
// workspace count 1-10): an arrow key or a wheel notch moves at least one,
// evenly both ways, and a drag lands on the nearest whole number. Before,
// the slider's own step (a twentieth of the range) was rounded back by the
// page and Right never moved Border width at all.
ShellRoot {
    id: root
    property int border: 2
    property int gaps: 5
    property int picks: 0

    FloatingWindow {
        implicitWidth: 300
        implicitHeight: 200
        visible: true
        Column {
            IntegerSlider {
                id: borderSlider
                width: 220
                from: 1; to: 8
                value: root.border
                onPicked: value => { root.picks += 1; root.border = value }
            }
            IntegerSlider {
                id: gapSlider
                width: 220
                from: 0; to: 30
                value: root.gaps
                onPicked: value => root.gaps = value
            }
        }
    }

    Component.onCompleted: {
        // The rule.
        T.eq(Step.whole(2, 2.35, false, 1, 8), 3, "a key step under one unit moves one up")
        T.eq(Step.whole(2, 1.65, false, 1, 8), 1, "and one down")
        T.eq([Step.whole(5, 6.5, false, 0, 30), Step.whole(5, 3.5, false, 0, 30)], [7, 3], "a step of 1.5 moves two, both ways")
        T.eq([Step.whole(5, 8, false, 0, 60), Step.whole(5, 2, false, 0, 60)], [8, 2], "a whole step as it is")
        T.eq([Step.whole(8, 8, false, 1, 8), Step.whole(1, 1, false, 1, 8)], [8, 1], "nothing past either end")
        T.eq([Step.whole(4, 1, false, 1, 8), Step.whole(4, 8, false, 1, 8)], [1, 8], "Home and End reach the ends")
        T.eq([Step.whole(2, 2.4, true, 1, 8), Step.whole(2, 2.6, true, 1, 8), Step.whole(2, 9, true, 1, 8)], [2, 3, 8],
             "a drag lands on the nearest whole number, within the range")
        T.eq(Step.whole(undefined, 3.7, false, 1, 8), 4, "no stored value: the nearest")

        // The real slider, through its own keys and wheel.
        for (let i = 0; i < 3; ++i) borderSlider.Keys.rightPressed(null)
        T.eq(root.border, 5, "three Right presses on Border width: 2 -> 5")
        for (let i = 0; i < 2; ++i) borderSlider.Keys.leftPressed(null)
        T.eq(root.border, 3, "two Left presses: back to 3")
        borderSlider.commit(borderSlider.wheelTarget(1))
        T.eq(root.border, 4, "a wheel notch moves one too")
        for (let i = 0; i < 10; ++i) borderSlider.Keys.rightPressed(null)
        T.eq(root.border, 8, "and the keys stop at the end")
        gapSlider.Keys.rightPressed(null)
        T.eq(root.gaps, 7, "Gap between windows: Right moves two")
        gapSlider.Keys.leftPressed(null)
        T.eq(root.gaps, 5, "and Left the same two back")

        // A drag: the slider was pressed while it moved.
        const before = root.picks
        borderSlider.dragged = true
        borderSlider.released(3.4)
        T.eq([root.border, root.picks - before, borderSlider.dragged], [3, 1, false], "a drag's release picks the nearest, once")
        T.finish("IntegerSliderTest")
    }
}
