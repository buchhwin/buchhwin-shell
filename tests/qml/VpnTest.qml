import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/VpnLogic.js" as V

// VPN switches (services/network/VpnLogic.js): what a row shows while nmcli
// brings a tunnel up or down, and what nmcli's answer means. The service is
// not built here (pitfall 82): its switches are the real tunnels.
ShellRoot {
    Component.onCompleted: {
        const home = { name: "Home", uuid: "aaaa", type: "wireguard", active: false }
        const work = { name: "Work", uuid: "bbbb", type: "vpn", active: true }

        // ---- under way ------------------------------------------------------
        let pending = V.begin({}, "aaaa", true, 1)
        T.eq(pending, { aaaa: { up: true, seq: 1 } }, "a switch asked for is pending")
        T.eq([V.checked(home, pending), V.status(home, pending)], [true, "Connecting …"],
             "the switch moves at once and the row says what is happening")
        T.eq([V.checked(work, pending), V.status(work, pending)], [true, "Connected"], "the others say where they are")
        T.eq(V.status(home, {}), "Off", "nothing pending: off")
        T.eq(V.status(work, V.begin({}, "bbbb", false, 2)), "Disconnecting …", "going down")
        T.eq([V.pendingText({}), V.pendingText(pending), V.pendingText(V.begin({}, "bbbb", false, 2))],
             ["", "Connecting …", "Disconnecting …"], "the quick tile's line")
        T.eq(V.begin({}, "", true, 3), {}, "no tunnel, nothing pending")

        // ---- answered ---------------------------------------------------------
        T.eq(V.finish(pending, "aaaa", 1), { pending: {}, current: true }, "the answer to the latest switch ends it")
        const newer = V.begin(pending, "aaaa", false, 2)
        T.eq(V.finish(newer, "aaaa", 1), { pending: newer, current: false },
             "the answer to one switched again since is not news, and the newer one stays pending")
        T.eq(V.finish({}, "aaaa", 1).current, false, "nothing pending, nothing current")

        T.eq(V.result("0\nConnection successfully activated (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/7)\n"),
             { ok: true, message: "" }, "exit 0 is done")
        T.eq(V.result("4\nError: Connection activation failed: Secrets were required, but not provided\nHint: use 'journalctl -xe NM_CONNECTION=aaaa' to get more details.\n"),
             { ok: false, message: "Connection activation failed: Secrets were required, but not provided" },
             "nmcli's reason, without the journalctl hint")
        T.eq(V.result("10\nsomething else\n"), { ok: false, message: "something else" }, "a line without 'Error:'")
        T.eq(V.result("8\n\n"), { ok: false, message: "nmcli exited with 8" }, "nothing said: the status")
        T.eq(V.result(""), { ok: false, message: "nmcli exited with an error" }, "no answer at all")

        // A switch that answered "done" moves its tunnel in the list at once,
        // so the row does not fall back to the old list until the refresh.
        const list = [home, work]
        const up = V.settled(list, "aaaa", true)
        T.eq(up.map(item => item.active), [true, true], "brought up: active before the next read")
        T.eq([up[1] === work, home.active], [true, false], "the others are the same objects, the old list is untouched")
        T.eq(V.settled(list, "bbbb", false).map(item => item.active), [false, false], "taken down: inactive")
        T.eq([V.settled(list, "bbbb", true) === list, V.settled(list, "gone", true) === list, V.settled(null, "aaaa", true)],
             [true, true, []], "nothing to change: the same list")

        // ---- the quick tile's tunnel ----------------------------------------
        T.eq([V.preferred([home, work], "bbbb"), V.preferred([home, work], "gone"), V.preferred([home, work], ""),
              V.preferred([], "bbbb")], ["bbbb", "aaaa", "aaaa", ""],
             "the one used last while it is there, else the first")

        T.finish("VpnTest")
    }
}
