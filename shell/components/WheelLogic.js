.pragma library

// How many steps a wheel event makes on something that moves in steps - the
// volume pill, a slider - rather than scrolling by pixels like a list
// (ScrollLogic.js does that).
//
// One step per *event* was wrong for both kinds of input. A two-finger swipe
// on this laptop's touchpad arrives as 12 to 41 updates (recorded live,
// 16.10.: tests/fixtures/touchpad-swipes.txt), and every one of them was a
// 5 % step, so the shortest swipe moved the volume by 60 % and most ran into
// 0 or 100. A high-resolution wheel sends eighths of a notch, and each eighth
// was a whole step as well. So a step is a *distance* now, and what is short
// of one is carried to the next event:
//
//   - a wheel (no scroll phase) by its angle: one step per notch of 120,
//     however it is sliced;
//   - a touchpad (a swipe's ScrollBegin, ScrollUpdate, ScrollEnd) by the
//     finger's travel in pixels: one step per FINGER_STEP. Its angle is no
//     use - Qt makes it twelve times the pixels, which would still be ~27
//     steps a swipe. What tells the two apart is the phase and nothing else:
//     Qt on Wayland gives a notch a pixelDelta of 15 too (testing.md 93).
//
// A swipe's begin and end start the count afresh, and so does turning the
// other way: half a notch up and then a notch down is one step down, not
// half of one.

// Qt.ScrollPhase by number, so plain objects can stand in for events (and
// WheelLogicTest holds them to Qt's own values).
var NO_PHASE = 0
var BEGIN = 1
var UPDATE = 2
var END = 3
var MOMENTUM = 4

// One detent of a wheel in Qt's angleDelta: eighths of a degree, 15 degrees
// a notch.
var NOTCH = 120
// Finger travel per step, in the compositor's pixels. The recorded swipes
// travel 184 to 350 px, which makes 4 to 8 steps: a fifth to two fifths of
// the range for a whole swipe, and one step for a short push.
var FINGER_STEP = 40

// `carry` is what the previous call returned (null to start); `angle` and
// `pixels` are the event's angleDelta and pixelDelta along the axis that
// steps (y). Returns { steps, remainder, finger }: whole steps, positive
// for up (a wheel turned away, fingers pushed up), and what is left over
// for the next event.
function step(carry, phase, angle, pixels, fingerStep) {
    if (phase === BEGIN || phase === END) return { steps: 0, remainder: 0, finger: true }
    const finger = phase === UPDATE || phase === MOMENTUM
    const distance = Number(finger ? pixels : angle) || 0
    const unit = finger ? (fingerStep > 0 ? fingerStep : FINGER_STEP) : NOTCH
    // Angle and pixels are different units: what one kind left over says
    // nothing to the other.
    let rest = carry && carry.finger === finger ? Number(carry.remainder) || 0 : 0
    if (distance === 0) return { steps: 0, remainder: rest, finger: finger }
    if (rest * distance < 0) rest = 0
    const total = rest + distance
    const steps = total > 0 ? Math.floor(total / unit) : -Math.floor(-total / unit)
    return { steps: steps, remainder: total - steps * unit, finger: finger }
}

// What a slider does with one wheel event: { taken, steps, carry }. A page
// scrolled with a slider on it must not move the slider it passes over, so
// a wheel moves only a slider that was used before (it has the focus) or
// one under Ctrl. A swipe is handed on unless Ctrl is held: its updates come
// as long as the fingers move, and a focused slider under a resting pointer
// took them all - the page around it is what a swipe means to scroll (the
// list's ScrollFeel takes it then). A swipe's begin and end are always
// handed on, because every list under the pointer keeps its own books on
// them, and so is an event that turned nothing along the slider's axis.
function sliderStep(carry, phase, angle, pixels, focused, ctrl) {
    if (phase === BEGIN || phase === END) return { taken: false, steps: 0, carry: null }
    const finger = phase !== NO_PHASE
    if (!ctrl && !(focused && !finger)) return { taken: false, steps: 0, carry: carry }
    if (!(Number(angle) || 0) && !(finger && (Number(pixels) || 0)))
        return { taken: false, steps: 0, carry: carry }
    const next = step(carry, phase, angle, pixels)
    return { taken: true, steps: next.steps, carry: next }
}
