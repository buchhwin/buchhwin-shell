import QtQuick
import qs.theme

// A spring for a Behavior on something that moves, with the session's
// values (theme/Animations.qml, scaled by the speed setting):
//
//   Behavior on x { enabled: Animations.motionEnabled; SpringMotion { kind: "fast" } }
//
// The Behavior carries the guard: Reduced and Off jump, the way a timed
// movement did with Animations.move(...) at 0. Not for opacity or colour,
// which have no ground to cover and stay timed; nor for anything a timer
// waits on, because a spring has no duration to wait for.
SpringAnimation {
    property string kind: "standard"
    // How close counts as arrived. A quarter pixel suits positions and sizes;
    // a value that lives between 0 and 1 (a slider's ratio) needs a finer one.
    property real precision: params.epsilon
    readonly property var params: Animations.spring(kind)
    spring: params.spring
    damping: params.damping
    mass: params.mass
    epsilon: precision
}
