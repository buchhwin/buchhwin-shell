pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.theme

// One shell panel is open at a time; it opens on the focused monitor.
Singleton {
    id: root
    property string active: ""
    property var args: ({})

    // How many frames each panel's last open animation was drawn in. Counts
    // only, for `editor get`: a 220 ms open at 60 Hz is about thirteen, and a
    // number far below that is the difference between an animation that looks
    // wrong and one that is barely drawn at all.
    property var openFrames: ({})
    function reportOpenFrames(panelId, frames, worstMs) {
        const next = Object.assign({}, openFrames)
        next[panelId] = { frames: frames, worstMs: worstMs }
        openFrames = next
    }
    // The screen the panels open on, held *by name* and resolved against the
    // screens there are now. Holding the screen object itself kept a dangling
    // one after that monitor was unplugged, and every panel window stayed
    // bound to it; by name, an unplugged monitor falls back to the first
    // screen there is the moment the list changes. Read-only on purpose: the
    // layout editor used to assign the object directly, and now asks for the
    // focused screen like `open` does.
    property string screenName: ""
    readonly property var screen: Quickshell.screens.find(item => item.name === screenName)
        || (Quickshell.screens.length ? Quickshell.screens[0] : null)

    function useFocusedScreen() {
        const focused = focusedScreen()
        screenName = focused ? focused.name : ""
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        return Quickshell.screens.find(item => item.name === name)
            || (Quickshell.screens.length ? Quickshell.screens[0] : null)
    }

    // ---- the scrim --------------------------------------------------------
    // One scrim for all of them, on its own surface (shell/components/
    // ScrimLayer.qml, which carries the measurements and the reason). These
    // two are what it reads, and they are set here rather than derived from
    // `active`, because a handover clears `active` for an instant on its way
    // to the next panel and the scrim must not see that.
    property bool scrimWanted: false
    property color scrimColor: Colors.scrim
    // The panel that is on screen says how deep its scrim is, as it always
    // did; `ShellPanel` pushes it here when it becomes the active one.
    function reportScrim(panelId, color) {
        if (active === panelId) scrimColor = color
    }

    function open(panelId, options) {
        useFocusedScreen()
        // Switching panels: close the old one before the arguments change, so
        // it keeps its own placement (anchorX …) during its close animation.
        if (active.length && active !== panelId) active = ""
        args = options || {}
        active = panelId
        scrimWanted = true
    }

    // Dialogs (Wi-Fi password, pairing, event editor) opened over a panel
    // return to it when they close. The panel reopens with its previous
    // arguments (e.g. its place below a pill) plus `returnArgs` (e.g. the
    // settings page or the selected day).
    function openOver(panelId, options, returnArgs) {
        let back = null
        if (active === panelId) {
            back = args.returnTo || null
        } else if (active.length) {
            const previous = Object.assign({}, args, returnArgs || {})
            delete previous.returnTo
            back = { panel: active, args: previous }
        }
        open(panelId, Object.assign({}, options || {}, back ? { returnTo: back } : {}))
    }

    function close(panelId) {
        if (panelId === undefined || active === panelId) {
            const back = panelId !== undefined && args ? args.returnTo : null
            active = ""
            args = {}
            // Only a close with nothing behind it takes the scrim down: a
            // close that reopens the panel underneath is a handover, and the
            // scrim stays exactly where it is.
            scrimWanted = !!back
            if (back) open(back.panel, back.args)
        }
    }

    function toggle(panelId, options) {
        if (active === panelId) close(panelId)
        else open(panelId, options)
    }

    function isOpen(panelId) {
        return active === panelId
    }
}
