import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/ScanLogic.js" as S

// Who keeps the Wi-Fi scan running, and what nmcli's answers say. The
// service itself is not built here (pitfall 82): it would switch the real
// adapter's scanner.
ShellRoot {
    // A run of view arrivals (true) and departures (false); the scan is on
    // while anyone is counted.
    function play(steps) {
        let viewers = 0
        const scanning = []
        for (const value of steps) {
            viewers = S.scanViewers(viewers, value)
            scanning.push(viewers > 0)
        }
        return scanning
    }

    Component.onCompleted: {
        T.eq(play([true, false]), [true, false], "one view starts the scan and stops it")
        // The popup's footer link or the control center's gear: Settings'
        // page arrives before the popup's body is torn down.
        T.eq(play([true, true, false]), [true, true, true], "a second view keeps the scan the first one leaves")
        T.eq(play([true, true, false, false]), [true, true, true, false], "and it stops with the last one")
        T.eq(S.scanViewers(0, false), 0, "a stop with nobody counted stays at nobody")
        T.eq([S.scanViewers(-3, true), S.scanViewers("x", true), S.scanViewers(undefined, false)], [1, 1, 0],
             "a count that is no count starts from nobody")
        // ---- nmcli -t -----------------------------------------------------------
        T.eq(S.splitTerse("Home:1234:wireguard::no"), ["Home", "1234", "wireguard", "", "no"], "fields at ':'")
        T.eq(S.splitTerse("Caf\\: 2\\\\x:u:t"), ["Caf: 2\\x", "u", "t"], "an escaped ':' and '\\' stay in the value")
        T.eq(S.splitTerse(""), [""], "an empty line is one empty field")

        const list = [
            "Fam. Example:aaaa:802-11-wireless:wlp2s0:yes",
            "lo:bbbb:loopback:lo:yes",
            "Home:cccc:wireguard::no",
            "Wired connection 1:dddd:802-3-ethernet::no",
            ""
        ].join("\n")
        const parsed = S.parseConnections(list, "buchhwin-hotspot")
        T.eq(parsed.connections.map(item => item.type), ["wifi", "loopback", "wireguard", "ethernet"], "short types")
        T.eq(parsed.connections[0], { name: "Fam. Example", uuid: "aaaa", type: "wifi", device: "wlp2s0", active: true },
             "a connection's fields")
        T.eq([parsed.wired, parsed.device, parsed.hotspot], [false, "wlp2s0", false], "Wi-Fi in use, no cable, no hotspot")
        const wired = S.parseConnections("Wired connection 1:dddd:802-3-ethernet:enp1s0:yes\nFam. Example:aaaa:802-11-wireless:wlp2s0:yes",
                                         "buchhwin-hotspot")
        T.eq([wired.wired, wired.device], [true, "enp1s0"], "a cable: wired, and its device is the one asked for its address")
        // The hotspot's state comes from the same list (network-helper.py's
        // hotspot-status asks the same question over D-Bus).
        T.eq(S.parseConnections("buchhwin-hotspot:eeee:802-11-wireless:wlp2s0:yes", "buchhwin-hotspot").hotspot, true,
             "the hotspot active in the list")
        T.eq(S.parseConnections("buchhwin-hotspot:eeee:802-11-wireless::no", "buchhwin-hotspot").hotspot, false,
             "listed but not active is off")
        T.eq(S.parseConnections("", "buchhwin-hotspot"), { connections: [], wired: false, device: "", hotspot: false },
             "nothing listed")

        // ---- nmcli monitor --------------------------------------------------
        T.eq([S.monitorNews("NetworkManager is running", true), S.monitorNews("NetworkManager is stopped", true)],
             [false, false], "the banner it starts with is no change")
        T.eq(S.monitorNews("wlp2s0: connected", true), true, "a first line that is a change is one")
        T.eq([S.monitorNews("NetworkManager is running", false), S.monitorNews("NetworkManager is stopped", false)],
             [true, true], "later, NetworkManager going or coming back is news")
        T.eq(S.monitorNews("'Home' is now the primary connection", false), true, "and so is any other line")

        T.finish("NetworkScanTest")
    }
}
