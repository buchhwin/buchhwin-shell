import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/origin/OriginLogic.js" as O

// Where a notification and an OSD come from. Both ask the same two functions,
// so the only way they can disagree is if these are wrong.
ShellRoot {
    Component.onCompleted: {
        // A collapsed notch on a 1920 screen: 202 wide, at the top centre.
        const notch = { x: 859, y: 0, width: 202, height: 32 }

        // ---- sitting under it ------------------------------------------------
        T.eq(O.under(notch, 400, 1920, 16, 8), { x: 760, y: 40 },
             "centred on the notch, below it")
        T.eq(O.under(notch, 202, 1920, 16, 8).x, 859, "a box as wide as the notch lines up with it")
        T.eq(O.under(null, 400, 1920, 16, 8), null, "with no notch there is nothing to sit under")
        // The failure that put the volume bar in the top left corner: a screen
        // whose width is not known yet answered with the left-hand margin
        // instead of refusing, and the surface went there.
        T.eq(O.under(notch, 400, 0, 16, 8), null, "nor before the screen's width is known")
        T.eq(O.under(notch, 0, 1920, 16, 8), null, "nor for a box with no width")

        // ---- where it goes when there is no notch ------------------------------
        T.eq(O.atBottom(300, 60, 1920, 1200, 96, 16), { x: 810, y: 1044 },
             "centred on the bottom edge, one bottom margin up")
        T.eq(O.atBottom(300, 60, 0, 1200, 96, 16), null, "and nothing before the screen is known")
        T.eq(O.atBottom(4000, 60, 1920, 1200, 96, 16).x, 16, "a box wider than the screen starts at the margin")
        T.eq(O.atTopRight(380, 1920, 40, 16), { x: 1524, y: 40 }, "the corner the popups have always used")
        T.eq(O.atTopRight(380, 0, 40, 16), null, "and nothing before the screen is known")
        T.eq(O.atTopRight(4000, 1920, 40, 16).x, 16, "a popup wider than the screen starts at the margin")

        // ---- and in bar mode ---------------------------------------------------
        // A popup whose own widget is not on the bar comes from a place on it
        // rather than from a thing, so the place has no width of its own.
        T.eq(O.barSpot(38, 1920, "centre", 16), { x: 960, y: 0, width: 0, height: 38 },
             "an OSD comes out of the middle of the bar")
        T.eq(O.barSpot(38, 1920, "end", 16), { x: 1904, y: 0, width: 0, height: 38 },
             "and a notification out of its right-hand end")
        T.eq(O.barSpot(-1, 1920, "end", 16), null, "with no bar there is no place on it")
        T.eq(O.barSpot(38, 0, "end", 16), null, "nor before the screen is known")
        // The place is usable as an origin like any other rectangle.
        T.eq(O.under(O.barSpot(38, 1920, "centre", 16), 300, 1920, 16, 8).x, 810,
             "a box sits under the middle of the bar the same way it sits under the notch")

        // Pushed back onto the screen rather than hanging off it.
        const corner = { x: 1700, y: 0, width: 200, height: 32 }
        T.eq(O.under(corner, 400, 1920, 16, 8).x, 1920 - 400 - 16,
             "a box that would hang off the right edge stops at the margin")
        const left = { x: 0, y: 0, width: 100, height: 32 }
        T.eq(O.under(left, 400, 1920, 16, 8).x, 16, "and one off the left edge does too")
        T.eq(O.under(notch, 4000, 1920, 16, 8).x, 16,
             "a box wider than the screen starts at the margin rather than off it")

        // ---- travelling out of it ---------------------------------------------
        const card = { x: 760, y: 40, width: 400, height: 120 }
        T.eq(O.offsetTo(notch, card), { x: 0, y: -84 },
             "a box centred under the notch only has to travel up")
        const right = { x: 1520, y: 40, width: 384, height: 120 }
        T.eq(O.offsetTo(notch, right), { x: -752, y: -84 },
             "one at the right edge travels left as well")
        T.eq(O.offsetTo(null, card), { x: 0, y: 0 }, "with no origin it travels nowhere")
        T.eq(O.offsetTo(notch, null), { x: 0, y: 0 }, "and so does nothing at all")
        // Carrying a box to the origin and back is where it started.
        const back = O.offsetTo(notch, card)
        T.eq({ x: card.x + back.x - back.x, y: card.y + back.y - back.y }, { x: card.x, y: card.y },
             "the offset is a journey, not a place")

        // ---- the same, for a bar at the bottom edge --------------------
        // A spot on a bottom bar is the last `inset` pixels of the screen, not
        // the first: built from the top it would sit under the whole screen.
        T.eq(O.barSpot(32, 1920, "centre", 16, "bottom", 1200), { x: 960, y: 1168, width: 0, height: 32 },
             "a spot on a bottom bar is at the bottom")
        T.eq(O.barSpot(32, 1920, "end", 16, "bottom", 1200).x, 1904, "its end is still the right-hand one")
        T.eq(O.barSpot(32, 1920, "centre", 16, "top", 1200), O.barSpot(32, 1920, "centre", 16, undefined, 0),
             "and a top bar answers the same with or without a screen height")
        T.eq(O.barSpot(32, 1920, "centre", 16, "bottom", 0), null,
             "a bottom spot on a screen whose height is not known yet is no spot at all")
        T.eq(O.barSpot(-1, 1920, "centre", 16, "bottom", 1200), null, "and neither is one with no bar")

        // `above` is `under` mirrored: same x, and the box sits its own height
        // plus the gap above the origin instead of below it.
        const lowBar = O.barSpot(32, 1920, "centre", 16, "bottom", 1200)
        const over = O.above(lowBar, 320, 64, 1920, 16, 8)
        T.eq(over, { x: 800, y: 1096 }, "a box comes out of a bottom bar upwards")
        T.eq(over.x, O.under(lowBar, 320, 1920, 16, 8).x, "and is centred on exactly the same spot")
        T.eq(O.above(lowBar, 320, 4000, 1920, 16, 8).y, 0,
             "a box taller than the screen stops at the top rather than going past it")
        T.eq(O.above(null, 320, 64, 1920, 16, 8), null, "no origin, nowhere to be")
        T.eq(O.above(lowBar, 320, 64, 0, 16, 8), null, "and a screen of no width is not known yet")

        // ---- beside, for a bar that runs down the screen ------------------

        const pill = { x: 0, y: 500, width: 40, height: 40 }
        const pastBar = O.beside(pill, 400, 300, 1920, 1080, 8, 8, false)
        T.eq(pastBar.x, 48, "a box beside a left-hand bar starts past it, with the gap")
        T.eq(pastBar.y, 370, "and is centred on the pill along the screen's height")

        const farPill = { x: 1880, y: 500, width: 40, height: 40 }
        const beforeBar = O.beside(farPill, 400, 300, 1920, 1080, 8, 8, true)
        T.eq(beforeBar.x, 1472, "a box beside a right-hand bar sits to the left of it")
        T.eq(beforeBar.y, 370, "centred the same way")

        // Clamped into the screen, top and bottom, the way `under` clamps left
        // and right.
        T.eq(O.beside({ x: 0, y: 0, width: 40, height: 40 }, 400, 300, 1920, 1080, 8, 8, false).y, 8,
             "a pill at the very top does not push the box off the screen")
        T.eq(O.beside({ x: 0, y: 1070, width: 40, height: 40 }, 400, 300, 1920, 1080, 8, 8, false).y, 772,
             "nor one at the very bottom")
        T.eq(O.beside({ x: 0, y: 500, width: 40, height: 40 }, 400, 2000, 1920, 1080, 8, 8, false).y, 8,
             "a box taller than the screen starts at the margin rather than above it")

        // The same refusal `under` has: a screen whose size is not known is
        // not a screen to place anything on.
        T.eq(O.beside(pill, 400, 300, 0, 1080, 8, 8, false), null, "no width, no place")
        T.eq(O.beside(pill, 400, 300, 1920, 0, 8, 8, false), null, "nor before the height is known")
        T.eq(O.beside(null, 400, 300, 1920, 1080, 8, 8, false), null, "and nothing to sit beside is nothing")
        T.eq(O.beside(pill, 0, 300, 1920, 1080, 8, 8, false), null, "a box with no width has no place either")

        // ---- barSpot for the two vertical edges ---------------------------

        const onLeft = O.barSpot(44, 1920, "centre", 8, "left", 1080)
        T.eq([onLeft.x, onLeft.y], [0, 540], "a left bar's centre spot is halfway down its own side")
        T.eq([onLeft.width, onLeft.height], [44, 0], "and the rectangle runs down the bar, not across it")
        const onRight = O.barSpot(44, 1920, "centre", 8, "right", 1080)
        T.eq(onRight.x, 1876, "a right bar's spot is at the far side")
        T.eq(O.barSpot(44, 1920, "end", 8, "left", 1080).y, 1072, "the end of a vertical bar is its bottom")
        T.eq(O.barSpot(44, 1920, "centre", 8, "left", 0), null, "a screen with no height is not one to place on")

        // Three spots, not two. "start" used to fall into the else branch with
        // "end", so choosing it in Settings moved notifications nowhere, on
        // any of the four edges - while panels, which read the same setting
        // through ShellPanel, honoured it all along.
        T.eq(O.barSpot(44, 1920, "start", 8, "left", 1080).y, 8, "the start of a vertical bar is its top")
        T.eq(O.barSpot(44, 1920, "start", 8, "right", 1080).y, 8, "on the right-hand one too")
        T.eq(O.barSpot(38, 1920, "start", 8, "top", 1080).x, 8, "and the start of a horizontal bar is its left")
        T.eq(O.barSpot(38, 1920, "start", 8, "bottom", 1080).x, 8, "bottom bar included")
        T.ok(O.barSpot(38, 1920, "start", 8, "top", 1080).x
             !== O.barSpot(38, 1920, "end", 8, "top", 1080).x, "start and end are not the same place")
        T.eq(O.barSpot(38, 30, "start", 8, "top", 1080).x, 8,
             "a screen narrower than two margins still starts at the margin")

        T.finish("OriginTest")
    }
}
