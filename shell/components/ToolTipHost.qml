import QtQuick
import qs.theme

// The machinery behind one tooltip, so that everything which can raise a
// bubble shares a single copy of it: the walk that finds the layer, the wait
// before showing, and the three ways a bubble has to be taken away again.
//
// It exists because the parts below are each a trap that has already been
// fallen into once, and two controls repeating them is two chances to get one
// of them wrong:
//
//   - **The walk happens when the pointer arrives, not at construction.** At
//     `Component.onCompleted` the window is not there yet, so the search finds
//     nothing and the control silently never shows a bubble again. That ended
//     an earlier attempt at tooltips entirely.
//   - **The timer is started and stopped by hand.** A `Timer` that does not
//     repeat clears its own `running` when it fires, so a binding on `running`
//     is torn down at the very moment it matters. That ate another attempt.
//   - **Every way out has to put the bubble back.** Leaving, being disabled,
//     being activated and being destroyed all end a tooltip, and a bubble left
//     behind by a control that no longer exists cannot be dismissed by
//     anything.
//
// The item the bubble points at is `anchorItem`, and it is the same item on
// the way in and the way out, because `ToolTipLayer.hide` refuses a request
// from anything that is not currently showing.
Item {
    id: root
    // What the bubble points at, and what identifies this tooltip to the
    // layer. The control itself, not this helper: the helper has no size.
    property Item anchorItem: parent
    property string text: ""
    // How long the pointer has to rest before the bubble appears.
    property int delay: Animations.toolTipDelay

    visible: false
    width: 0
    height: 0

    // The layer that draws the bubble, found by walking up. A window without
    // one shows nothing at all, which is what every window did before there
    // were layers.
    //
    // Not called `layer`: every Item already has one of those - Qt Quick's own
    // render-layer group - and shadowing it with a function makes the call
    // fail at runtime with "layer is not a function", not at load.
    function findLayer() {
        let node = root.anchorItem ? root.anchorItem.parent : null
        while (node) {
            if (node.toolTipLayer) return node.toolTipLayer
            node = node.parent
        }
        return null
    }

    // The pointer arrived. Nothing happens for a control with nothing to say.
    function arm() {
        if (root.text.length) wait.start()
    }

    // The pointer left, or the control was disabled, activated or destroyed.
    function release() {
        wait.stop()
        root.hide()
    }

    function show() {
        const found = findLayer()
        if (found) found.show(root.anchorItem, root.text)
    }

    function hide() {
        const found = findLayer()
        if (found) found.hide(root.anchorItem)
    }

    Timer {
        id: wait
        interval: root.delay
        onTriggered: root.show()
    }

    Component.onDestruction: root.hide()
}
