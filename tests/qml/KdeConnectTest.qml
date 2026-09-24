import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/kdeconnect/KdeConnectLogic.js" as K

ShellRoot {
    // Synthetic snapshot in the format of scripts/kdeconnect-status.sh.
    FileView { id: sample; path: Qt.resolvedUrl("../fixtures/kdeconnect-status.txt").toString().replace("file://", ""); blockLoading: true }
    // Synthetic notification list (scripts/kdeconnect-notifications.sh).
    FileView { id: notes; path: Qt.resolvedUrl("../fixtures/kdeconnect-notifications.txt").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // busctl JSON
        T.eq(K.busValue("{\"type\":\"s\",\"data\":[\"host\"]}", true), "host", "method result")
        T.eq(K.busValue("{\"type\":\"as\",\"data\":[\"a\"]}", false), ["a"], "property value")
        T.eq(K.busValue("Call failed: not found", true), undefined, "errors ignored")
        T.eq(K.busProperties("{\"type\":\"a{sv}\",\"data\":[{\"charge\":{\"type\":\"i\",\"data\":5}}]}"), { charge: 5 }, "GetAll map")
        T.eq(K.busProperties(""), {}, "empty GetAll")
        T.eq(K.deviceList("{\"type\":\"a{ss}\",\"data\":[{\"abc_1\":\"A: B\",\"x/y\":\"Bad\"}]}"), [{ id: "abc_1", name: "A: B" }], "device names with valid ids")
        T.eq(K.deviceList("{\"type\":\"a{ss}\",\"data\":[{}]}"), [], "no devices")

        // Snapshot
        const status = K.parseStatus(sample.text())
        T.ok(status.known && status.daemon, "daemon running")
        T.eq(status.selfId, "00000000000000000000000000000000", "own id")
        T.eq(status.name, "test-laptop", "announced name")
        T.eq(status.requests, ["_55555555_5555_5555_5555_555555555555_"], "invalid request ids dropped")
        T.eq(status.devices.map(item => item.name), ["Guest Phone", "Test Phone", "Tablet: Living Room", "Nearby Phone"], "sorted: request, connected, paired, available")
        const [guest, phone, tablet, nearby] = status.devices
        T.ok(guest.requestedByPeer && !guest.paired, "incoming pair request")
        T.eq(guest.verificationKey, "9F3E 12AB", "verification key")
        T.eq(K.stateText(guest), "Wants to pair", "request label")
        T.eq(phone.battery, { charge: 76, charging: true }, "battery")
        T.eq(K.batteryText(phone.battery), "Charging · 76%", "battery text")
        T.eq(K.stateText(phone), "Connected", "connected label")
        T.eq(phone.type, "phone", "device type")
        T.eq(tablet.battery, null, "unknown charge hidden")
        T.eq(K.stateText(tablet), "Paired, not reachable", "paired label")
        T.eq(K.deviceIcon(tablet.type), "󰓶", "tablet icon")
        T.eq(K.stateText(nearby), "Waiting for the phone to accept…", "outgoing request label")
        T.eq(K.stateText({ paired: false, reachable: true }), "Available to pair", "available label")
        T.ok(K.supports(phone, "share") && !K.supports(phone, "findmyphone"), "plugins from the phone")
        T.ok(K.supports(tablet, "findmyphone"), "empty plugin list allows actions")

        // Plugin data of a connected phone
        T.eq(phone.connectivity, { type: "LTE", strength: 3 }, "cellular report")
        T.eq(K.signalText(phone.connectivity), "LTE · Good", "signal text")
        T.eq(K.signalIcon(phone.connectivity), "󰤥", "signal icon")
        T.eq(K.signalText(null), "", "no signal text without the plugin")
        T.eq(K.signalIcon(null), "󰤯", "signal icon without the plugin")
        T.eq(K.connectivity({}), null, "device without a SIM report")
        T.eq(K.connectivity({ cellularNetworkType: "Unknown", cellularNetworkStrength: 7 }), { type: "", strength: 4 },
             "unknown type dropped, strength clamped")
        T.eq(K.signalText({ type: "", strength: -1 }), "No signal", "unknown strength")
        T.eq(K.detailText(phone), "Connected · Charging · 76% · LTE · Good", "device detail line")
        T.eq(K.detailText(tablet), "Paired, not reachable", "detail line without plugin data")
        T.eq(phone.media.players, ["Sample Player", "Podcasts"], "player list")
        T.eq([phone.media.player, phone.media.playing, phone.media.volume], ["Sample Player", true, 42], "current player")
        T.eq(K.mediaTitle(phone.media), "Sample Track", "media title")
        T.eq(K.mediaSubtitle(phone.media), "Sample Artist · Sample Player · Playing", "media subtitle")
        T.eq(K.media({ playerList: [] }), null, "no players")
        T.eq(K.media({ playerList: ["A"], volume: 250 }), { players: ["A"], player: "", playing: false, title: "",
                                                            artist: "", album: "", volume: -1 }, "bad volume hidden")
        T.eq(K.mediaSubtitle(K.media({ playerList: ["A"], player: "A" })), "Paused", "paused player without metadata")
        T.eq(tablet.media, null, "no media without the plugin")
        T.eq([phone.notificationCount, phone.locked], [3, false], "notification count without texts, lock state")
        T.eq(phone.commands.map(entry => entry.name), ["Reboot", "Screenshot"], "the commands the phone offers")
        T.eq(phone.mounted, false, "not mounted over SFTP")
        T.eq(tablet.commands, [], "no commands without the plugin")
        T.eq(tablet.notificationCount, 0, "no notifications without the plugin")
        T.eq(K.notificationCountText(1), "1 notification", "one notification")
        T.eq(K.notificationCountText(3), "3 notifications", "several notifications")

        // Notification list (contents stay in the shell process)
        const list = K.parseNotifications(notes.text())
        T.eq(list.map(item => item.id), ["7", "4", "2"], "newest first, invalid ids dropped")
        T.eq(list[1], { id: "4", appName: "Chat", title: "Sample Contact", text: "See you at six",
                        dismissable: true, replyId: "reply-4" }, "notification row")
        T.eq(list[0].replyId, "", "a notification without a reply action carries no reply id")
        T.eq([list[0].title, list[0].dismissable], ["Sample Track", false], "ticker used when the title is empty")
        T.eq(K.parseNotifications(""), [], "empty list")
        T.eq(K.summary(status), "1 connected · 2 paired", "summary")
        T.eq(K.summary(K.parseStatus("@daemon stopped\n")), "KDE Connect is not running", "stopped")
        T.eq(K.summary(K.parseStatus("")), "Checking KDE Connect…", "unknown before the first run")
        T.eq(K.parseStatus("@daemon running\n@devices\n{\"type\":\"a{ss}\",\"data\":[{}]}\n@end\n").devices, [], "empty snapshot")
        const bare = K.parseStatus("@devices\n{\"type\":\"a{ss}\",\"data\":[{\"abc\":\"Old\"}]}\n@device abc\nCall failed\n").devices[0]
        T.eq([bare.name, bare.paired, bare.reachable, bare.battery], ["Old", false, false, null], "device without properties")

        // Commands
        const id = "11111111111111111111111111111111"
        T.eq(K.command("ping", id), ["kdeconnect-cli", "--device", id, "--ping"], "ping argv")
        T.eq(K.command("share", id, "/home/user/a file; rm -rf ~"), ["kdeconnect-cli", "--device", id, "--share", "/home/user/a file; rm -rf ~"], "file is one argument")
        T.eq(K.command("share", id, "-rf"), null, "relative or option-like paths rejected")
        T.eq(K.command("accept", id), ["busctl", "--user", "--auto-start=no", "call", "org.kde.kdeconnect", "/modules/kdeconnect/devices/" + id, "org.kde.kdeconnect.device", "acceptPairing"], "accept through D-Bus")
        T.eq(K.command("ping", "--help"), null, "option-like id rejected")
        T.eq(K.command("reject", "a/../b"), null, "path-like id rejected")
        T.eq(K.command("format", id), null, "unknown action")
        T.eq(K.parseFiles("/tmp/a b.png\nrelative\n\n/tmp/c\n"), ["/tmp/a b.png", "/tmp/c"], "picked files")

        // Plugin actions
        const mprisPath = "/modules/kdeconnect/devices/" + id + "/mprisremote"
        const busCall = ["busctl", "--user", "--auto-start=no", "call", "org.kde.kdeconnect"]
        const busSet = ["busctl", "--user", "--auto-start=no", "set-property", "org.kde.kdeconnect"]
        T.eq(K.command("play", id), busCall.concat([mprisPath, "org.kde.kdeconnect.device.mprisremote", "sendAction", "s", "PlayPause"]), "play/pause")
        T.eq(K.command("next", id)[9], "Next", "next track")
        T.eq(K.command("previous", id)[9], "Previous", "previous track")
        T.eq(K.command("volume", id, 42), busSet.concat([mprisPath, "org.kde.kdeconnect.device.mprisremote", "volume", "i", "42"]), "phone volume")
        T.eq(K.command("volume", id, 120), null, "volume out of range")
        T.eq(K.command("volume", id, "50"), null, "volume must be a number")
        T.eq(K.command("player", id, "Sample Player"), busSet.concat([mprisPath, "org.kde.kdeconnect.device.mprisremote", "player", "s", "Sample Player"]), "player choice is one argument")
        T.eq(K.command("player", id, "a\nb"), null, "player name with a newline rejected")
        T.eq(K.command("dismiss", id, "12"), busCall.concat(["/modules/kdeconnect/devices/" + id + "/notifications/12",
                                                             "org.kde.kdeconnect.device.notifications.notification", "dismiss"]), "dismiss a notification")
        T.eq(K.command("dismiss", id, "../device"), null, "path-like notification id rejected")
        T.eq(K.command("sms", id), ["kdeconnect-sms", "--device", id], "SMS app")
        T.eq(K.command("lock", id), ["kdeconnect-cli", "--device", id, "--lock"], "lock the phone")
        T.eq(K.command("unlock", id), ["kdeconnect-cli", "--device", id, "--unlock"], "unlock the phone")

        // Answering a notification, the phone's own commands, browsing it
        const notePath = "/modules/kdeconnect/devices/" + id + "/notifications/12"
        const noteIface = "org.kde.kdeconnect.device.notifications.notification"
        T.eq(K.command("reply", id, { note: "12", text: "On my way" }),
             busCall.concat([notePath, noteIface, "sendReply", "s", "On my way"]), "answer a notification")
        T.eq(K.command("reply", id, { note: "../x", text: "hi" }), null, "path-like notification id rejected")
        T.eq(K.command("reply", id, { note: "12", text: "" }), null, "an empty answer is not sent")
        T.eq(K.command("reply", id, { note: "12", text: "a\nb" })[9], "a\nb",
             "an answer of several lines is one argument, not several")
        T.eq(K.command("reply", id, undefined), null, "nothing to answer")
        T.eq(K.command("runCommand", id, "abc123"),
             busCall.concat(["/modules/kdeconnect/devices/" + id + "/remotecommands",
                             "org.kde.kdeconnect.device.remotecommands", "triggerCommand", "s", "abc123"]),
             "run a command the phone offers")
        T.eq(K.command("runCommand", id, "--help"), null, "option-like command key rejected")
        T.eq(K.command("browse", id),
             busCall.concat(["/modules/kdeconnect/devices/" + id + "/sftp",
                             "org.kde.kdeconnect.device.sftp", "startBrowsing"]), "browse the phone")

        // The runcommand plugin reports its commands as JSON of its own.
        T.eq(K.remoteCommands('{"b7":{"name":"Screenshot","command":"scrot"},"a1":{"name":"Reboot","command":"reboot"}}'),
             [{ key: "a1", name: "Reboot" }, { key: "b7", name: "Screenshot" }], "commands by name, without the command line")
        T.eq(K.remoteCommands('{"a1":{}}'), [{ key: "a1", name: "Command" }], "a command without a name still has one")
        T.eq(K.remoteCommands('{"../x":{"name":"Bad"}}'), [], "a key that is not an id is dropped")
        T.eq(K.remoteCommands("not json"), [], "unreadable commands")
        T.eq(K.remoteCommands(""), [], "no commands")
        T.eq(K.remoteCommands("[1,2]"), [], "a list is not a command map")

        // Send link or text
        T.eq(K.shareAction("https://example.org/a?b=c"), { action: "url", value: "https://example.org/a?b=c" }, "link stays a link")
        T.eq(K.shareAction(" example.org/page "), { action: "url", value: "https://example.org/page" }, "bare host gets https")
        T.eq(K.shareAction("Remember the milk"), { action: "text", value: "Remember the milk" }, "plain text")
        T.eq(K.shareAction("1.5"), { action: "text", value: "1.5" }, "a number with a dot is text, not a site")
        T.eq(K.shareAction("v2.0"), { action: "text", value: "v2.0" }, "so is a version")
        T.eq(K.shareAction("example.co2"), { action: "url", value: "https://example.co2" }, "a letter in the last label makes a host")
        T.eq(K.shareAction("-rf"), { action: "text", value: "-rf" }, "option-like text is still one argument")
        T.eq(K.shareAction("   "), null, "nothing to send")
        T.eq(K.command("url", id, "javascript:alert(1)"), null, "only http(s) links")
        T.eq(K.command("url", id, "https://example.org"), ["kdeconnect-cli", "--device", id, "--share", "https://example.org"], "link argv")
        T.eq(K.command("text", id, "a; rm -rf ~"), ["kdeconnect-cli", "--device", id, "--share-text", "a; rm -rf ~"], "text is one argument")
        T.eq(K.command("text", id, "  "), null, "empty text rejected")
        T.eq(K.command("play", "a/../b"), null, "path-like id rejected for media")
        T.finish("KdeConnectTest")
    }
}
