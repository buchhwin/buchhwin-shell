.pragma library
.import "../appearance/AnimationLogic.js" as Anim

// The compositor's animation table, in one place.
//
// The same numbers live in hypr/hyprland.conf and hypr/hyprland.lua, which is
// what Hyprland reads at startup; this copy is what the shell re-emits when
// the animation mode changes, because Hyprland has no global speed multiplier.
// `scripts/lib/checks.py hypr` holds the three against each other.
//
// Hyprland's `speed` is a duration in deciseconds, so a larger number is a
// slower animation - it scales the same way theme/Animations.qml's `factor`
// does, which is why one setting can drive both.

// Ten frames is the floor here as well as in the shell, and three leaves were
// below it at the *designed* pace, before any speed setting touched them:
// windowsOut at 1.4 was 8.4 frames and fade and layers at 1.6 were 9.6. A
// window closing in eight frames of a 4 % scale change is the "window
// animations are broken" report, and no floor behind the division can rescue
// it, because that floor is capped at the base and the base was the problem.
//
// `popin 96%` is 4 % of travel. Hyprland's own table uses 87 %, three times
// as far, and the lesson from the panels applies unchanged: enough frames is
// not enough if there is nothing to see in them.
var BASE = [
    { leaf: "windows", speed: 2.0, bezier: "buchhwinSpring", style: "popin 87%" },
    { leaf: "windowsOut", speed: 1.7, bezier: "buchhwinFast", style: "popin 87%" },
    { leaf: "windowsMove", speed: 2.0, bezier: "buchhwinFast", style: "" },
    { leaf: "fade", speed: 1.7, bezier: "buchhwinFast", style: "" },
    { leaf: "layers", speed: 1.7, bezier: "buchhwinFast", style: "fade" },
    { leaf: "workspaces", speed: 2.2, bezier: "buchhwinFast", style: "slidefade 10%" },
    { leaf: "specialWorkspace", speed: 2.0, bezier: "buchhwinFast", style: "slidefadevert 15%" },
    { leaf: "border", speed: 2.0, bezier: "buchhwinFast", style: "" },
    // Off in every mode: a border that cycles its hue forever is motion with
    // nothing to say.
    { leaf: "borderangle", speed: 1, bezier: "buchhwinFast", style: "", off: true }
]

// How the shell's four animation modes read on the compositor. Only the
// durations are scaled and only `borderangle` and the two pointer-driven
// `misc` flags are switched: which style string means "less movement" differs
// per leaf and guessing at it would be cosmetic invention, so the modes stay
// honest about what they change.
//
//   off      nothing animates
//   reduced  shorter, and a dragged or resized window stops interpolating
//   full     the table as written; the pace within it is the speed setting
function plan(mode) {
    if (mode === "off") return { enabled: false, factor: 1, pointer: false, moving: false }
    if (mode === "reduced") return { enabled: true, factor: 0.6, pointer: false, moving: false }
    return { enabled: true, factor: 1, pointer: true, moving: true }
}

// The table as one mode wants it, at one speed. Speeds are rounded to two
// decimals, because Hyprland takes them as text and a long float only makes
// the command noisy.
//
// `speed` is the user's setting (1 is the designed pace) and it divides the
// duration, the same way it does for the shell's own animations - one control
// has to mean the same thing on both sides of the session or the desktop
// moves at two rhythms at once.
//
// And so does the floor: without it the shell kept its ten frames while the
// compositor did not, so at 1.5x a window closed in 93 ms - five and a half
// frames of a 4 % scale change, which is not a motion anybody can see. The
// old `Math.max(0.1, ...)` was a floor of ten milliseconds, which is to say
// none at all. AnimationLogic.travelSpeed is the real one.
function entries(mode, speed) {
    const wanted = plan(mode)
    const pace = Math.max(0.25, Number(speed) || 1)
    return BASE.map(entry => ({
        leaf: entry.leaf,
        enabled: wanted.enabled && !entry.off,
        speed: Math.max(0.1, Math.round(Anim.travelSpeed(entry.speed, wanted.factor / pace, wanted.moving) * 100) / 100),
        bezier: entry.bezier,
        style: entry.style
    }))
}

function pointerAnimated(mode) {
    return plan(mode).pointer
}

function enabled(mode) {
    return plan(mode).enabled
}

// Hyprland's newer frame scheduling: start a frame from when the last one
// finished rather than from the vblank alone. It sits with the animation table
// because it is the same subject - who asks for a frame, and when - and
// because a session that docks has to decide it in one place.
//
// One output: on. It is what an animation on an idle machine needs, measured
// on this laptop (six panel animations, GPU at 16 % busy on its lowest clock,
// motion still stepping) and confirmed by the user for workspace switches and
// a terminal opening.
//
// Several outputs: off. The same option also decides *which* output gets asked
// for a frame, and an unfocused one stops being asked - which is exactly the
// symptom reported from a three-monitor dock: a video on the left screen
// nearly freezes the moment focus moves to the second, while its audio keeps
// playing. The configuration files ship `false`, because a session that comes
// up before the shell has counted its screens should start in the state that
// cannot starve a monitor.
// Exactly one screen turns it on. Nothing else does - not two, and not a
// count of zero, which is what the shell holds for the first moments before it
// has seen its outputs. An unknown number of screens is answered with the
// value that cannot starve one.
function frameScheduling(screenCount) {
    return Math.round(Number(screenCount)) === 1
}
