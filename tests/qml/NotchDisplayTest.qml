import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notch/NotchDisplay.js" as Display

// Who gets the notch when more than one thing wants it. A nested session can
// show a volume bar in the notch; it cannot show what happens when a
// notification arrives during one, or on the second monitor that has no notch,
// and those are the two the plan said the time would go into.
ShellRoot {
    function state(extra) {
        return Object.assign({ enabled: true, notchShown: true, hasNotch: true,
                               overviewOpen: false, arranging: false }, extra || {})
    }

    Component.onCompleted: {
        // ---- the three kinds, each on its own switch --------------------------
        T.eq(Display.KINDS, ["osd", "notification", "media"], "three things can ask for the notch")
        T.eq(Display.KINDS.map(Display.setting),
             ["notch.displayOsd", "notch.displayNotifications", "notch.displayMedia"],
             "and each has its own setting, named in one place")
        T.eq(Display.setting("nonsense"), "", "something that is not a kind has no setting")

        // ---- when the notch may take it ---------------------------------------
        T.ok(Display.takes("osd", state()), "with everything in place, the notch takes it")
        T.ok(!Display.takes("osd", state({ enabled: false })), "its own switch is off")
        T.ok(!Display.takes("nonsense", state()), "it is not one of the three")

        // The answer for a screen with no notch, which is the question that was
        // left open: it does exactly what it always did.
        T.ok(!Display.takes("osd", state({ notchShown: false })),
             "widgets or bar mode: no notch to take")
        T.ok(!Display.takes("osd", state({ hasNotch: false })),
             "a second monitor without one, or a notch behind a fullscreen window")

        T.ok(!Display.takes("notification", state({ overviewOpen: true })),
             "the overview is on screen because the user put it there")
        T.ok(!Display.takes("media", state({ arranging: true })),
             "and nothing takes a notch that is being arranged")

        // Each kind is asked separately, so two can differ at the same moment.
        T.ok(Display.takes("osd", state()) && !Display.takes("notification", state({ enabled: false })),
             "the volume bar in the notch and notifications still below it")

        // ---- who wins ---------------------------------------------------------
        T.eq(Display.current(null), null, "nothing set is nobody")
        T.eq(Display.current({}), null, "and neither is an empty set of slots")
        T.eq(Display.current({ osd: { stamp: 1, content: { icon: "a" } } }).kind, "osd", "one is that one")
        T.eq(Display.current({ osd: { stamp: 1, content: {} }, notification: null }).kind, "osd",
             "an empty slot is not a contender")
        T.eq(Display.current({ osd: { stamp: 1, content: {} }, notification: { stamp: 2, content: {} } }).kind,
             "notification", "the later one wins")
        T.eq(Display.current({ osd: { stamp: 5, content: {} }, notification: { stamp: 2, content: {} } }).kind,
             "osd", "and it is the stamp that decides, not the order of the kinds")
        // The case the rule exists for: pressing a volume key while a
        // notification is up must show the volume, or the key looks broken.
        T.eq(Display.current({ notification: { stamp: 7, content: {} }, osd: { stamp: 8, content: {} } }).kind,
             "osd", "a key pressed during a notification shows what the key did")
        T.eq(Display.current({ osd: { stamp: 3, content: null } }), null,
             "a slot whose content was cleared is empty, whatever its stamp says")
        T.eq(Display.current({ media: { stamp: 4, content: { title: "x" } } }).content.title, "x",
             "the winner brings its content with it")

        // ---- what a page says -------------------------------------------------
        T.eq(Display.enabledKinds({ osd: true, notification: false, media: true }), ["osd", "media"],
             "which switches are on, in the order they are listed")
        T.eq(Display.enabledKinds(null), [], "and none when nothing is")

        T.finish("NotchDisplayTest")
    }
}
