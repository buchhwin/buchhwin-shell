//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T

// NotificationService's own wiring around the pure rules NotificationPopupTest
// covers: the popup the notch takes, a replaced notification queued again,
// and a mode's Do Not Disturb that a reboot ended taken back by the mode in
// use. Under the lock screen's shell id, so the service runs no notification
// server (LockLogic.lockProcess, pitfall 82) and its history stays empty;
// the popups here are stand-ins put in the queue by hand.
ShellRoot {
    id: root
    property int tries: 0

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.tries += 1
            if (!NotificationService.stateLoaded && root.tries < 200) return
            stop()
            T.ok(NotificationService.stateLoaded, "the state is read in the sandbox")
            T.eq(NotificationService.server, null, "and no server runs")
            root.check()
        }
    }

    function check() {
        const anna = { id: 1, appName: "Signal", summary: "Anna" }
        const bob = { id: 2, appName: "Signal", summary: "Bob" }

        // The notch takes the newest of the queue.
        NotificationService.popups = [anna, bob]
        T.ok(NotificationService.notchPopup === bob, "the notch shows the newest popup")
        NotificationService.hidePopup(bob)
        T.ok(NotificationService.notchPopup === anna, "and the one before it once that has gone")
        NotificationService.hidePopup(anna)
        T.eq(NotificationService.notchPopup, null, "and nothing with no popup")

        // Replaced in place by its sender: back in the queue, once.
        NotificationService.setDnd("off")
        NotificationService.replaced(anna)
        NotificationService.replaced(anna)
        T.eq(NotificationService.popups.map(item => item.summary), ["Anna"],
             "a replaced notification whose popup had gone pops up again, once for its summary and body both")
        T.ok(NotificationService.arrivalOf(anna) > 0, "and came now")
        NotificationService.hidePopup(anna)
        NotificationService.setDnd("manual")
        NotificationService.replaced(anna)
        T.eq(NotificationService.popups, [], "not while the user's Do Not Disturb runs")
        NotificationService.setDnd("off")

        // Clear all with nothing to clear leaves nothing behind.
        NotificationService.popups = [anna]
        NotificationService.clearAll()
        T.eq([NotificationService.popups, NotificationService.clearing, NotificationService.unread], [[], false, 0],
             "Clear all empties the queue and ends clearing")

        // A reboot ended gaming's Do Not Disturb (dndEndedBy, from
        // Logic.dndAtBoot); the mode in use takes it back only when it is
        // gaming, and only once.
        NotificationService.dndEndedBy = "gaming"
        T.eq([NotificationService.resumeModeDnd("work"), NotificationService.dndActive], [false, false],
             "another mode in use leaves it off")
        T.eq(NotificationService.resumeModeDnd("gaming"), false, "and the question has been answered")
        NotificationService.dndEndedBy = "gaming"
        T.eq(NotificationService.resumeModeDnd("gaming"), true, "gaming in use takes it back")
        T.eq([NotificationService.dndMode, NotificationService.dndBy, NotificationService.dndLabel],
             ["manual", "gaming", "Until you leave Gaming"], "as gaming's own")
        NotificationService.setDnd("manual")
        NotificationService.dndEndedBy = "gaming"
        T.eq([NotificationService.resumeModeDnd("gaming"), NotificationService.dndBy], [false, ""],
             "one the user has turned on stays the user's")
        NotificationService.dndEndedBy = "gaming"
        NotificationService.setDnd("off")
        T.eq(NotificationService.dndEndedBy, "", "any change of Do Not Disturb answers the question")
        T.finish("NotificationWiringTest")
    }
}
