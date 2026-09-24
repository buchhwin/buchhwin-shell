import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/Pinned.js" as Pinned

// The launcher's pinned apps. A nested session can show a row of icons; it
// cannot show what a stored list does when an app is uninstalled, pinned
// twice, or pinned once too often - and those are the cases that lose
// something the user put there on purpose.
ShellRoot {
    function app(id, noDisplay) { return { id: id, name: id, noDisplay: noDisplay === true } }
    readonly property var installed: ["a.desktop", "b.desktop", "c.desktop"].map(id => app(id))

    Component.onCompleted: {
        // ---- reading the string ---------------------------------------------
        T.eq(Pinned.ids(""), [], "nothing stored is nothing pinned")
        T.eq(Pinned.ids(null), [], "and neither is no string at all")
        T.eq(Pinned.ids("a.desktop, b.desktop "), ["a.desktop", "b.desktop"],
             "spaces around an id do not make a new one")
        T.eq(Pinned.ids("a.desktop,a.desktop"), ["a.desktop"], "an id twice is one app")
        T.eq(Pinned.ids(",,a.desktop,,"), ["a.desktop"], "empty parts are not apps")

        // ---- pinning and unpinning -------------------------------------------
        T.eq(Pinned.toggle("", "a.desktop"), "a.desktop", "the first one")
        T.eq(Pinned.toggle("a.desktop", "b.desktop"), "a.desktop,b.desktop",
             "a new one goes to the end, so the ones already there do not move")
        T.eq(Pinned.toggle("a.desktop,b.desktop", "a.desktop"), "b.desktop", "and unpinning takes it out")
        T.eq(Pinned.toggle("a.desktop", ""), "a.desktop", "an empty id changes nothing")
        T.ok(Pinned.has("a.desktop,b.desktop", "b.desktop") && !Pinned.has("a.desktop", "b.desktop"),
             "`has` is what the row's own marking asks")

        // ---- the limit --------------------------------------------------------
        // At the limit, one more is refused rather than quietly dropping the
        // oldest: a list that forgets what you put on it is worse than one
        // that says no.
        let many = ""
        for (let index = 0; index < Pinned.LIMIT; ++index) many = Pinned.toggle(many, "app" + index)
        T.eq(Pinned.ids(many).length, Pinned.LIMIT, "the limit fills up")
        T.ok(Pinned.full(many), "and says so")
        T.eq(Pinned.toggle(many, "one-more"), many, "one more is refused, and nothing is lost")
        T.ok(!Pinned.full(Pinned.toggle(many, "app0")), "unpinning one makes room again")
        T.eq(Pinned.ids("a,b,c,d,e,f,g,h,i,j,k,l").length, Pinned.LIMIT,
             "a string longer than the limit is cut rather than believed")

        // ---- the apps themselves ----------------------------------------------
        T.eq(Pinned.apps("b.desktop,a.desktop", installed).map(entry => entry.id),
             ["b.desktop", "a.desktop"], "the apps come back in the pinned order")
        T.eq(Pinned.apps("a.desktop,gone.desktop,b.desktop", installed).map(entry => entry.id),
             ["a.desktop", "b.desktop"],
             "an app that is not installed right now is skipped for drawing")
        T.eq(Pinned.toggle("a.desktop,gone.desktop,b.desktop", "c.desktop"),
             "a.desktop,gone.desktop,b.desktop,c.desktop",
             "but it stays in the string - an app missing today may be back tomorrow")
        T.eq(Pinned.apps("a.desktop", [app("a.desktop", true)]), [],
             "an app that asks not to be shown is not shown here either")
        T.eq(Pinned.apps("a.desktop", null), [], "and nothing installed is nothing to draw")
        // What Quickshell hands out for the installed applications is not a
        // JS array, however much it behaves like one. Guarding with
        // `Array.isArray` threw the whole list away and the row drew nothing
        // while the ids sat in the settings file.
        T.eq(Pinned.apps("b.desktop", { length: 3, 0: app("a.desktop"), 1: app("b.desktop"), 2: app("c.desktop") })
                   .map(entry => entry.id),
             ["b.desktop"], "a list that is not an Array is still a list")
        T.eq(Pinned.apps("a.desktop", { nope: true }), [], "and something with no length is not")

        // ---- order ------------------------------------------------------------
        T.eq(Pinned.move("a,b,c", "c", -1), "a,c,b", "one moves up")
        T.eq(Pinned.move("a,b,c", "a", 1), "b,a,c", "and down")
        T.eq(Pinned.move("a,b,c", "a", -1), "a,b,c", "the first does not move up")
        T.eq(Pinned.move("a,b,c", "c", 1), "a,b,c", "nor the last down")
        T.eq(Pinned.move("a,b,c", "gone", 1), "a,b,c", "and one that is not pinned moves nowhere")

        T.finish("PinnedTest")
    }
}
