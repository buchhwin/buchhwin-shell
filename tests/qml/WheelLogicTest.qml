import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../shell/components/WheelLogic.js" as W

// A step is a distance, not an event: a wheel notch is one step however it
// is sliced, and a touchpad swipe is as many steps as the fingers travel -
// replayed from a real recording, where one step per event had taken the
// volume from 30 to 100 % in the shortest swipe. Then a slider's share of
// it: a swipe goes on to the page unless Ctrl is held, the wheel moves only
// a slider that has the focus. Pure logic: no service, no window.
ShellRoot {
    FileView { id: swipes; path: Qt.resolvedUrl("../fixtures/touchpad-swipes.txt").toString().replace("file://", ""); blockLoading: true }

    // Feeds `events` ([phase, angle, pixels]) through one carry; the steps
    // each made, in order.
    function feed(events) {
        let carry = null
        const made = []
        for (const event of events) {
            carry = W.step(carry, event[0], event[1], event[2])
            made.push(carry.steps)
        }
        return made
    }
    function sum(list) { return list.reduce((total, value) => total + value, 0) }

    Component.onCompleted: {
        T.eq([W.NO_PHASE, W.BEGIN, W.UPDATE, W.END, W.MOMENTUM],
             [Qt.NoScrollPhase, Qt.ScrollBegin, Qt.ScrollUpdate, Qt.ScrollEnd, Qt.ScrollMomentum],
             "the phases are Qt's own numbers")

        // ---- a wheel: one step per notch of 120 ------------------------------
        // Qt on Wayland gives a notch a pixelDelta of 15 as well; without a
        // phase it is a wheel, and the pixels are not read.
        T.eq(feed([[W.NO_PHASE, 120, 15]]), [1], "one notch up is one step")
        T.eq(feed([[W.NO_PHASE, -120, -15]]), [-1], "one notch down is one step down")
        T.eq(feed([[W.NO_PHASE, 120, 15], [W.NO_PHASE, 120, 15], [W.NO_PHASE, 120, 15]]), [1, 1, 1],
             "three notches are three steps")
        T.eq(feed([[W.NO_PHASE, 240, 30]]), [2], "two notches in one event are two")
        const fine = [0, 1, 2, 3, 4, 5, 6, 7].map(() => [W.NO_PHASE, 15, 0])
        T.eq(feed(fine), [0, 0, 0, 0, 0, 0, 0, 1], "a high-resolution wheel's eight eighths are one step, at the last")
        T.eq(feed([[W.NO_PHASE, 60, 0], [W.NO_PHASE, 60, 0]]), [0, 1], "two half notches are one step")
        T.eq(feed([[W.NO_PHASE, 60, 0], [W.NO_PHASE, -120, 0]]), [0, -1],
             "turning back starts afresh: half up and a notch down is a step down")
        T.eq(feed([[W.NO_PHASE, 0, 0]]), [0], "a sideways turn is no step")
        const kept = W.step({ steps: 0, remainder: 90, finger: false }, W.NO_PHASE, 0, 0)
        T.eq(kept.remainder, 90, "and leaves what was carried alone")

        // ---- a touchpad: one step per FINGER_STEP of travel ------------------
        T.eq(W.step({ steps: 0, remainder: 30, finger: true }, W.BEGIN, 0, 0),
             { steps: 0, remainder: 0, finger: true }, "a swipe's begin starts the count afresh")
        T.eq(W.step({ steps: 0, remainder: 30, finger: true }, W.END, 0, 0).remainder, 0, "and so does its end")
        T.eq(feed([[W.BEGIN, 0, 0], [W.UPDATE, 240, 20], [W.UPDATE, 240, 20], [W.END, 0, 0]]), [0, 0, 1, 0],
             "40 px of finger travel is one step, whatever the angle says")
        T.eq(feed([[W.UPDATE, -480, -40]]), [-1], "the other way, the other sign")
        T.eq(W.step(null, W.UPDATE, 96, 8, 4).steps, 2, "the travel per step is the caller's to choose")
        T.eq(feed([[W.NO_PHASE, 60, 0], [W.UPDATE, 0, 30]]), [0, 0],
             "a wheel's half notch is not carried into a swipe's pixels")

        // The recording: eleven real swipes of 12 to 41 updates each.
        const lines = swipes.text().split("\n").filter(line => line.length && line[0] !== "#")
        const events = lines.map(line => line.split(" ").map(Number))
        T.eq(events.length, 328, "the recording is all there")
        const perSwipe = []
        let current = null
        let carry = null
        for (const event of events) {
            if (event[0] === W.BEGIN && (current === null || current.updates > 0)) {
                current = { updates: 0, steps: 0, travel: 0 }
                perSwipe.push(current)
            }
            carry = W.step(carry, event[0], event[1], event[2])
            if (event[0] === W.UPDATE && event[1] !== 0) current.updates += 1
            if (event[0] === W.UPDATE) current.travel += event[2]
            current.steps += carry.steps
        }
        T.eq(perSwipe.length, 11, "eleven swipes")
        T.eq(perSwipe.map(swipe => swipe.updates), [41, 37, 33, 33, 27, 27, 25, 18, 16, 12, 15],
             "of 12 to 41 updates each, every one of which used to be a step")
        T.ok(perSwipe.every(swipe => swipe.steps <= -3 && swipe.steps >= -9),
             "each swipe is 3 to 9 steps now: " + JSON.stringify(perSwipe.map(swipe => swipe.steps)))
        T.ok(perSwipe.every(swipe => Math.abs(swipe.steps) === Math.floor(Math.abs(swipe.travel) / W.FINGER_STEP)),
             "as many as the fingers travelled, nothing lost between updates")
        T.ok(perSwipe.every(swipe => swipe.steps * 0.05 >= -0.45),
             "so a swipe moves the volume by at most 45 %, where the shortest went 60 % before")

        // ---- a slider ------------------------------------------------------------
        const off = W.sliderStep(null, W.NO_PHASE, 120, 15, false, false)
        T.eq([off.taken, off.steps], [false, 0], "the wheel passes over a slider without the focus")
        const ctrl = W.sliderStep(null, W.NO_PHASE, 120, 15, false, true)
        T.eq([ctrl.taken, ctrl.steps], [true, 1], "unless Ctrl is held")
        const focused = W.sliderStep(null, W.NO_PHASE, -120, -15, true, false)
        T.eq([focused.taken, focused.steps], [true, -1], "a focused slider takes a notch as one step")
        let sliced = null
        const slices = []
        for (let i = 0; i < 8; ++i) {
            const answer = W.sliderStep(sliced, W.NO_PHASE, 15, 0, true, false)
            sliced = answer.carry
            slices.push(answer.taken ? answer.steps : "handed on")
        }
        T.eq(slices, [0, 0, 0, 0, 0, 0, 0, 1], "and keeps a fine wheel's eighths until they make one")
        const swipe = W.sliderStep(null, W.UPDATE, -100, -8, true, false)
        T.eq([swipe.taken, swipe.steps], [false, 0], "a swipe over a focused slider goes on to the page")
        const held = W.sliderStep(null, W.UPDATE, 480, 40, true, true)
        T.eq([held.taken, held.steps], [true, 1], "with Ctrl it is the slider's, by distance")
        T.eq(W.sliderStep(null, W.BEGIN, 0, 0, true, true).taken, false, "a swipe's begin is every list's news")
        T.eq(W.sliderStep(null, W.END, 0, 0, true, true).taken, false, "and so is its end")
        T.eq(W.sliderStep(null, W.NO_PHASE, 0, 0, true, false).taken, false, "a sideways wheel is not the slider's")

        T.finish("WheelLogicTest")
    }
}
