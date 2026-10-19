import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/hypr/PassthroughLogic.js" as P
import "../../services/hypr/HyprCommands.js" as H

// The keyboard passthrough (PassthroughLogic): when the shell hands the keys
// to a window and when it takes them back, and what the chip says.
ShellRoot {
    function window(appId, title, fullscreen, same) {
        return { present: true, same: same === true, appId: appId, title: title, fullscreen: fullscreen === true }
    }

    Component.onCompleted: {
        const session = window("Wfica", "RDS-Desk (SSL/TLS Secured, 256 bit)", true, true)
        const nothing = { present: false, same: false, appId: "", title: "", fullscreen: false }

        T.eq([P.activeIn("passthrough"), P.activeIn(""), P.activeIn("other")], [true, false, false], "Hyprland's word on the submap")
        T.eq([P.citrixSession("Wfica", "RDS-Desk"), P.citrixSession("Wfica", "wfica"), P.citrixSession("wfica", "Desktop"),
              P.citrixSession("Wfica", ""), P.citrixSession("brave-browser", "Citrix")],
             [true, false, true, false, false], "a Citrix session is class Wfica and not its dialog")

        // Automatic: only with the setting, and only a full-screen session.
        T.eq(P.decide({ active: false, enabled: true, focused: session }), "enter", "a full-screen session with the setting on")
        // The IPC way in is the user's, the automatic one the shell's: only
        // that one is taken back when the window stops wanting it.
        T.eq([P.enteredByItself("auto"), P.enteredByItself("enter"), P.enteredByItself(""), P.enteredByItself("leave")],
             [true, false, false, false], "who asked")
        const plain = window("probeX", "a terminal", false, true)
        T.eq(P.decide({ active: true, owner: { appId: "probeX", title: "a terminal" }, auto: P.enteredByItself("enter"), focused: plain }), "",
             "entered over IPC for a plain window: kept while it has the focus")
        T.eq(P.decide({ active: true, owner: { appId: "probeX", title: "a terminal" }, auto: P.enteredByItself("auto"), focused: plain }), "leave",
             "entered by itself for a window that does not want it: given back")
        T.eq(P.decide({ active: false, enabled: false, focused: session }), "", "not with it off")
        T.eq(P.decide({ active: false, enabled: true, focused: window("Wfica", "RDS-Desk", false) }), "", "not in a window")
        T.eq(P.decide({ active: false, enabled: true, focused: window("Wfica", "wfica", true) }), "", "not for Citrix's own dialog")
        T.eq(P.decide({ active: false, enabled: true, focused: session, declined: true }), "",
             "not again for the window the user just took them back from")
        T.eq(P.decide({ active: false, enabled: true, focused: nothing }), "", "nothing in front, nothing to hand over")

        // Taken back.
        const owner = { appId: "Wfica", title: "RDS-Desk" }
        T.eq(P.decide({ active: true, owner: owner, focused: session }), "", "the session keeps them")
        T.eq(P.decide({ active: true, owner: owner, focused: window("org.kde.dolphin", "Home", false) }), "leave",
             "another window in front gives them back")
        T.eq(P.decide({ active: true, owner: owner, focused: window("Wfica", "wfica", false) }), "",
             "Citrix's own dialog is still the session's")
        T.eq(P.decide({ active: true, owner: owner, ownerGone: true, focused: nothing }), "leave", "the window closed")
        T.eq(P.decide({ active: true, owner: owner, auto: true, focused: window("Wfica", "RDS-Desk", false, true) }), "leave",
             "came by itself, goes when the session leaves full screen")
        T.eq(P.decide({ active: true, owner: owner, auto: false, focused: window("Wfica", "RDS-Desk", false, true) }), "",
             "given by the key, stays out of full screen too")
        T.eq(P.decide({ active: true, owner: { appId: "virt-manager", title: "VM" }, focused: window("virt-manager", "VM", false, true) }), "",
             "any window can have them: a virtual machine")
        T.eq(P.decide({ active: true, owner: null, focused: nothing }), "", "entered with nothing in front: stays while nothing is")
        T.eq(P.decide({ active: true, owner: null, focused: window("org.kde.dolphin", "Home", false) }), "leave",
             "and goes when a window comes to the front")
        T.eq(P.decide(null), "", "no state, nothing to do")

        // What the chip says.
        T.eq(P.chipText(owner, "Super+Esc"), "Keys go to Citrix · Super+Esc gives them back", "for Citrix")
        T.eq(P.chipText({ appId: "virt-manager", title: "VM" }, "Super+Esc"), "Keys go to the window · Super+Esc gives them back", "for any other")
        T.eq(P.chipText(null, ""), "Keys go to the window", "without a key to name")
        T.eq([P.chipShort("Super+Esc"), P.chipShort("")], ["Super+Esc", "Keys"], "the short form")

        // The way in and out, in both dialects.
        T.eq(H.submap(P.NAME), { legacy: "submap passthrough", lua: "hl.dsp.submap(\"passthrough\")" }, "into the submap")
        T.eq(H.submap("reset"), { legacy: "submap reset", lua: "hl.dsp.submap(\"reset\")" }, "back")
        T.throwsError(() => H.submap("x; exec rm"), "a submap name is a word")
        T.finish("PassthroughTest")
    }
}
