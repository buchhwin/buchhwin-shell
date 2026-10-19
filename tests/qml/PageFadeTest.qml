import Quickshell
import QtQuick
import qs.services
import qs.shell.components
import "Harness.js" as T

// A page that changes inside an open panel fades in, starting from nothing
// rather than drawn at full strength first; not while the panel opens, and
// not in Reduced or Off.
ShellRoot {
    id: root
    property string page: "overview"
    property bool open: false

    Item {
        id: holder
        PageFade { id: fade; target: holder; key: root.page; live: root.open }
    }

    Timer {
        id: later
        interval: 400
        onTriggered: {
            T.eq(holder.opacity, 1, "and comes up to full")
            SettingsService.set("appearance.animationMode", "reduced")
            root.page = "network"
            T.eq([fade.running, holder.opacity], [false, 1], "Reduced swaps the page as it is")
            SettingsService.set("appearance.animationMode", "full")
            T.finish("PageFadeTest")
        }
    }
    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        property int waits: 0
        onTriggered: {
            if (!SettingsService.loaded && ++waits < 250) return
            stop()
            root.page = "network"
            T.eq([fade.running, holder.opacity], [false, 1], "a page set while the panel opens comes in with the panel")
            root.open = true
            root.page = "bluetooth"
            T.ok(fade.running, "a page changed in an open panel fades in")
            T.ok(holder.opacity < 0.5, "from nothing, not from where it was: " + holder.opacity)
            later.start()
        }
    }
}
