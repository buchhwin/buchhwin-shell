.pragma library

// When the on-screen display keeps quiet, for shell/osd/Osd.qml.

// Whether the OSD for `kind` stays hidden because the panel that is open
// (`active`, PanelService.active) already shows that control. Per kind, not
// per panel: with the volume popup open the brightness keys changed the
// screen and nothing said by how much, and with the control center open the
// keyboard light's key said nothing at all - neither has a control for them.
// The control center shows what its tiles are (`quickTypes`,
// LayoutService.quickTypes): the volume with an audio tile, the microphone
// with a microphone tile, the brightness with a brightness tile. The
// keyboard light has no slider anywhere, so its OSD always shows.
function suppressed(kind, active, quickTypes) {
    const types = quickTypes || []
    if (active === "volumePopup") return kind === "volume" || kind === "mic"
    if (active !== "controlCenter") return false
    if (kind === "volume") return types.indexOf("audio") >= 0
    if (kind === "mic") return types.indexOf("microphone") >= 0
    if (kind === "brightness") return types.indexOf("brightness") >= 0
    return false
}

// Whether the default device moving from `previous` to `next` is a change
// the user did not make - headphones connecting, a headset unplugged, a dock
// - so its level and mute state are not news for a moment (Osd's settle
// timers). `seen` says a device has been known before: the first one the
// shell meets at start is where it begins, not a change. One that goes and
// comes back (`null` in between) is a change both ways, which reading
// "nothing before" as a start had missed.
function deviceChanged(previous, next, seen) {
    return seen === true && previous !== next
}

// Whether a level change has to reach the notch's display slot. Only while
// the OSD is in the notch, and once more to take it out of the slot when it
// leaves; a level dragged in the control center, with the OSD nowhere,
// rewrote every screen's notch display on each step.
function publishes(inNotch, published) {
    return inNotch === true || published === true
}

// How far from the screen's sides the box out of `origin` (a rect, or null)
// stays: the screen margin, but never further in than what it comes out of
// (never less than 0), as ShellPanel's PanelPlaceLogic.outerClear. `barEnd`
// is where a floating bar or the pills end along the screen (PillBar's
// inset: the windows' gap, at least the bar margin), or a negative number
// when the box does not come out of a bar that floats. Out of the status
// pill that is the pill's own outer edge: the item inside it is further in,
// and the box ended 4 px inside the pill once the pills moved out to the gap.
function sideMargin(origin, screenWidth, margin, barEnd) {
    if (!origin) return margin
    const width = Number(screenWidth) || 0
    let clear = Math.min(margin, origin.x, width - origin.x - origin.width)
    const end = Number(barEnd)
    if (isFinite(end) && end >= 0) clear = Math.min(clear, end)
    return Math.max(0, clear)
}
