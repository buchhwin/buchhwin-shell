.pragma library

// The one rule that both halves of the session have to obey: a motion that
// covers ground may not be scaled below ten frames.
//
// It lives here rather than in theme/Animations.qml because the compositor
// needs it too (services/hypr/HyprAnimations.js) and a rule written twice is a
// rule that drifts. Unit tested, because "what does 1.5x do to a 340 ms panel"
// is arithmetic and not something a nested session can show.
//
// Why a floor at all: the durations used to enforce it themselves - nothing in
// the table was under ten frames at 1x. That held until the speed setting
// arrived, which *divides* what the table had already chosen. A session at
// 1.5x was back to a 227 ms panel, which is the duration that was measured as
// too fast for the ground it covers and replaced by 340 in the first place. A
// floor written into the constants is not a floor; it has to sit behind the
// division.

// Ten frames at 60 Hz, in milliseconds. 60 Hz because that is what the panel
// this was measured on runs at, and because a floor chosen for the slowest
// refresh rate in the room is the one that is always enough.
var FLOOR_MS = 167

// Hyprland counts its `speed` in deciseconds, so the same ten frames are 1.67.
var FLOOR_SPEED = 1.67

// And a second floor, because the first one turned out not to be the rule it
// was written to be. Ten frames is a floor on *visibility*: below it a motion
// stops being one picture after another. It is not a floor on the ground a
// motion covers, and the comment above says so itself - 227 ms was measured as
// too fast for a panel and replaced by 340, and a floor at 167 lets exactly
// that case through. At 1.5x the panel was back at 227 and nothing caught it.
//
// So: no travel is scaled below four fifths of what it was designed to take.
// The speed setting keeps working everywhere - it can still take a fifth off
// any motion in the session - but it can no longer undo the choice the
// duration table made. One rule, and both floors apply at once: whichever
// binds first, binds.
//
// Four fifths and not a half: a fifth is the most that came out of stretching
// panel durations by hand without the result reading as a different animation.
var FLOOR_SHARE = 0.8

// A duration, scaled and then floored. `base` is the designed duration at 1x.
//
// Both floors are capped at the base, so a motion that was always shorter than
// ten frames is not *lengthened* by this: a floor only ever refuses to make
// something shorter. Without the cap, asking for a 70 ms shake would return
// 167 and the speed setting would stop reaching it entirely.
//
// `moving` is false in Reduced and Off, where shortness is the point (and Off
// is zero anyway), so those two are exempt.
function travel(base, factor, moving) {
    const scaled = Math.round(base * factor)
    if (!moving) return scaled
    return Math.max(scaled, Math.min(base, FLOOR_MS), Math.round(base * FLOOR_SHARE))
}

// The same, for a compositor speed. Larger is slower here, so the floors are
// minima in the same direction: a leaf may not be scaled below FLOOR_SPEED nor
// below its own share, and again only down to its own base, never above it.
//
// The share is what keeps this table honest. Its slowest leaf is 2.2 ds, so a
// ten-frame floor raised to a panel's 227 ms would have sat above *every* leaf
// and frozen the compositor at its designed pace whatever the speed setting
// said. A share cannot do that: it scales with each leaf.
function travelSpeed(base, factor, moving) {
    const scaled = base * factor
    if (!moving) return scaled
    return Math.max(scaled, Math.min(base, FLOOR_SPEED), base * FLOOR_SHARE)
}

// ---- the modes, and the one that stopped meaning anything -----------------

// Fast and Normal differed in exactly two numbers: a duration factor of 1
// against 1.25, and the notch spring. Everything else - whether movement
// happens at all, whether a dragged window interpolates, whether the
// compositor animates - was identical. Since the speed setting arrived, "Fast
// at 0.8x" and "Normal at 1x" are the same session, so the two were a choice
// between a thing and itself.
//
// Reduced and Off are not like that. They turn *movement* off and keep the
// fades, and Reduced stops a dragged or resized window following the pointer.
// No pace can say that. So: Full, Reduced, Off, and the slider carries the
// pace it was built to carry.
var MODES = ["full", "reduced", "off"]

// What a stored value means now. `fast` and `normal` are what sessions written
// before this have; anything unknown is Full, the same way an unknown theme is
// dark.
function mode(value) {
    if (value === "off" || value === "reduced") return value
    return "full"
}

// The pace that keeps a migrated session looking the way it looked.
//
// `factor = modeFactor / speed`, so Normal's 1.25 has to go somewhere when the
// mode becomes Full and its factor becomes 1: it goes into the speed, divided,
// because a *larger* speed is a *shorter* animation. Fast was already 1 and
// keeps its pace untouched.
//
// Clamped to the slider's own range, so a migration cannot produce a value the
// slider could not have produced.
function speedFor(storedMode, storedSpeed) {
    const pace = Number(storedSpeed)
    const base = isFinite(pace) && pace > 0 ? pace : 1
    const scaled = storedMode === "normal" ? base / 1.25 : base
    return Math.min(3, Math.max(0.25, Math.round(scaled * 100) / 100))
}

// settings.json as this version reads it. Total and idempotent: a document
// that has already been migrated passes through unchanged, because `full`,
// `reduced` and `off` all map to themselves and their speed is untouched.
function migrate(document) {
    if (!document || typeof document !== "object" || Array.isArray(document)) return document
    const appearance = document.appearance
    if (!appearance || typeof appearance !== "object" || Array.isArray(appearance)) return document
    const stored = appearance.animationMode
    if (stored !== "fast" && stored !== "normal") return document
    const result = Object.assign({}, document)
    result.appearance = Object.assign({}, appearance, {
        animationMode: "full",
        animationSpeed: speedFor(stored, appearance.animationSpeed)
    })
    return result
}

