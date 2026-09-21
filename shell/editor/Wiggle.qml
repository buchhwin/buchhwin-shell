import QtQuick
import qs.theme

// The small lean that says a tile can be picked up: put one in a tile and use
// its `angle` in a Rotation. Each tile gets a different point of the cycle from
// its index, because all of them in step looks mechanical rather than alive.
// Reduced and Off show the tile still: the frame around it already says it is
// editable, and a movement that cannot be turned off is what those modes exist
// to stop.
// An Item, not a Rotation with the animation inside it - a Rotation has no
// default property, so it cannot hold the Timer that offsets the phase.
Item {
    id: root
    required property int index
    property bool running: true

    readonly property bool active: running && Animations.motionEnabled
    // The animation owns `lean`, never `angle`: `angle` is a binding, so the
    // tile snaps flat the moment the mode changes.
    property real lean: 0
    property bool started: false
    readonly property real angle: active ? lean : 0

    visible: false
    width: 0
    height: 0

    // A Timer for the phase, not a pause inside the loop: the pause would
    // repeat every cycle instead of only offsetting the start.
    Timer {
        interval: (root.index % 6) * Math.round(Animations.wiggle / 6)
        running: root.active && !root.started
        onTriggered: root.started = true
    }

    SequentialAnimation on lean {
        running: root.active && root.started
        loops: Animation.Infinite
        NumberAnimation { to: Effects.wiggleAngle; duration: Math.round(Animations.wiggle / 4); easing.type: Animations.easing }
        NumberAnimation { to: -Effects.wiggleAngle; duration: Math.round(Animations.wiggle / 2); easing.type: Animations.easing }
        NumberAnimation { to: 0; duration: Math.round(Animations.wiggle / 4); easing.type: Animations.easing }
    }
}
