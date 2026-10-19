import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/bluetooth/BluetoothLogic.js" as B

// Who keeps Bluetooth discovery running, what a typed passkey means, when the
// pairing agent runs and what follows a pairing. The service itself is not
// built here (pitfall 82): it would talk to the real adapter.
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

        // ---- the pairing agent ------------------------------------------------
        const idle = { enabled: true, viewers: 0, discoverable: false, grace: false, pairing: false,
                       untrusted: false, asking: false }
        const wanted = change => B.agentWanted(Object.assign({}, idle, change))
        T.eq(wanted({}), false, "Bluetooth on, nothing to pair: no agent")
        T.eq([wanted({ viewers: 1 }), wanted({ discoverable: true }), wanted({ grace: true }),
              wanted({ pairing: true }), wanted({ untrusted: true })], [true, true, true, true, true],
             "a view open, discoverable, a pairing started or under way, an untrusted paired device: the agent runs")
        T.eq([wanted({ enabled: false, viewers: 2 }), wanted({ enabled: false, untrusted: true })], [false, false],
             "Bluetooth off: BlueZ can ask nothing, whatever is open")
        T.eq(wanted({ enabled: false, asking: true }), true, "a question on screen keeps it, to be answered")
        T.eq([B.agentWanted(null), B.agentWanted({ viewers: 3 })], [false, false], "no state, no adapter on: no agent")

        T.eq(B.agentStopped(0, false, false), null, "a stop the shell asked for (Bluetooth off) is no failure")
        T.eq(B.agentStopped(2, true, true), null, "nor one during the pause before a retry")
        T.eq(B.agentStopped(0, true, false), { failures: 1, retryIn: 5000 }, "a crash: the first retry after 5 s")
        T.eq(B.agentStopped(3, true, false), { failures: 4, retryIn: 40000 }, "doubling")
        T.eq(B.agentStopped(5, true, false), { failures: 6, retryIn: -1 }, "after five failures it stays off")
        T.eq(B.agentStopped(2, false, false, true), null, "a stop the shell asked for, still not wanted: nothing")
        T.eq(B.agentStopped(2, true, false, true), { failures: 2, retryIn: 0 },
             "asked to stop and wanted again before it was gone (a view reopened): again at once, no failure")

        // ---- after a pairing ------------------------------------------------
        const path = "/org/bluez/hci0/dev_00_11_22_33_44_55"
        const address = "00:11:22:33:44:55"
        const device = change => Object.assign({ address: address, path: path, paired: false, pairing: false,
                                                 connected: false, trusted: false }, change)
        T.eq([B.addressFromPath(path), B.addressFromPath("/org/bluez/hci0"), B.addressFromPath(undefined)],
             [address, "", ""], "a device's address from its object path")
        T.eq(B.stateFor([device({})], path, "").address, address, "the state by path")
        T.eq(B.stateFor([device({ path: "" })], "", "00:11:22:33:44:55").address, address, "or by address")
        T.eq(B.stateFor([device({})], "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", ""), null, "another device is not it")

        let started = B.startPairing({}, "00:11:22:33:44:55")
        T.eq(started, { "00:11:22:33:44:55": { seen: false } }, "a pairing the shell starts is remembered")
        T.eq(B.afterPairing(started, [device({})], true), { trust: [], started: started },
             "before the device reports pairing it waits")
        let step = B.afterPairing(started, [device({ pairing: true })], true)
        T.eq(step, { trust: [], started: { "00:11:22:33:44:55": { seen: true } } }, "pairing: seen")
        T.eq(B.afterPairing(step.started, [device({ paired: true })], true), { trust: [address], started: {} },
             "paired (Just Works, the agent never asked): trust and connect, then forget it")
        T.eq(B.afterPairing(step.started, [device({})], true), { trust: [], started: {} },
             "seen pairing, stopped without a bond: failed, forgotten, nothing trusted")
        T.eq(B.afterPairing(started, [], true).started, started, "a device not listed (yet) waits")
        T.eq(B.afterPairing(started, [device({})], false), { trust: [], started: {} },
             "until the grace time is over")
        T.eq(B.afterPairing(started, [device({ paired: true })], false).trust, [address],
             "a bond found at the end of the grace time still counts")

        // A code to type on the other device: BlueZ sends no Cancel when that
        // pairing is done, so the dialog goes when the device has paired.
        const message = { kind: "display", name: "Keyboard", passkey: "000042", device: path }
        let shown = B.displayFor(message, [device({ pairing: true })])
        T.eq(shown, { name: "Keyboard", passkey: "000042", device: path, address: address, paired: false, pairing: true },
             "the code knows its device and how it was when the code came")
        T.eq(B.displayStep(shown, [device({ pairing: true })]).done, false, "while it pairs the code stays")
        T.eq(B.displayStep(shown, [device({ paired: true })]), { done: true, display: null }, "paired: the code goes")
        T.eq(B.displayStep(shown, [device({})]).done, true, "a pairing that stopped without a bond (wrong code): it goes")
        shown = B.displayFor(message, [device({})])
        T.eq(B.displayStep(shown, [device({})]).done, false,
             "a pairing the other side started (never `pairing` here) keeps the code until it has paired")
        const caught = B.displayStep(shown, [device({ pairing: true })])
        T.eq([caught.done, caught.display.pairing], [false, true], "a pairing seen later is noted")
        T.eq(B.displayStep(caught.display, [device({})]).done, true, "and its end ends the code")
        T.eq(B.displayStep(B.displayFor(message, [device({ paired: true })]), [device({ paired: true })]).done, false,
             "a device paired before the code came does not end it")
        T.eq(B.displayStep({ name: "Example device", passkey: "482913", preview: true }, [device({ paired: true })]).done,
             false, "a code without a device (the preview) waits for the user")

        T.finish("BluetoothTest")
    }
}
