import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/PortalLogic.js" as P

// Captive portals (services/network/PortalLogic.js): when the way to the
// sign-in page is offered, the one notification per network, and the
// address the browser opens.
ShellRoot {
    Component.onCompleted: {
        // Offered only for a portal that has held (NetworkService.limited is
        // the settled flag), never for "no internet" of another kind.
        T.eq([P.signInNeeded("portal", true), P.signInNeeded("portal", false), P.signInNeeded("limited", true),
              P.signInNeeded("none", true), P.signInNeeded("full", true), P.signInNeeded(undefined, true)],
             [true, false, false, false, false, false], "a settled portal only")

        T.eq([P.connectionKey("Hotel Guest", false), P.connectionKey("", true), P.connectionKey("", false),
              P.connectionKey("WIFIonICE", true)],
             ["wifi:Hotel Guest", "wired", "", "wifi:WIFIonICE"], "the Wi-Fi network by name, a wire as one")
        T.eq([P.networkName("Hotel Guest", false), P.networkName("", true), P.networkName(undefined, false)],
             ["Hotel Guest", "the wired network", "this network"], "the network in words")

        // Once per network: the first settled portal notifies, a flap of the
        // check or of the Wi-Fi does not, the internet back clears it, and
        // the same network notifies again only after the cooldown.
        const input = (key, portal, full, now) => ({ key: key, portal: portal, full: full, now: now, enabled: true })
        let step = P.notifyStep({ notified: {} }, input("wifi:Hotel", true, false, 1000))
        T.eq([step.notify, step.dismiss], [true, false], "the first portal notifies")
        step = P.notifyStep(step.state, input("wifi:Hotel", true, false, 2000))
        T.eq(step.notify, false, "and the same portal does not again")
        step = P.notifyStep(step.state, input("", false, false, 3000))
        step = P.notifyStep(step.state, input("wifi:Hotel", true, false, 4000))
        T.eq(step.notify, false, "nor after the Wi-Fi dropped and came back, unsigned")
        step = P.notifyStep(step.state, input("wifi:Hotel", false, true, 5000))
        T.eq([step.notify, step.dismiss], [false, true], "the internet back: the notice can go")
        step = P.notifyStep(step.state, input("wifi:Hotel", false, true, 6000))
        T.eq(step.dismiss, false, "and only once")
        step = P.notifyStep(step.state, input("wifi:Hotel", true, false, 7000))
        T.eq(step.notify, false, "a portal again within the cooldown: a flap of the check, quiet")
        step = P.notifyStep(step.state, input("wifi:Hotel", true, false, 1000 + P.COOLDOWN_MS))
        T.eq(step.notify, true, "signed in, and the portal back after the cooldown (the next day): notifies")
        const other = P.notifyStep(step.state, input("wifi:Train", true, false, 1000 + P.COOLDOWN_MS + 1))
        T.eq(other.notify, true, "another network notifies on its own")
        T.eq(Object.keys(other.state.notified).sort(), ["wifi:Hotel", "wifi:Train"], "kept per network")
        const off = P.notifyStep({ notified: {} }, { key: "wifi:Cafe", portal: true, full: false, now: 1, enabled: false })
        T.eq([off.notify, Object.keys(off.state.notified).length], [false, 0], "switched off: nothing, and nothing marked")
        T.eq(P.notifyStep(null, input("", true, false, 1)).notify, false, "no connection, no notice")
        T.eq(P.notifyStep(undefined, input("wired", true, false, 1)).notify, true, "a wired portal too")

        T.eq(P.notice("Hotel Guest"), { title: "Sign in to Hotel Guest",
                                        body: "This network asks you to sign in before it reaches the internet.",
                                        icon: "network-wireless" }, "the notice")

        // NetworkManager's check address, as busctl prints it.
        T.eq(P.parseUri('s "http://ping.archlinux.org/nm-check.txt"\n'), "http://ping.archlinux.org/nm-check.txt", "busctl's string")
        T.eq([P.parseUri('s ""'), P.parseUri(""), P.parseUri("Failed to get property"), P.parseUri('b true')],
             ["", "", "", ""], "nothing usable")
        T.eq(P.parseUri('s "http://example.test/a\\"b"'), 'http://example.test/a"b', "an escaped quote")
        // Plain http is what a portal answers in its place; anything else
        // takes the fallback.
        T.eq(P.signInUrl("http://ping.archlinux.org/nm-check.txt"), "http://ping.archlinux.org/nm-check.txt", "the check address")
        T.eq([P.signInUrl("https://example.test/"), P.signInUrl(""), P.signInUrl("http://"), P.signInUrl("file:///etc/passwd"),
              P.signInUrl("javascript:alert(1)"), P.signInUrl("http://a b")],
             [P.FALLBACK_URL, P.FALLBACK_URL, P.FALLBACK_URL, P.FALLBACK_URL, P.FALLBACK_URL, P.FALLBACK_URL], "the fallback")
        T.eq(P.FALLBACK_URL.indexOf("http://"), 0, "a fallback that is plain http")

        T.finish("PortalTest")
    }
}
