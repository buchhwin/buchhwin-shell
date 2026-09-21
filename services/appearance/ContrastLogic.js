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
// (large text/icon contrast by default, so the calm blue accent keeps white
// labels), otherwise whichever of the two reads better.
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
    const fg = Panel.normalizeHex(foreground)
    const bg = Panel.normalizeHex(background)
    if (!fg.length || !bg.length) return fg
    const target = ratio === undefined ? TEXT_RATIO : ratio
    if (contrast(fg, bg) >= target) return fg
    const hsl = toHsl(Panel.parseHex(fg))
    const darker = Panel.luminance(bg) > Panel.luminance("#767676")
    let best = fg
    for (let step = 1; step <= 100; ++step) {
        const l = darker ? hsl.l - step / 100 : hsl.l + step / 100
        if (l < 0 || l > 1) break
        best = toHex(fromHsl({ h: hsl.h, s: hsl.s, l: l }))
        if (contrast(best, bg) >= target) return best
    }
    return darker ? "#000000" : "#ffffff"
}
