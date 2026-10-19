//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// NotificationService's Do Not Disturb and whose it is, against the runner's
// sandboxed state directory. Under the lock screen's shell id, where the
// service runs no notification server (LockLogic.lockProcess): a test that
// made one queued for org.freedesktop.Notifications on the session's bus and
// would have taken the user's notifications had the shell restarted meanwhile
// (pitfall 82). The pure halves are NotificationPopupTest's (dndOwner) and
// LayoutUndoTest's (dndOnModeChange); this is the wiring between them: the
// owner written to state.json beside the mode, read back by a restart of the
// shell, and gone with a timed one that ran out.
ShellRoot {
    id: root
    property int tries: 0

    FileView {
        id: written
        path: Paths.stateDir + "/state.json"
        blockLoading: true
        printErrors: false
    }

    function stored() {
        written.reload()
        try { return JSON.parse(written.text()).dnd || null } catch (error) { return null }
    }

    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.tries += 1
            if (!NotificationService.stateLoaded && root.tries < 200) return
            stop()
            T.ok(NotificationService.stateLoaded, "the state is read in the sandbox (" + Paths.stateDir + ")")
            T.eq([NotificationService.serverWanted, NotificationService.server], [false, null], "and no server runs")
            NotificationService.setDnd("manual", "gaming")
            T.eq([NotificationService.dndActive, NotificationService.dndBy, NotificationService.dndLabel],
                 [true, "gaming", "Until you leave Gaming"], "a mode's Do Not Disturb names the mode")
            root.tries = 0
            ownerWritten.start()
        }
    }

    Timer {
        id: ownerWritten
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            const dnd = root.stored()
            if ((!dnd || dnd.by !== "gaming") && root.tries < 60) return
            stop()
            T.eq(dnd ? [dnd.mode, dnd.by] : null, ["manual", "gaming"], "state.json keeps the mode and whose it is")
            T.eq(dnd ? dnd.boot : "", NotificationService.bootId, "with the boot it belongs to")
            // A shell restart reads the file again: same boot, same owner.
            NotificationService.dndBy = ""
            NotificationService.dndMode = "off"
            NotificationService.loadState()
            T.eq([NotificationService.dndMode, NotificationService.dndBy], ["manual", "gaming"],
                 "read back in the same boot, it is the mode's again")
            // Any change made anywhere else is the user's.
            NotificationService.setDnd("manual")
            T.eq(NotificationService.dndBy, "", "set again without an owner, it is the user's")
            // A timed one keeps its owner while it runs and loses it with the hour.
            NotificationService.setDnd("1h", "gaming")
            T.eq(NotificationService.dndBy, "gaming", "a timed one can be a mode's too")
            NotificationService.dndUntil = Date.now() - 1000
            NotificationService.checkDnd()
            T.eq([NotificationService.dndMode, NotificationService.dndBy, NotificationService.dndActive], ["off", "", false],
                 "and ends with its hour, owner and all")
            root.tries = 0
            offWritten.start()
        }
    }

    Timer {
        id: offWritten
        interval: 50
        repeat: true
        onTriggered: {
            root.tries += 1
            const dnd = root.stored()
            if ((!dnd || dnd.mode !== "off") && root.tries < 60) return
            stop()
            T.eq(dnd ? [dnd.mode, dnd.by] : null, ["off", ""], "and the file says so")
            T.finish("NotificationServiceTest")
        }
    }
}
