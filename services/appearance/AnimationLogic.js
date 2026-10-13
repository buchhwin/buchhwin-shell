.pragma library

// The pace of the session, shared by both halves of it: the shell's own
// motion (theme/Animations.qml) and the compositor's (services/hypr/
// HyprAnimations.js). One setting, one place, or the desktop moves at two
// rhythms at once.
//
// The slider runs from half speed to double. Beyond that the old range only
// ever produced complaints in both directions - a 0.25x session that felt
// broken, a 3x session that the floors had to hold back anyway.
var SPEED_MIN = 0.5
var SPEED_MAX = 2

function speed(value) {
    const pace = Number(value)
    if (!isFinite(pace) || pace <= 0) return 1
    return Math.min(SPEED_MAX, Math.max(SPEED_MIN, pace))
}

// What "1x" plays at. The session was tuned at 1.5x and that is the pace the
// user wants to call normal (2026-10-13), so the slider's 1 now means the
// designed durations played 1.5 times as fast, on both sides of the session.
// The tables keep their designed numbers; this is the one place that moves
// them, and 1 here is the way back.
var BASE_PACE = 1.5

// The setting (the slider, 0.5-2) as the multiplier the animations play at.
function pace(value) {
    return speed(value) * BASE_PACE
}

// A multiplier kept sane: the slider's whole range at the base pace, and
// nonsense is the base itself.
function rate(value) {
    const r = Number(value)
    if (!isFinite(r) || r <= 0) return 1
    return Math.min(SPEED_MAX * BASE_PACE, Math.max(SPEED_MIN, r))
}

// A floor for anything that travels: six frames at 60 Hz. Below it a motion
// stops being one picture after another. The old second floor - four fifths
// of the designed duration - froze every travelling motion from 1.25x up,
// so the top half of the slider only ever reached hover tints; with the range
// ending at 2x this one floor is enough.
var FLOOR_MS = 100

// Hyprland counts its `speed` in deciseconds, so the same six frames are 1.
var FLOOR_SPEED = 1

// A duration, scaled and then floored. `base` is the designed duration at 1x.
// The floor is capped at the base, so a motion that was always shorter is not
// lengthened by it. `moving` is false in Reduced and Off, where shortness is
// the point.
function travel(base, factor, moving) {
    const scaled = Math.round(base * factor)
    if (!moving) return scaled
    return Math.max(scaled, Math.min(base, FLOOR_MS))
}

// The same, for a compositor speed (larger is slower).
function travelSpeed(base, factor, moving) {
    const scaled = base * factor
    if (!moving) return scaled
    return Math.max(scaled, Math.min(base, FLOOR_SPEED))
}

// ---- springs ---------------------------------------------------------------
// Movement follows springs rather than durations: a spring has no length to
// get wrong, it settles where it is sent and can be interrupted mid-way
// without a jump. Three of them, in the Material 3 sense of "spatial":
// fast for small controls, default for most things that move, slow for large
// surfaces. Tints and fades stay timed.
//
// QML's SpringAnimation, and the same shape for Hyprland's Lua curves. A
// spring ignores any duration, so the speed setting scales the spring itself:
// stiffness by s² and damping by s is the same motion played s times as fast
// - the damping ratio, and with it the amount of overshoot, stays the same.
var SPRINGS = {
    fast: { spring: 7, damping: 0.5 },
    standard: { spring: 4.5, damping: 0.42 },
    slow: { spring: 2.8, damping: 0.34 },
    // The notch's shape: a little push, like the Dynamic Island, without the
    // ring-out 0.3 had (shell/notch/NotchValue.qml).
    notch: { spring: 5, damping: 0.5 }
}

// { spring, damping, mass, epsilon } for SpringAnimation at a pace.
function spring(kind, pace) {
    const base = SPRINGS[kind] || SPRINGS.standard
    const s = rate(pace)
    return { spring: Math.round(base.spring * s * s * 100) / 100,
             damping: Math.min(1, Math.round(base.damping * s * 100) / 100),
             mass: 1, epsilon: 0.25 }
}

// A Hyprland spring curve at a scale (the same rule, in its own units).
function scaleSpring(curve, scale) {
    const s = Number(scale) > 0 ? Number(scale) : 1
    return { name: curve.name, mass: curve.mass,
             stiffness: Math.round(curve.stiffness * s * s * 10) / 10,
             dampening: Math.round(curve.dampening * s * 10) / 10 }
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
    return Math.min(SPEED_MAX, Math.max(SPEED_MIN, Math.round(scaled * 100) / 100))
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

