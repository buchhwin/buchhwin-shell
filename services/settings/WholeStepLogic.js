.pragma library

// Whole-number settings on a slider: a border in pixels, a gap, a corner
// radius, a count. ShellSlider steps a twentieth of its range per arrow key or
// wheel notch, which is less than one on a short range: Border width (1 to 8)
// stepped 0.35, the page rounded it back, and Right never moved it; Gap
// between windows (0 to 30) stepped 1.5 and went up two on Right but down one
// on Left. shell/settings/pages/IntegerSlider.qml hands its gestures here.

// The whole value a gesture ends on. A drag lands on the nearest whole
// number. A key or a wheel notch moves at least one in its direction, and as
// many as its share of the range rounds to - the same number either way.
// Home and End reach the ends, the page keys go further than the arrows.
function whole(stored, value, dragged, from, to) {
    const low = Math.ceil(Number(from))
    const high = Math.floor(Number(to))
    const clamp = number => Math.max(low, Math.min(high, number))
    const base = Math.round(Number(stored))
    if (dragged || !isFinite(base)) return clamp(Math.round(Number(value)))
    const delta = Number(value) - base
    if (!isFinite(delta) || Math.abs(delta) < 1e-6) return clamp(base)
    return clamp(base + Math.sign(delta) * Math.max(1, Math.round(Math.abs(delta))))
}
