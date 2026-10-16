.pragma library
.import "PanelStyleLogic.js" as Panel

// WCAG contrast helpers for theme colours (theme/Colors.qml): text on an
// accent fill and accent-coloured text or icons on panel surfaces. Colours
// are "#rrggbb" strings (QML colours convert with String()). Unit tested.

// Body text wants 4.5:1, large text and icons 3:1.
var TEXT_RATIO = 4.5
var LARGE_RATIO = 3

function contrast(first, second) {
    const a = Panel.luminance(first)
    const b = Panel.luminance(second)
    if (a < 0 || b < 0) return -1
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

// Text on a filled background: the light colour while it keeps `minLight`
// (by default the 3:1 of large text and marks, such as the check on a
// swatch; labels on accent buttons pass TEXT_RATIO), otherwise whichever of
// the two reads better.
function textOn(background, light, dark, minLight) {
    const lightRatio = contrast(light, background)
    if (lightRatio < 0) return light
    if (lightRatio >= (minLight === undefined ? LARGE_RATIO : minLight)) return light
    return contrast(dark, background) > lightRatio ? dark : light
}

function toHex(rgb) {
    function part(value) {
        const byte = Math.round(Math.max(0, Math.min(1, value)) * 255)
        return (byte < 16 ? "0" : "") + byte.toString(16)
    }
    return "#" + part(rgb.r) + part(rgb.g) + part(rgb.b)
}

function toHsl(rgb) {
    const max = Math.max(rgb.r, rgb.g, rgb.b)
    const min = Math.min(rgb.r, rgb.g, rgb.b)
    const l = (max + min) / 2
    if (max === min) return { h: 0, s: 0, l: l }
    const d = max - min
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    const h = max === rgb.r ? (rgb.g - rgb.b) / d + (rgb.g < rgb.b ? 6 : 0)
        : max === rgb.g ? (rgb.b - rgb.r) / d + 2
        : (rgb.r - rgb.g) / d + 4
    return { h: h / 6, s: s, l: l }
}

function fromHsl(hsl) {
    if (hsl.s === 0) return { r: hsl.l, g: hsl.l, b: hsl.l }
    function channel(p, q, t) {
        if (t < 0) t += 1
        if (t > 1) t -= 1
        if (t < 1 / 6) return p + (q - p) * 6 * t
        if (t < 1 / 2) return q
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
        return p
    }
    const q = hsl.l < 0.5 ? hsl.l * (1 + hsl.s) : hsl.l + hsl.s - hsl.l * hsl.s
    const p = 2 * hsl.l - q
    return { r: channel(p, q, hsl.h + 1 / 3), g: channel(p, q, hsl.h), b: channel(p, q, hsl.h - 1 / 3) }
}

// `foreground` with its lightness moved away from `background` (darker on a
// light background, lighter on a dark one) until it reaches `ratio`; hue and
// saturation stay, so an accent remains recognisable. Colours that already
// reach the ratio are returned unchanged (normalized).
function readable(foreground, background, ratio) {
    return readableOnAll(foreground, [background], ratio)
}

// The lowest ratio `foreground` has on any of `backgrounds`.
function lowestContrast(foreground, backgrounds) {
    let lowest = Infinity
    for (const background of backgrounds) lowest = Math.min(lowest, contrast(foreground, background))
    return lowest
}

// readable() for an ink that sits on more than one surface - a card and the
// tint of a selected row on it, a card and a card inside it. The ink moves
// until the weakest of its ratios reaches `ratio`. The surfaces are all on
// one side (all light or all dark); the first decides which way it moves.
function readableOnAll(foreground, backgrounds, ratio) {
    const fg = Panel.normalizeHex(foreground)
    const bgs = (backgrounds || []).map(Panel.normalizeHex).filter(bg => bg.length > 0)
    if (!fg.length || !bgs.length) return fg
    const target = ratio === undefined ? TEXT_RATIO : ratio
    if (lowestContrast(fg, bgs) >= target) return fg
    const hsl = toHsl(Panel.parseHex(fg))
    const darker = Panel.luminance(bgs[0]) > Panel.luminance("#767676")
    let best = fg
    for (let step = 1; step <= 100; ++step) {
        const l = darker ? hsl.l - step / 100 : hsl.l + step / 100
        if (l < 0 || l > 1) break
        best = toHex(fromHsl({ h: hsl.h, s: hsl.s, l: l }))
        if (lowestContrast(best, bgs) >= target) return best
    }
    return darker ? "#000000" : "#ffffff"
}

// `color` laid over the opaque `background` at `alpha`, the way Qt Quick
// blends (straight, in sRGB): the colour a translucent fill really shows.
// Every surface the inks are measured on is built from these, so a token
// that changes its alpha changes the measurement with it.
function over(color, alpha, background) {
    const fg = Panel.parseHex(color)
    const bg = Panel.parseHex(background)
    if (!fg || !bg) return Panel.normalizeHex(background)
    const a = Math.max(0, Math.min(1, Number(alpha)))
    return toHex({ r: fg.r * a + bg.r * (1 - a), g: fg.g * a + bg.g * (1 - a), b: fg.b * a + bg.b * (1 - a) })
}

// How strongly `cover` may be laid over `background` (0 to `limit`, in
// hundredths) before `ink` on the mix falls below `ratio`; 0 when even the
// bare background misses. For a picture that tints a surface behind text,
// with `cover` the worst the picture can be (white behind light ink).
function maxOverlay(ink, cover, background, ratio, limit) {
    const target = ratio === undefined ? TEXT_RATIO : ratio
    const top = limit === undefined ? 1 : limit
    let best = 0
    for (let step = 1; step <= 100 && step / 100 <= top + 1e-9; ++step) {
        if (contrast(ink, over(cover, step / 100, background)) < target) break
        best = step / 100
    }
    return best
}
