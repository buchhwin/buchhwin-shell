.pragma library

// Lighter effects on battery (Settings > Power, per power source like the
// profile): the blur off and reduced motion while that set applies - what
// the Gaming mode has always worn, without touching a stored setting. The
// user's own animation mode and blur stay as they are in Settings >
// Appearance and come back the moment the charger is in. Off by default:
// what it saves on this laptop is to be measured first (BAT0's power_now,
// five minutes with and five without, the same windows). Unit tested
// (LightEffectsTest).

var CHOICES = ["keep", "light"]

function normal(choice) {
    return CHOICES.indexOf(choice) >= 0 ? choice : "keep"
}

// What applies now. `preview` ("keep", "light" or "") is IPC's, for a nested
// check that cannot unplug the host's charger; it wins while it is set.
function light(choice, preview) {
    if (preview === "keep" || preview === "light") return preview === "light"
    return normal(choice) === "light"
}

// The animation mode the shell and the compositor run: Full becomes Reduced,
// Reduced and Off stay what they are.
function animationMode(stored, isLight) {
    return isLight === true && stored === "full" ? "reduced" : stored
}

// The blur the compositor gets: none while light, the user's otherwise.
function blurStrength(stored, isLight) {
    return isLight === true ? 0 : stored
}
