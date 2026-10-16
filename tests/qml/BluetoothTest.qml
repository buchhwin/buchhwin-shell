import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/bluetooth/BluetoothLogic.js" as B

// Who keeps Bluetooth discovery running, and what a typed passkey means. The
// service itself is not built here (pitfall 82): it would talk to the real
// adapter.
ShellRoot {
    // A run of view arrivals (true) and departures (false) against an adapter
    // that does what it is asked, and every question put to BlueZ.
    function play(steps, enabled) {
        let viewers = 0
        let discovering = false
        const asked = []
        for (const value of steps) {
            const step = B.discoveryStep(viewers, value, enabled, discovering)
            viewers = step.viewers
            if (step.start !== null) {
                asked.push(step.start ? "start" : "stop")
                discovering = step.start
            }
        }
        return { viewers: viewers, discovering: discovering, asked: asked }
    }

    Component.onCompleted: {
        // ---- discovery ------------------------------------------------------
        T.eq(play([true, false], true), { viewers: 0, discovering: false, asked: ["start", "stop"] },
             "one view starts the search and stops it")
        // The popup's footer link: Settings arrives before the popup's body
        // is torn down, and the search must outlive the popup.
        T.eq(play([true, true, false], true), { viewers: 1, discovering: true, asked: ["start"] },
             "a second view keeps the search the first one leaves")
        T.eq(play([true, true, false, false], true).asked, ["start", "stop"],
             "and it stops with the last one")
        T.eq(B.discoveryStep(1, true, true, true), { viewers: 2, start: null },
             "a search that runs is not asked to start again (\"Operation already in progress\")")
        T.eq(B.discoveryStep(0, false, true, false), { viewers: 0, start: null },
             "a stop that has nobody to count down asks nothing")
        // Settings' "Search again" after BlueZ dropped the search: a retry,
        // not one more viewer that nobody would ever let go of.
        T.eq(B.discoveryStep(1, true, true, false), { viewers: 1, start: true },
             "asking again while the search should run retries it")
        T.eq(play([true, false, false], true), { viewers: 0, discovering: false, asked: ["start", "stop"] },
             "Settings' \"Stop searching\", then the page closing, leaves nothing running")
        T.eq(play([true, false, true, false], true), { viewers: 0, discovering: false, asked: ["start", "stop", "start", "stop"] },
             "and \"Search again\" before it closes starts one that the close ends")
        T.eq(B.discoveryStep(0, true, false, false), { viewers: 1, start: null },
             "an adapter that is off is counted for but not asked")
        T.eq(B.discoveryStep(-3, false, true, false).viewers, 0, "the count never goes below nothing")

        // ---- the passkey ----------------------------------------------------
        T.eq(B.passkey("482913"), "482913", "six digits are a passkey")
        T.eq(B.passkey("482 913"), "482913", "typed the way the dialog prints codes")
        T.eq(B.passkey(" 012345 "), "012345", "leading zeros and stray spaces")
        T.eq([B.passkey("48291a"), B.passkey("48291"), B.passkey("4829130"), B.passkey("")],
             ["", "", "", ""], "a letter, five digits, seven digits or nothing are not")
        T.eq([B.passkeyPossible(""), B.passkeyPossible("482 9"), B.passkeyPossible("4829130"),
              B.passkeyPossible("48a")], [true, true, false, false],
             "what may still become one while it is typed")

        T.finish("BluetoothTest")
    }
}
