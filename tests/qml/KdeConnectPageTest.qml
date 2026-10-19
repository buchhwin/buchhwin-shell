import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/kdeconnect/KdeConnectLogic.js" as K

// Settings > Phone across a poll. The real page, in a window that is never
// shown, so PageActivity never starts the tracker: no status script, no bus.
// The snapshots come from the fixture, as the 10-s poll would bring them:
// the same one again, then one with the battery at 77 instead of 76. A row
// is the same object after both, with its open share field and what was
// typed in it; the commands and the notifications under it keep theirs.
ShellRoot {
    id: root
    FileView { id: fixture; path: Qt.resolvedUrl("../fixtures/kdeconnect-status.txt").toString().replace("file://", ""); blockLoading: true }
    FileView { id: notes; path: Qt.resolvedUrl("../fixtures/kdeconnect-notifications.txt").toString().replace("file://", ""); blockLoading: true }

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 1400
        visible: false
        Loader { id: loader; width: 860; active: false; sourceComponent: KdeConnectPage {} }
    }

    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }
    function devices() { return walk(loader.item, item => item.shareOpen !== undefined && item.commandsOpen !== undefined, []) }
    function field(under, placeholder) {
        return walk(under, item => item.placeholder === placeholder && item.text !== undefined, [])[0] || null
    }
    function commandRows(under) { return walk(under, item => item.command !== undefined && item.title !== undefined, []) }
    function noteRows(under) { return walk(under, item => item.answering !== undefined, []) }
    function snapshot(charge) {
        return K.parseStatus(fixture.text().replace('"charge":{"type":"i","data":76}', '"charge":{"type":"i","data":' + charge + '}'))
    }

    Timer {
        interval: 50; running: true
        onTriggered: {
            KdeConnectService.status = root.snapshot(76)
            loader.active = true
            check.start()
        }
    }
    Timer {
        id: check; interval: 100
        onTriggered: {
            const before = root.devices()
            T.eq(before.map(row => row.device.name), ["Test Phone", "Tablet: Living Room"], "the paired devices have rows")
            const phone = before[0]
            phone.shareOpen = true
            const share = root.field(phone, "Link or text to send to the phone")
            T.ok(share !== null, "the share field is there")
            if (share) share.text = "half a link"
            phone.commandsOpen = true
            const commands = root.commandRows(phone)
            T.eq(commands.map(row => row.title), ["Reboot", "Screenshot"], "the phone's commands by name")

            // The phone's notifications, open, with an answer being typed.
            KdeConnectService.notificationsId = phone.modelData
            KdeConnectService.notifications = K.parseNotifications(notes.text())
            const shown = root.noteRows(phone)
            T.eq(shown.map(row => row.note.id), ["7", "4", "2"], "the notifications, newest first")
            const chat = shown.find(row => row.note.id === "4")
            chat.answering = true
            const answer = root.field(chat, "Answer …")
            if (answer) answer.text = "on my way"

            KdeConnectService.status = root.snapshot(76)
            const same = root.devices()
            T.ok(same[0] === phone, "the same snapshot again keeps the row")

            KdeConnectService.status = root.snapshot(77)
            const after = root.devices()
            T.ok(after[0] === phone && after[1] === before[1], "a new battery level keeps every row")
            T.ok(phone.shareOpen, "the share field stays open")
            T.eq(share ? share.text : "", "half a link", "and keeps what was typed")
            T.eq(phone.device.battery ? phone.device.battery.charge : -1, 77, "the row reads the new level")
            T.eq(KdeConnectService.batteryText(phone.device), K.batteryText({ charge: 77, charging: true }), "and shows it")
            const commandsAfter = root.commandRows(phone)
            T.ok(commandsAfter.length === 2 && commandsAfter.every((row, at) => row === commands[at]),
                 "the command rows stay as they were")

            // The list read again (after a dismiss elsewhere): new objects,
            // the rows and the answer stay; the one dismissed goes alone.
            KdeConnectService.notifications = K.parseNotifications(notes.text())
            T.ok(root.noteRows(phone).find(row => row.note.id === "4") === chat, "a new read keeps the rows")
            KdeConnectService.notifications = K.parseNotifications(notes.text()).filter(note => note.id !== "7")
            const left = root.noteRows(phone)
            T.eq(left.map(row => row.note.id), ["4", "2"], "the dismissed one goes")
            T.ok(left[0] === chat && chat.answering, "the answer being typed under another stays open")
            T.eq(answer ? answer.text : "", "on my way", "with its text")

            // A device that goes takes its own row and no other.
            const text = fixture.text()
            const without = K.parseStatus(text).devices.filter(item => item.id !== "22222222222222222222222222222222")
            KdeConnectService.status = Object.assign({}, root.snapshot(77), { devices: without })
            const one = root.devices()
            T.ok(one.length === 1 && one[0] === phone, "the tablet's row goes, the phone's stays")

            KdeConnectService.notificationsId = ""
            KdeConnectService.notifications = []
            T.finish("KdeConnectPageTest")
        }
    }
}
