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

// Springs, for everything that moves (Hyprland reads them from the Lua
// config only; hyprland.conf has no spring syntax and uses each leaf's
// `bezier` instead). Material 3 in spirit - a spatial family that may
// overshoot a little and an effects family that is critically damped - with
// values of this session's own. Mass 1 throughout; the damping ratio
// d / (2·√k) is in the comment.
var SPRINGS = [
    { name: "buchhwinSpatialFast", mass: 1, stiffness: 700, dampening: 50 },   // 0.94
    { name: "buchhwinSpatial", mass: 1, stiffness: 380, dampening: 34 },       // 0.87
    { name: "buchhwinSpatialSlow", mass: 1, stiffness: 200, dampening: 26 },   // 0.92
    { name: "buchhwinEffectsFast", mass: 1, stiffness: 3200, dampening: 113 }, // 1.00
    { name: "buchhwinEffects", mass: 1, stiffness: 1400, dampening: 75 },      // 1.00
    { name: "buchhwinEffectsSlow", mass: 1, stiffness: 700, dampening: 53 }    // 1.00
]

// Beziers: the layers keep a timed curve (a surface fading in has nothing to
// spring), and the legacy configuration uses them for every leaf.
//   buchhwinFast      fast off the mark, long soft landing (OutQuint-like)
//   buchhwinSpring    a hint of push, the bezier stand-in for a spatial spring
//   buchhwinStandard  Material's standard curve
//   buchhwinAccel     Material's emphasized accelerate, for leaving
var BEZIERS = [
    { name: "buchhwinFast", points: [0.22, 1.0, 0.36, 1.0] },
    { name: "buchhwinSpring", points: [0.2, 1.12, 0.32, 1.0] },
    { name: "buchhwinStandard", points: [0.2, 0.0, 0.0, 1.0] },
    { name: "buchhwinAccel", points: [0.3, 0.0, 0.8, 0.15] }
]

// The leaves. `spring` is what the Lua configuration animates with; `bezier`
// and `speed` are what the legacy one does (and what a leaf without a spring
// uses in both). `popin 87%` is enough travel to be seen: Hyprland's own
// table uses 87 % too, and 96 % was a window that barely moved.
var BASE = [
    { leaf: "windows", speed: 2.0, spring: "buchhwinSpatial", bezier: "buchhwinSpring", style: "popin 87%" },
    { leaf: "windowsOut", speed: 1.7, spring: "buchhwinSpatialFast", bezier: "buchhwinFast", style: "popin 87%" },
    { leaf: "windowsMove", speed: 2.0, spring: "buchhwinSpatial", bezier: "buchhwinFast", style: "" },
    { leaf: "fade", speed: 1.7, spring: "buchhwinEffects", bezier: "buchhwinFast", style: "" },
    { leaf: "layers", speed: 1.7, spring: "", bezier: "buchhwinStandard", style: "fade" },
    { leaf: "layersOut", speed: 1.5, spring: "", bezier: "buchhwinAccel", style: "fade" },
    { leaf: "workspaces", speed: 2.2, spring: "buchhwinSpatial", bezier: "buchhwinFast", style: "slidefade 10%" },
    { leaf: "specialWorkspace", speed: 2.0, spring: "buchhwinSpatialSlow", bezier: "buchhwinFast", style: "slidefadevert 15%" },
    { leaf: "border", speed: 2.0, spring: "buchhwinEffectsSlow", bezier: "buchhwinFast", style: "" },
    // Off in every mode: a border that cycles its hue forever is motion with
    // nothing to say.
    { leaf: "borderangle", speed: 1, spring: "", bezier: "buchhwinFast", style: "", off: true }
]

// How the shell's three animation modes read on the compositor. Only the
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
// And so does the floor - six frames, AnimationLogic.travelSpeed - or the
// shell would keep its frames while the compositor rushed a window through
// fewer than anybody can see. It applies to the bezier leaves; a spring has no
// duration and is scaled in `curves()` instead.
function entries(mode, speed) {
    const wanted = plan(mode)
    const pace = Anim.speed(speed === undefined ? 1 : speed)
    return BASE.map(entry => ({
        leaf: entry.leaf,
        enabled: wanted.enabled && !entry.off,
        speed: Math.max(0.1, Math.round(Anim.travelSpeed(entry.speed, wanted.factor / pace, wanted.moving) * 100) / 100),
        spring: entry.spring,
        bezier: entry.bezier,
        style: entry.style
    }))
}

// The springs as one mode wants them at one speed. A spring ignores the
// leaf's `speed`, so the pace is put into the spring: faster by `scale`
// means stiffer by scale² and damped by scale, which is the same motion
// played faster. Reduced is faster again, the way its durations are shorter.
function curves(mode, speed) {
    const wanted = plan(mode)
    const scale = Anim.speed(speed === undefined ? 1 : speed) / (wanted.factor > 0 ? wanted.factor : 1)
    return SPRINGS.map(curve => Anim.scaleSpring(curve, scale))
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
