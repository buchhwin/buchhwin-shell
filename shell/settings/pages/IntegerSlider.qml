import QtQuick
import qs.shell.components
import "../../../services/settings/WholeStepLogic.js" as Step

// A ShellSlider for a whole number. `picked` hands the page the value a
// gesture ended on (WholeStepLogic.whole): a drag the nearest whole number, an
// arrow key or a wheel notch at least one step on. Stored rounded, the
// slider's own twentieth-of-the-range step went nowhere on a short range.
ShellSlider {
    id: root
    signal picked(int value)

    // Whether the gesture that ends now was a drag. The pointer moves the
    // value while the slider is pressed; a key and the wheel move it in one
    // go (moved, then released) while it is not.
    property bool dragged: false
    onMoved: root.dragged = root.pressed
    onReleased: value => {
        const dragged = root.dragged
        root.dragged = false
        root.picked(Step.whole(root.value, value, dragged, root.from, root.to))
    }
}
