import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/hypr/FullscreenLogic.js" as F

// Is a screen really covered by a fullscreen window? The workspace flag says
// yes too often, and the case that hurt was a client letting its own
// fullscreen go: Hyprland drops the window to maximized and the flag stays
// true for good, so the notch never came back after a video.
ShellRoot {
    Component.onCompleted: {
        const on = ws => ({ workspace: ws, fullscreen: true })
        const off = ws => ({ workspace: ws, fullscreen: false })

        // ---- the case this exists for ----------------------------------

        // Measured in a nested session with a real Wayland set_fullscreen, the
        // path a video player in a browser takes. The compositor's workspace
        // flag is true in the second and third rows alike; only the window
        // tells them apart.
        T.eq(F.hasFullscreenWindow([off(2)], 2), false, "nothing fullscreen, before")
        T.eq(F.hasFullscreenWindow([on(2)], 2), true, "the client asks, and the screen is covered")
        T.eq(F.hasFullscreenWindow([off(2)], 2), false, "the client lets go, and it is not - however stuck the flag is")

        // ---- the right workspace ---------------------------------------

        T.eq(F.hasFullscreenWindow([on(1)], 2), false, "a fullscreen window on another workspace covers nothing here")
        T.eq(F.hasFullscreenWindow([on(1), off(2)], 2), false, "and is not confused with the one that is here")
        T.eq(F.hasFullscreenWindow([off(1), on(2)], 2), true, "the one that is here counts")
        T.eq(F.hasFullscreenWindow([on(2), off(2)], 2), true, "one is enough, whichever comes first")
        T.eq(F.hasFullscreenWindow([off(2), on(2)], 2), true, "and it is looked for past the first window")

        // Ids are compared as numbers: Hyprland hands them out as either.
        T.eq(F.hasFullscreenWindow([{ workspace: "2", fullscreen: true }], 2), true, "an id given as text still matches")
        T.eq(F.hasFullscreenWindow([on(2)], "2"), true, "and so does the one asked for")

        // ---- nothing to go on --------------------------------------------

        // An unknown state must not hide the shell. The shell coming back is
        // the part nobody notices is missing until it is.
        T.eq(F.hasFullscreenWindow([], 2), false, "no windows, nothing covered")
        T.eq(F.hasFullscreenWindow(null, 2), false, "no list at all is not a fullscreen")
        T.eq(F.hasFullscreenWindow(undefined, 2), false, "nor an absent one")
        T.eq(F.hasFullscreenWindow([null, undefined], 2), false, "nor a list of nothings")
        T.eq(F.hasFullscreenWindow([{ workspace: null, fullscreen: true }], 2), false,
             "a window whose workspace is not known yet covers nothing")
        T.eq(F.hasFullscreenWindow([{ fullscreen: true }], 2), false, "and neither does one with no workspace at all")
        T.eq(F.hasFullscreenWindow([on(2)], null), false, "a screen with no workspace is not covered")
        T.eq(F.hasFullscreenWindow([on(2)], undefined), false, "nor one that has not said which")

        // Only a real true counts - an absent or truthy-ish value is not a
        // fullscreen, because the flag comes straight off a Wayland object
        // that may not have answered yet.
        T.eq(F.hasFullscreenWindow([{ workspace: 2 }], 2), false, "no fullscreen flag is not a fullscreen")
        T.eq(F.hasFullscreenWindow([{ workspace: 2, fullscreen: 1 }], 2), false, "and neither is something merely truthy")

        T.finish("FullscreenTest")
    }
}
