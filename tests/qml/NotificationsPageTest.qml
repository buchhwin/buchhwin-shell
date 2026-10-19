//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../shell/settings/pages"

// Settings > Notifications with the rows for sharing the screen, fullscreen
// exceptions and the other screen, the summary, sounds and the history
// kept across restarts, over the sandboxed settings: the page loads, says
// what the defaults are, and a row writes its setting. Under the lock
// screen's shell id, so the page's NotificationService runs no server and
// watches no share (pitfall 82).
ShellRoot {
    id: root
    property int waits: 0

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        visible: true
        Loader { id: loader; width: 860; active: false; sourceComponent: NotificationsPage {} }
    }

    function walk(item, pred, out) {
        if (!item) return out
        if (pred(item)) out.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) walk(kids[i], pred, out)
        return out
    }
    function texts() {
        return walk(loader.item, item => typeof item.text === "string" && item.text.length > 0
                    && item.toString().indexOf("ShellText") >= 0, []).map(item => item.text)
    }

    Timer {
        id: wait
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            if (!SettingsService.loaded && root.waits < 100) return
            stop()
            loader.active = true
            check.start()
        }
    }

    Timer {
        id: check
        interval: 200
        onTriggered: {
            T.ok(loader.item !== null, "the page loads")
            const words = texts()
            for (const label of ["Mute automatically while sharing the screen", "Not muted in fullscreen",
                                 "Pop up on another screen instead", "Summary when Do Not Disturb ends", "Play a sound",
                                 "Keep notifications across restarts"])
                T.ok(words.indexOf(label) >= 0, "the page has \"" + label + "\"")
            T.eq([SettingsService.value("notifications.suppressSharing"), SettingsService.value("notifications.fullscreenExceptions"),
                  SettingsService.value("notifications.fullscreenElsewhere"), SettingsService.value("notifications.missedSummary"),
                  SettingsService.value("notifications.sounds"), SettingsService.value("notifications.keepHistory")],
                 [true, "Wfica", true, false, false, false], "the fixes on, the notice, sounds and the kept history off")
            const fields = walk(loader.item, item => item.storedText !== undefined && item.commit !== undefined, [])
            T.eq(fields.length, 1, "one text field: the fullscreen exceptions")
            fields[0].commit(" Wfica ,  mpv")
            T.eq(SettingsService.value("notifications.fullscreenExceptions"), "Wfica, mpv", "written tidied")
            T.eq(SettingsService.set("notifications.keepHistory", true), true, "the kept history is a setting")
            T.eq(SettingsService.set("notifications.sounds", true), true, "and the sounds")
            T.finish("NotificationsPageTest")
        }
    }
}
