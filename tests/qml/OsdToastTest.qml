import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/osd/OsdLogic.js" as L
import "../../services/audio/MicLogic.js" as M

// The OSD's short messages for state changes (shell/osd/OsdLogic.js): the
// output, the charger, the VPN and Caps Lock.
ShellRoot {
    Component.onCompleted: {
        T.eq([L.outputToast("", "Headphones"), L.outputToast("Speaker", "Headphones"), L.outputToast("Headphones", "Headphones"),
              L.outputToast("Headphones", " Headphones "), L.outputToast("Speaker", ""), L.outputToast(undefined, undefined)],
             ["Output: Headphones", "Output: Headphones", "", "", "", ""],
             "a new output by name, never the same name twice (a headset's music and call profiles)")

        const battery = (onBattery, charging, percent) => ({ hasBattery: true, onBattery: onBattery, charging: charging, percent: percent })
        T.eq(L.chargerToast(battery(true, false, 54), battery(false, true, 54)), "Charging · 54%", "plugged in, charging")
        T.eq(L.chargerToast(battery(true, false, 80), battery(false, false, 80)), "Plugged in · 80%", "plugged in, held at its limit")
        T.eq(L.chargerToast(battery(false, true, 54.4), battery(true, false, 54.4)), "On battery · 54%", "unplugged")
        T.eq([L.chargerToast(battery(true, false, 50), battery(true, false, 49)),
              L.chargerToast(battery(false, true, 50), battery(false, false, 100))], ["", ""], "no change of source")
        T.eq([L.chargerToast({ hasBattery: false, onBattery: false }, { hasBattery: false, onBattery: false }),
              L.chargerToast(null, battery(false, true, 5)), L.chargerToast(battery(true, false, 5), null)],
             ["", "", ""], "no battery, or nothing to compare")

        const uni = { uuid: "u1", name: "Uni" }
        const home = { uuid: "h1", name: "Home" }
        T.eq([L.vpnToast([], [uni]), L.vpnToast([uni], []), L.vpnToast([uni], [uni]), L.vpnToast([uni, home], [home]),
              L.vpnToast([home], [home, uni]), L.vpnToast([], [{ uuid: "x" }]), L.vpnToast(undefined, undefined)],
             ["VPN connected: Uni", "VPN disconnected", "", "", "VPN connected: Uni", "VPN connected: tunnel", ""],
             "a tunnel up, the last one down, nothing for the rest")

        T.eq([L.capsToast(true), L.capsToast(false), L.capsToast(undefined)], ["Caps Lock on", "Caps Lock off", "Caps Lock off"], "Caps Lock")

        T.eq(["output", "charger", "vpn", "capsLock", "mics"].map(kind => L.previewToast(kind).text),
             ["Output: Headphones", "Charging · 54%", "VPN connected: Example", "Caps Lock on", M.message(true, 0, 2)],
             "a sample for each, the microphones' as MicLogic says it")
        T.eq([L.previewToast("nothing"), L.previewToast(undefined)], [null, null], "no sample for anything else")

        T.finish("OsdToastTest")
    }
}
