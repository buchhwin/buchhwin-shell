import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/ScanLogic.js" as S

// Who keeps the Wi-Fi scan running. The service itself is not built here
// (pitfall 82): it would switch the real adapter's scanner.
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
        T.finish("NetworkScanTest")
    }
}
