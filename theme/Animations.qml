pragma Singleton
import Quickshell
import QtQuick
import qs.services
import "../services/appearance/AnimationLogic.js" as Logic

// Durations follow Promt §11. Animation Mode scales them: Full (default),
// Reduced (shorter, no movement) and Off. The pace inside Full is the speed
// setting's job - see AnimationLogic for why there is no longer a Fast and a
// Normal to choose between.
Singleton {
    readonly property string mode: SettingsService.animationMode
    // The mode decides the rhythm, the speed setting scales it. `factor` is a
    // *duration* multiplier, so a faster speed divides it: at 2x an animation
    // takes half as long.
    readonly property real modeFactor: mode === "off" ? 0 : mode === "reduced" ? 0.6 : 1
    // The slider's value times the base pace (AnimationLogic.BASE_PACE).
    readonly property real speed: Logic.pace(SettingsService.animationSpeed)
    readonly property real factor: modeFactor / speed
    readonly property bool motionEnabled: mode === "full"
    readonly property bool enabled: factor > 0

    // A motion that covers ground may not be scaled below six frames. The
    // rule is in AnimationLogic.js, which the compositor's table uses too -
    // one rule, one place.
    //
    // They apply to travel, not to every duration. A panel crossing 680 px and
    // a hover tint changing in place are not the same problem: the panel reads
    // as single pictures when it is rushed, the tint does not, and a floor on
    // the tint would only stop the speed setting from doing anything at all
    // above 1x. That is the same line `move()` already draws - ground covered
    // against no ground covered - so the two stay in agreement.
    //
    // The floor now depends on the base, so it is a function and not a number.
    function travel(base) { return Logic.travel(base, factor, motionEnabled) }

    // ---- springs -----------------------------------------------------------
    // Anything that *follows* a value - a knob, an indicator, a tile gliding to
    // its new place, the notch's shape - moves on a spring: it lands where it
    // is sent and can be redirected half-way without a jump, which a fixed
    // duration cannot. Three of them (AnimationLogic.SPRINGS), scaled by the
    // speed setting; shell/components/SpringMotion.qml is the animation that
    // uses them. Only in Full: Reduced and Off jump to the new place.
    readonly property var springFast: Logic.spring("fast", speed)
    readonly property var springStandard: Logic.spring("standard", speed)
    readonly property var springSlow: Logic.spring("slow", speed)
    function spring(kind) { return kind === "fast" ? springFast : kind === "slow" ? springSlow : springStandard }

    // **No travel here is below six frames** - see `travel()` above. At 60 Hz a
    // 100 ms animation is six frames and a 60 ms one is four, and a four-frame
    // fade does not read as a fade - it reads as the thing stepping, which is
    // exactly what "all the animations look like five frames a second"
    // describes. Measured first: the shell sits at 0 CPU jiffies when idle and
    // spends 11 % of one core through a burst of panel opens, and the
    // compositor 5 %, so nothing here was ever short of time to draw. It was
    // short of *frames*.
    //
    // The numbers below are the durations at 1x. They are no longer the floor
    // themselves, because the speed setting divides them afterwards.
    //
    // The same lesson is already written a few lines down, about the panel
    // morph: "The old 140/105 ms were so short that a dropped frame was the
    // whole animation."
    readonly property int hover: Math.round(170 * factor)
    // One UI controls: the press reaction is quick, the release settles back
    // with a small, damped overshoot.
    readonly property int press: Math.round(140 * factor)
    readonly property int control: Math.round(240 * factor)
    // Movement (knob travel, segment slide) only in the moving modes; Reduced
    // and Off jump to the new place and keep the fades.
    function move(duration) { return motionEnabled ? duration : 0 }
    // One UI motion: a panel needs enough frames to read as a glide. The old
    // 140/105 ms were so short that a dropped frame was the whole animation.
    // A panel travels a long way: the control center grows from the notch's
    // 202 px to its own 880, and in 220 ms at 60 Hz that is thirteen frames -
    // 52 px a frame on average and several hundred in the first one, because
    // OutQuint spends most of the distance at the start. Every frame arrived
    // on time and it still read as single pictures, which is a motion that is
    // too fast for the ground it covers rather than a motion short of frames.
    readonly property int popupOpen: travel(340)
    readonly property int popupClose: travel(240)
    readonly property int navigation: travel(210)
    readonly property int workspace: travel(200)
    // Level meter updates arrive every 50 ms; glide between them. Longer than
    // the gap on purpose, so the bar is always travelling rather than landing
    // and waiting - that stutter is what a four-frame glide looks like.
    readonly property int meter: Math.round(110 * factor)
    // One turn of a busy indicator; only runs while motion is enabled.
    readonly property int spinner: 900
    // A quick Alt+Tab switches without flashing the switcher; not scaled.
    readonly property int switcherShowDelay: 110
    // A window preview shows its placeholder icon only after this long without
    // a picture: a new one (a window just moved to another workspace) needs a
    // frame or two for its first capture, and the icon flashed in that gap.
    // Not scaled.
    readonly property int previewIconDelay: 250
    // Lock screen: staggered entrance, rolling clock digits, zoom-out unlock.
    readonly property int lockEnter: travel(720)
    // A digit fades in over part of the roll, so the swap reads as one move.
    readonly property int lockDigitFade: Math.round(lockDigit * 0.6)
    readonly property int lockStagger: Math.round(120 * factor)
    readonly property int lockDigit: travel(460)
    readonly property int lockExit: travel(380)
    readonly property int lockPop: travel(180)
    readonly property int lockPulse: 1100
    // One turn of the media popup's vinyl record (33⅓ rpm would be 1800).
    readonly property int vinylTurn: 5000
    // Fingerprint glyph: ripple while scanning, fill per enrollment stage.
    readonly property int fingerprintRipple: 1800
    // How often the ripples run per scan before they rest (a new attempt
    // starts them again): fprintd can wait for minutes, and each cycle
    // redraws every lock surface, blur included, on every frame.
    readonly property int fingerprintRippleCycles: 5
    readonly property int fingerprintFill: travel(420)

    // A rejected password shakes the field: three fast swings at full
    // amplitude, then back to rest. ~400 ms in total, macOS-style.
    readonly property int shakeOut: Math.round(70 * factor)
    readonly property int shakeSwing: Math.round(110 * factor)
    readonly property int easingShake: Easing.OutQuad

    // Notch: content fade after the shape and the morph. Full uses a spring
    // (spring/damping, scaled by the speed setting like every spring here),
    // Reduced a plain ease, Off jumps. How long the pointer has to rest on it
    // is the user's (notch.openDelay/closeDelay); notchHoverDelay is only the
    // pause before a remapped notch shows again and the pill bar's own hover.
    // Editing: a tile wiggles so you can see it can be picked up. Each one
    // starts at a slightly different point of the cycle - all in step looks
    // mechanical.
    readonly property int wiggle: 1400
    // One step of the scroll a drag near a list's edge pulls. Not scaled by
    // the animation mode: it is a rate, not a transition, and a session with
    // motion off still has to be able to reach the bottom of the list.
    readonly property int scrollTick: 16
    // How long the pointer has to rest on a control before it explains itself.
    // Not scaled by the animation mode: it is a wait, not a transition, and a
    // session with motion off still wants to read the label.
    //
    // A second, at the user's word. It was 550 ms when the only things with
    // tooltips were icon-only buttons, where the bubble is the only way to
    // learn what the button does and waiting is pure cost. The "i" beside a
    // setting is the opposite: the pointer crosses a column of them on its way
    // somewhere else, and a bubble that fires halfway is a flicker rather than
    // an answer.
    readonly property int toolTipDelay: 1000

    readonly property int notchHoverDelay: 150
    // How long the first-start tour waits for the shell to settle. Not a
    // motion duration: Reduced and Off must not make it appear at once.
    readonly property int welcomeDelay: 4000
    // How long a button that destroys something stays armed after the first
    // click. Not scaled by the animation mode: it is a grace period, not a
    // transition.
    readonly property int confirmTimeout: 4000
    readonly property int notchContentDelay: Math.round(110 * factor)
    readonly property int notchContentFade: Math.round(190 * factor)
    readonly property int notchMorph: travel(260)
    // 5 at the designed pace, scaled like the other springs.
    readonly property var notchSpringParams: Logic.spring("notch", speed)
    readonly property real notchSpring: notchSpringParams.spring
    // 0.3 rang the shape for a quarter of a second after it had arrived; the
    // notch is the most expensive thing the shell draws, so every extra
    // wobble frame rebuilt its outline and its input region. 0.5 keeps the
    // Dynamic-Island push without the ring-out.
    readonly property real notchDamping: notchSpringParams.damping
    readonly property real notchMass: 1
    // Stop the spring once it is within a quarter pixel instead of chasing
    // sub-pixel differences for another few frames.
    readonly property real notchEpsilon: 0.25

    readonly property int easing: Easing.OutCubic
    // One UI enter: fast off the mark, long soft landing.
    // OutCubic, not OutQuint: the fifth power puts nine tenths of the distance
    // in the first third of the time, which is the same complaint again in a
    // different shape.
    readonly property int easingEnter: Easing.OutCubic
    readonly property int easingExit: Easing.InQuad
    // One UI's control curve: fast start, soft landing with a hint of spring.
    readonly property int easingControl: Easing.OutBack
    readonly property real overshoot: 1.2
    // A large surface needs less of it than a small control.
    readonly property real overshootSoft: 0.8
    // A pop that is meant to be seen (the fingerprint glyph finishing).
    readonly property real overshootStrong: 2
    // Something breathing in place, back and forth (the lock screen's pulse).
    readonly property int easingBreathe: Easing.InOutSine
}
