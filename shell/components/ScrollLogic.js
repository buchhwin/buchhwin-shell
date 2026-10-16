.pragma library

// The arithmetic of ScrollFeel.qml - how far a wheel notch or a touchpad
// swipe moves a list, where a list may rest, and how a fling dies away - apart
// from the component so it can be held to account without a pointer.
//
// Why there is any arithmetic at all: Qt's own Flickable scrolled the shell's
// lists far less than a browser does with the same hand. Measured 16.10. in a
// nested session with the same virtual input sent to every client (review
// baseline, "Scroll"): one wheel notch moved the Flickable 72 px (three lines
// of 24 - `Qt.styleHints.wheelScrollLines`, which QML cannot change), Chrome
// 120 and Firefox 132; a 300-unit two-finger swipe moved the Flickable 510-611
// px and the browsers 2100-2640.

// Qt's angleDelta for one detent of a wheel: eighths of a degree, 15 degrees
// a notch. A high-resolution wheel sends fractions of it, which scroll the
// same fraction of a notch.
var NOTCH = 120
// How much finger movement the speed at release is read from, in ms. Long
// enough for several events of a touchpad's stream, short enough that the
// start of a swipe does not count against how it ended.
var SAMPLE_WINDOW = 100
// Fingers that stood still this long before they lifted meant to stop there:
// no fling. A stream that is still moving has an event every 8-17 ms.
var REST = 60
// Below this speed, in px/s, a lift is a stop and not a throw.
var FLING_MIN = 150
// A fling slower than this, in px/s, has ended; what is left of it is under
// a twentieth of a pixel per frame.
var STOP_SPEED = 20
// Closer than this to a bound is at it: positions are reals, and a list
// half a pixel short of its end has nowhere left to go.
var EPSILON = 0.5

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

// How far one wheel event moves the content, in pixels, positive towards the
// end (down, right). Qt's angleDelta is positive for a wheel turned away from
// the user, which scrolls up - hence the sign.
function wheelPixels(angleDelta, perNotch) {
    return -angleDelta / NOTCH * perNotch
}

// How far one touchpad event moves it: the compositor's pixels times the
// factor, in the direction the compositor sends them. Natural scrolling is
// already in that sign (the compositor flips it), so nothing here reads
// `inverted` - neither do the browsers, nor Qt's Flickable.
function fingerPixels(pixelDelta, factor) {
    return -pixelDelta * factor
}

// Where a view may rest along one axis: from its origin less the leading
// margin to the end of its content plus the trailing margin, less what the
// view shows. Flickable's own bounds. A ListView or GridView moves its origin
// as delegates of other sizes come and go, which is why it is not just 0.
function range(origin, content, size, startMargin, endMargin) {
    const low = origin - startMargin
    return { low: low, high: Math.max(low, origin + content + endMargin - size) }
}

// Whether a step of `delta` from `position` has anywhere to go. This is the
// test for handing the wheel on: a list at its end lets the event go to the
// list or page around it, the way Flickable does.
function hasRoom(position, delta, low, high) {
    if (delta > 0) return position < high - EPSILON
    if (delta < 0) return position > low + EPSILON
    return false
}

// One UI's curve for a glide (Animations.easing, OutCubic): fast off the mark,
// a soft landing.
function easeOut(progress) {
    const rest = 1 - clamp(progress, 0, 1)
    return 1 - rest * rest * rest
}

// Where a glide from `from` to `to` is after `elapsed` of `duration` ms.
function easedAt(from, to, elapsed, duration) {
    if (duration <= 0 || elapsed >= duration) return to
    return from + (to - from) * easeOut(elapsed / duration)
}

// A fling slows down like a puck on ice: its speed falls by the same share in
// every moment (`decay` is the time constant in ms), so it covers velocity x
// decay in all and most of it at once. Velocity in px/s, times in ms.
function flingOffset(velocity, decay, elapsed) {
    if (decay <= 0) return 0
    return velocity * decay / 1000 * (1 - Math.exp(-elapsed / decay))
}

function flingSpeed(velocity, decay, elapsed) {
    if (decay <= 0) return 0
    return velocity * Math.exp(-elapsed / decay)
}

function flingDistance(velocity, decay) {
    return Math.max(0, decay) / 1000 * velocity
}

function flingDone(velocity, decay, elapsed) {
    return Math.abs(flingSpeed(velocity, decay, elapsed)) < STOP_SPEED
}

// The speed the fingers had as they lifted, in px/s, from the samples
// `{ t, d }` (time in ms, content pixels already scaled) the swipe left: the
// distance of the last SAMPLE_WINDOW over the time it took, capped at `cap`.
// Nothing if the fingers rested before they lifted, if there is too little
// to measure, or if it is too slow to be a throw.
function releaseVelocity(samples, now, cap) {
    if (!samples || samples.length < 2) return 0
    const last = samples[samples.length - 1]
    if (now - last.t > REST) return 0
    const recent = samples.filter(sample => now - sample.t <= SAMPLE_WINDOW)
    if (recent.length < 2) return 0
    const span = recent[recent.length - 1].t - recent[0].t
    if (span <= 0) return 0
    // The first sample only starts the clock: its distance was covered
    // before the window began.
    let distance = 0
    for (let i = 1; i < recent.length; ++i) distance += recent[i].d
    const velocity = clamp(distance / span * 1000, -cap, cap)
    return Math.abs(velocity) < FLING_MIN ? 0 : velocity
}

// The samples worth keeping after one more: the window's worth and the one
// just before it, which starts the window's clock.
function keepSamples(samples, sample) {
    const kept = samples.filter(old => sample.t - old.t <= SAMPLE_WINDOW * 2)
    kept.push(sample)
    return kept
}

// Where a whole gesture lands, for the notes and the tests: `steps` events of
// `units / steps` compositor pixels, `interval` ms apart, then the lift.
function swipeLands(units, steps, interval, factor, cap, decay) {
    let samples = []
    let moved = 0
    for (let i = 0; i < steps; ++i) {
        const d = fingerPixels(-units / steps, factor)
        moved += d
        samples = keepSamples(samples, { t: i * interval, d: d })
    }
    const velocity = releaseVelocity(samples, (steps - 1) * interval + interval, cap)
    return moved + flingDistance(velocity, decay)
}
