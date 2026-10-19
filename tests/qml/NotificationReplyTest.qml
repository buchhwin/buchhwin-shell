//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.shell.notifications
import "Harness.js" as T

// A card's inline reply (KDE Connect's text messages): the field is built only
// on a card whose notification takes an answer, the answer goes to the sender
// trimmed and the card closes, an empty one sends nothing. Under the lock
// screen's shell id, so the service the card asks runs no server (pitfall 82).
ShellRoot {
    id: root
    property var replies: []
    property int closedCount: 0

    function message(withReply, extra) {
        return Object.assign({
            id: 7, appName: "KDE Connect", summary: "Anna", body: "Lunch?", urgency: 1, image: "", appIcon: "",
            actions: [], hints: {}, hasInlineReply: withReply, inlineReplyPlaceholder: "Answer Anna",
            sendInlineReply: text => { root.replies = root.replies.concat([text]) },
            dismiss: () => {}
        }, extra || {})
    }

    property Item box: Item {
        width: 400; height: 1200
        NotificationCard { id: sms; width: 400; notification: root.message(true); onClosed: root.closedCount += 1 }
        NotificationCard { id: plain; y: 300; width: 400; notification: root.message(false) }
        NotificationCard { id: kept; y: 600; width: 400; notification: root.message(true, { earlier: true }) }
    }

    Component.onCompleted: {
        T.ok(sms.replyShown && sms.replyField !== null, "a text message's card has a reply field")
        T.eq(sms.replyField.placeholder, "Answer Anna", "named as the sender names it")
        T.eq([plain.replyShown, plain.replyField], [false, null], "any other card builds none")
        T.eq([kept.replyShown, kept.replyField], [false, null], "nor does one kept from before a restart")
        T.eq(sms.replying, false, "nothing is typed yet")

        sms.replyField.text = "   "
        sms.sendReply()
        T.eq([root.replies, root.closedCount], [[], 0], "a blank answer sends nothing and keeps the card")

        sms.replyField.text = "  on my way "
        sms.sendReply()
        T.eq(root.replies, ["on my way"], "the answer goes to the sender, trimmed")
        T.eq([root.closedCount, sms.replyField.text], [1, ""], "and the card closes with the field emptied")

        T.finish("NotificationReplyTest")
    }
}
