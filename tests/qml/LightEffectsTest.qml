import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/EffectsLogic.js" as E
import "../../services/power/PowerSourceLogic.js" as P

ShellRoot {
    Component.onCompleted: {
        T.eq([E.normal("light"), E.normal("keep"), E.normal("off"), E.normal(undefined)], ["light", "keep", "keep", "keep"],
             "two choices, keep unless light was chosen")
        T.eq([E.light("light", ""), E.light("keep", ""), E.light(undefined, undefined)], [true, false, false],
             "the choice of the source that applies")
        T.eq([E.light("keep", "light"), E.light("light", "keep"), E.light("light", "bogus")], [true, false, true],
             "IPC's preview wins while it is set, and only with a real value")

        // What the shell and the compositor run.
        T.eq([E.animationMode("full", true), E.animationMode("reduced", true), E.animationMode("off", true)],
             ["reduced", "reduced", "off"], "Full runs as Reduced, the calmer ones stay")
        T.eq([E.animationMode("full", false), E.animationMode("off", false)], ["full", "off"], "not light: the user's own")
        T.eq(E.animationMode("full", "yes"), "full", "only true is light")
        T.eq([E.blurStrength(0.5, true), E.blurStrength(0.5, false), E.blurStrength(0, false)], [0, 0.5, 0],
             "the blur off while light")

        T.ok(P.KEYS.indexOf("effects") >= 0, "a per-source setting, like the profile")
        T.finish("LightEffectsTest")
    }
}
