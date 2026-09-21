pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

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
    property var screen: Quickshell.screens.length ? Quickshell.screens[0] : null

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        return Quickshell.screens.find(item => item.name === name)
            || (Quickshell.screens.length ? Quickshell.screens[0] : null)
    }

    function open(panelId, options) {
        screen = focusedScreen()
        // Switching panels: close the old one before the arguments change, so
        // it keeps its own placement (anchorX …) during its close animation.
        if (active.length && active !== panelId) active = ""
        args = options || {}
        active = panelId
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
