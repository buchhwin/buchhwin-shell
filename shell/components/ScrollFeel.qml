import QtQuick
import qs.theme
import qs.services
import "ScrollLogic.js" as Logic

// A browser's scrolling for one Flickable, ListView or GridView: a wheel
// notch moves the list 120 px in a short glide (notches that come quickly add
// up), a two-finger swipe moves it four times the touchpad's pixels and
// throws it a little further when the fingers lift. Qt's Flickable moved 72 px
// a notch and the touchpad one to one, which is why Settings felt slow next
// to the browser (ScrollLogic.js has the numbers).
//
//     Flickable { id: list; ...; ScrollFeel { view: list } }
//
// Declared inside the view it lands in the view's content item, and that is
// the point: it has to see the wheel *after* everything in the list - an
// inner list, a slider that has the focus, an open select - and *before* the
// view itself. Qt hands the wheel to the topmost item under the pointer
// first, then down through its parents; an item with a negative z comes
// after its parent, so this one, under the content item, is asked after the
// rows and before the Flickable. A WheelHandler cannot do the same: it keeps
// every event it is shown, so a list at its end could not let the page around
// it scroll on (tried offscreen, 16.10.).
//
// The way back to Qt's own scrolling: `input.browserScroll: false` in
// settings.json for all of them, `enabled: false` for one. Disabled, this
// receives nothing and the Flickable scrolls the way it always did.
MouseArea {
    id: feel

    // The view this scrolls.
    required property Flickable view

    // The theme's numbers, here so a view or a probe can differ.
    property real notch: Metrics.scrollNotch
    property real fingerFactor: Metrics.scrollFingerFactor
    // 0 jumps: Reduced and Off (Animations.scroll).
    property int duration: Animations.scroll
    property bool fling: Animations.motionEnabled
    property int flingDecay: Animations.scrollFling
    property real flingMax: Metrics.scrollFlingMax

    // True while this moves the list, and a moment after: the "more below"
    // hints light up for it the way they do for a Flickable's `moving`, which
    // a position set from here never sets.
    readonly property bool scrolling: ticker.running || settle.running

    // Over what the view shows, wherever its content has been scrolled to.
    parent: view ? view.contentItem : null
    x: view ? view.contentX : 0
    y: view ? view.contentY : 0
    width: view ? view.width : 0
    height: view ? view.height : 0
    z: -1
    enabled: view !== null && view.interactive && SettingsService.value("input.browserScroll") !== false
    // Only the wheel: presses, drags and hover belong to the rows and to the
    // Flickable's own dragging.
    acceptedButtons: Qt.NoButton

    // One axis's motion: a glide to `to` (wheel), a fling, or nothing. `last`
    // is where this put the list last, so a move from anywhere else - keys,
    // positionViewAtIndex, a drag at the edge - is seen and wins.
    property var motions: ({
        y: { kind: "", from: 0, to: 0, start: 0, velocity: 0, last: 0 },
        x: { kind: "", from: 0, to: 0, start: 0, velocity: 0, last: 0 }
    })
    // The current swipe's movement per axis, for the speed it lifts at.
    property var samples: ({ y: [], x: [] })

    function now() { return Date.now() }

    function position(axis) { return axis === "y" ? view.contentY : view.contentX }
    function place(axis, value) {
        if (axis === "y") view.contentY = value
        else view.contentX = value
        motions[axis].last = position(axis)
    }
    function bounds(axis) {
        return axis === "y"
            ? Logic.range(view.originY, view.contentHeight, view.height, view.topMargin, view.bottomMargin)
            : Logic.range(view.originX, view.contentWidth, view.width, view.leftMargin, view.rightMargin)
    }
    // The axes the view scrolls along. An automatic direction may be either;
    // the bounds decide (a plain Flickable without a contentWidth has no room
    // across), so a sideways wheel stays Qt's unless the view scrolls sideways.
    function flicks(axis) {
        const direction = view.flickableDirection
        if (direction === Flickable.AutoFlickDirection || direction === Flickable.AutoFlickIfNeeded) return true
        return (direction & (axis === "y" ? Flickable.VerticalFlick : Flickable.HorizontalFlick)) !== 0
    }

    function stop(axis) {
        motions[axis].kind = ""
    }
    function stopAll() {
        stop("y")
        stop("x")
        ticker.running = false
    }

    // A wheel notch along one axis. "moved", "kept" (the list is still
    // gliding to the end this asks for: the wheel stays with it, as it stays
    // with a Flickable until its content is there) or "" (nowhere to go: hand
    // it on).
    function wheelAxis(axis, angle) {
        if (angle === 0 || !flicks(axis)) return ""
        const motion = motions[axis]
        const range = bounds(axis)
        const here = position(axis)
        const delta = Logic.wheelPixels(angle, feel.notch)
        const gliding = motion.kind === "ease"
        const base = gliding ? motion.to : here
        if (!Logic.hasRoom(base, delta, range.low, range.high))
            return gliding && Logic.hasRoom(here, delta, range.low, range.high) ? "kept" : ""
        const to = Logic.clamp(base + delta, range.low, range.high)
        if (feel.duration <= 0) {
            stop(axis)
            place(axis, to)
            return "moved"
        }
        motion.kind = "ease"
        motion.from = here
        motion.to = to
        motion.start = now()
        motion.last = here
        ticker.running = true
        return "moved"
    }

    // A touchpad event along one axis: the list follows the fingers at once.
    function fingerAxis(axis, pixels) {
        if (!flicks(axis)) return ""
        // Fingers on the pad again take over from a fling.
        stop(axis)
        if (pixels === 0) return samples[axis].length > 0 ? "kept" : ""
        const range = bounds(axis)
        const here = position(axis)
        const delta = Logic.fingerPixels(pixels, feel.fingerFactor)
        if (!Logic.hasRoom(here, delta, range.low, range.high)) return ""
        place(axis, Logic.clamp(here + delta, range.low, range.high))
        samples[axis] = Logic.keepSamples(samples[axis], { t: now(), d: delta })
        return "moved"
    }

    // The fingers lifted: throw the list on at the speed they had.
    function release(axis) {
        const velocity = feel.fling ? Logic.releaseVelocity(samples[axis], now(), feel.flingMax) : 0
        samples[axis] = []
        if (velocity === 0) return
        const motion = motions[axis]
        motion.kind = "fling"
        motion.from = position(axis)
        motion.velocity = velocity
        motion.start = now()
        motion.last = motion.from
        ticker.running = true
    }

    // Everything a wheel event can be. Returns whether it was used; the
    // caller hands it on when it was not. Plain objects with the same fields
    // will do, which is how the tests drive it.
    function handle(event) {
        if (!view) return false
        const phase = event.phase
        // A swipe starting and ending are news for every list under the
        // pointer, the Flickables included (they keep their own books on
        // them), so neither is ever kept here.
        if (phase === Qt.ScrollBegin) {
            stopAll()
            samples = { y: [], x: [] }
            return false
        }
        if (phase === Qt.ScrollEnd) {
            release("y")
            release("x")
            return false
        }
        // A touchpad's stream comes in phases (begin, updates, end - the
        // compositor's axis_stop); a wheel's notches come without one. The
        // pixelDelta says nothing: Qt on Wayland fills it for a notch too
        // (15 per detent, measured live 16.10.), and taken as a swipe that
        // made a notch half a browser's.
        const finger = phase === Qt.ScrollUpdate || phase === Qt.ScrollMomentum
        const results = finger
            ? [fingerAxis("y", event.pixelDelta.y), fingerAxis("x", event.pixelDelta.x)]
            : [wheelAxis("y", event.angleDelta.y), wheelAxis("x", event.angleDelta.x)]
        const used = results.some(result => result.length > 0)
        if (used) settle.restart()
        return used
    }

    onWheel: event => { event.accepted = feel.handle(event) }

    // Turned off, or the view stopped taking input (the launcher while it is
    // arranged): nothing of this may keep moving it.
    onEnabledChanged: if (!enabled) stopAll()

    // One step per frame of whatever is moving, and only while something is.
    FrameAnimation {
        id: ticker
        running: false
        onTriggered: feel.step()
    }
    function step() {
        if (!view) {
            stopAll()
            return
        }
        const time = now()
        let busy = false
        for (const axis of ["y", "x"]) {
            const motion = motions[axis]
            if (!motion.kind) continue
            if (Math.abs(position(axis) - motion.last) > Logic.EPSILON) {
                stop(axis)
                continue
            }
            const elapsed = time - motion.start
            const range = bounds(axis)
            let next = motion.kind === "ease"
                ? Logic.easedAt(motion.from, motion.to, elapsed, feel.duration)
                : motion.from + Logic.flingOffset(motion.velocity, feel.flingDecay, elapsed)
            let done = motion.kind === "ease" ? elapsed >= feel.duration
                : Logic.flingDone(motion.velocity, feel.flingDecay, elapsed)
            // The end of the list stops a glide and a fling alike.
            const held = Logic.clamp(next, range.low, range.high)
            if (held !== next) done = true
            place(axis, held)
            if (done) stop(axis)
            else busy = true
        }
        if (!busy) ticker.running = false
    }

    // `scrolling` outlasts the last event by a hover's time, so the hint does
    // not blink between the notches of one turn of the wheel.
    Timer {
        id: settle
        interval: Math.max(Animations.hover, feel.duration)
    }
}
