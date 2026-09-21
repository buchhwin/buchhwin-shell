import QtQuick
import qs.theme

// One animated size of the notch shape. Fast and Normal animation modes
// follow `to` with a spring (a little overshoot like the Dynamic Island),
// Reduced with a plain ease, Off jumps. The value never springs below
// `minimum` (the collapsed size), so collapsing settles without bobbing.
QtObject {
    id: root
    property real to: 0
    property real minimum: 0
    property real spring: to
    property real eased: to
    readonly property real value: Math.max(minimum, Animations.motionEnabled ? spring : Animations.enabled ? eased : to)

    Behavior on spring {
        enabled: Animations.motionEnabled
        SpringAnimation {
            spring: Animations.notchSpring
            damping: Animations.notchDamping
            mass: Animations.notchMass
            epsilon: Animations.notchEpsilon
        }
    }
    Behavior on eased {
        enabled: Animations.enabled && !Animations.motionEnabled
        NumberAnimation { duration: Animations.notchMorph; easing.type: Animations.easing }
    }
}
