.pragma library

// The screen zoom (magnifier) and the colour filters, both of them
// compositor options the shell sets at run time: Hyprland's
// `cursor:zoom_factor`, which scales the output around the pointer, and
// `decoration:screen_shader`, a fragment shader run over the finished frame
// (the files in shaders/). Pure, unit tested in ScreenEffectsTest.qml;
// ScreenEffectsService holds the state and sends it.

// ---- Zoom ----------------------------------------------------------------
//
// Steps rather than a factor times something: a ladder reads the same on
// every press (Windows' Magnifier goes 100 %, 200 %, 300 %; this is finer at
// the start, where small text on a 4K screen wants 125 % and not double), and
// two presses out always land back where the two presses in started.
var ZOOM_STEPS = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8]
var ZOOM_MAX = ZOOM_STEPS[ZOOM_STEPS.length - 1]

// A factor Hyprland can take: 1 (off) to the top of the ladder.
function clampZoom(factor) {
    const value = Number(factor)
    if (!isFinite(value) || value <= 1) return 1
    return Math.min(ZOOM_MAX, Math.round(value * 100) / 100)
}

// One step in (`direction` > 0) or out (< 0) from `current`: the next rung
// past it, so a factor between two rungs (set over IPC) goes to the nearer
// one in that direction rather than skipping it.
function zoomStep(current, direction) {
    const now = clampZoom(current)
    const dir = Number(direction)
    if (!isFinite(dir) || dir === 0) return now
    if (dir > 0) {
        const up = ZOOM_STEPS.filter(step => step > now + 0.001)
        return up.length ? up[0] : ZOOM_MAX
    }
    const down = ZOOM_STEPS.filter(step => step < now - 0.001)
    return down.length ? down[down.length - 1] : 1
}

function zoomActive(factor) {
    return clampZoom(factor) > 1
}

// Whether a zoom of `next` has to be sent when the shell holds `current`:
// any change, and 100 % always. The shell starts at 1 whatever the
// compositor has, so one restarted while the screen was zoomed would
// otherwise have no way back - Super+0 would find nothing to change.
function zoomNeedsSend(current, next) {
    const target = clampZoom(next)
    return target === 1 || target !== clampZoom(current)
}

// "2×", "1.25×": what the OSD and the control center's tile say.
function zoomLabel(factor) {
    const value = clampZoom(factor)
    return value > 1 ? String(value) + "×" : "Off"
}

// The option map for HyprCompat.setOptions.
function zoomOptions(factor) {
    return { "cursor:zoom_factor": clampZoom(factor) }
}

// ---- Colour filters ------------------------------------------------------
//
// The three colour-blind ones correct rather than simulate: the colours one
// cone cannot tell apart are pushed towards ones it can (the daltonize
// method; Windows' and Plasma's filters do the same), so red and green on a
// chart or in a diff are two colours again. Grayscale is also a focus aid,
// as on a phone. Each costs a full-screen shader pass on every frame and
// turns direct scanout off, while it is on and only then.
var FILTERS = [
    { id: "grayscale", label: "Grayscale", file: "grayscale.frag" },
    { id: "deuteranopia", label: "Red-green (green weak)", file: "deuteranopia.frag" },
    { id: "protanopia", label: "Red-green (red weak)", file: "protanopia.frag" },
    { id: "tritanopia", label: "Blue-yellow", file: "tritanopia.frag" },
    { id: "invert", label: "Inverted", file: "invert.frag" }
]
var DEFAULT_FILTER = "grayscale"

function filterEntry(id) {
    return FILTERS.find(item => item.id === String(id || "")) || null
}

function knownFilter(id) {
    return filterEntry(id) !== null
}

// The filter a setting names, or the default one: a value from a later
// version, or one edited by hand, never reaches the compositor as a path.
function normalizeFilter(id) {
    return knownFilter(id) ? String(id) : DEFAULT_FILTER
}

function filterLabel(id) {
    return filterEntry(normalizeFilter(id)).label
}

// The shader for `id` under the shell's directory `shaders` (Paths.shellFile
// of "shaders"), or "" with the filter off.
function shaderPath(on, id, shaders) {
    if (on !== true) return ""
    const folder = String(shaders || "").replace(/\/+$/, "")
    if (!folder.length) return ""
    return folder + "/" + filterEntry(normalizeFilter(id)).file
}

// The option map for HyprCompat.setOptions. An empty value takes the shader
// off (HyprCommands.options sends it on its own in the legacy dialect).
function filterOptions(on, id, shaders) {
    return { "decoration:screen_shader": shaderPath(on, id, shaders) }
}

// The filter after `id` in the list, for a key that walks through them.
function nextFilter(id) {
    const index = FILTERS.findIndex(item => item.id === normalizeFilter(id))
    return FILTERS[(index + 1) % FILTERS.length].id
}

// { value, label } for a picker: the filters in their order.
function filterOptionsList() {
    return FILTERS.map(item => ({ value: item.id, label: item.label }))
}
