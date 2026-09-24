import Quickshell
import QtQuick

// When a settings page is on screen. The panel keeps its page across closes
// (the Loader in SettingsPanel stays active, so a second open is a frame and
// not a first layout of several hundred items again), which makes "the page
// was created" and "the page is in view" two different moments. A page that
// starts something - a Wi-Fi scan, Bluetooth discovery, a tracker with its
// refresh timer, a reading that should be fresh on every open - hangs it on
// this: `opened` fires when the panel shows the page, `closed` when it hides
// it or replaces it with another page, always in pairs.
Item {
    id: root
    // Takes no room in the page's column; layouts skip invisible items.
    visible: false
    readonly property bool active: QsWindow.window !== null && QsWindow.window.visible
    signal opened()
    signal closed()
    property bool open: false

    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (open) { open = false; closed() }

    function sync() {
        if (active === open) return
        open = active
        if (open) opened()
        else closed()
    }
}
