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
    // Counted up by every open over a fullscreen window: the scrim maps its
    // surface anew for it (ScrimLayer, which says why).
    property int scrimOverFullscreen: 0
    // The panel that is on screen says how deep its scrim is, as it always
    // did; `ShellPanel` pushes it here when it becomes the active one.
    // And whether a click beside it closes it: the scrim's surface is what
    // that click lands on, now that a panel's surface is only its card.
    property bool outsideCloses: true
    // The open panel came out of the notch and stands in for it: the notch
    // on that screen hides until it closes (Notch.qml).
    property bool overNotch: false
    function reportScrim(panelId, color, closesOnOutsideClick, fromNotch) {
        if (active !== panelId) return
        scrimColor = color
        outsideCloses = closesOnOutsideClick !== false
        overNotch = fromNotch === true
    }

    // Panels built on demand (shell.qml's LazyLoaders): a panel is built at the
    // start whether it opens or not (testing.md pitfall 101), and these may
    // never open in a session - the dock's menu, the start menu, the tour
    // after the first start, Settings, the dialogs (Wi-Fi password, pairing,
    // drive unlock, event editor), the power menu, the shortcut sheet, the
    // emoji and wallpaper pickers, the clipboard and notification histories,
    // the display switcher. And the assistant and the share picker, which may
    // never open at all.
    // Each ShellPanel says when it is there.
    //
    // Opening one that is not there asks for it (`demanded`, which its loader
    // reads alongside its feature), and the open waits for the panel to report
    // in (`pending`). Neither `active` nor the scrim moves before: a scrim
    // raised for a panel that is not there dims over nothing and catches the
    // next click (pitfall 110). A loader whose feature is off builds nothing,
    // and then nothing opens.
    readonly property var lazyPanels: ["dockMenu", "startMenu", "welcome", "settings", "eventEditor",
                                       "wifiPassword", "pairing", "driveUnlock", "powerMenu", "shortcutSheet",
                                       "emoji", "wallpaperPicker", "clipboard", "notifications", "assistant", "sharePicker", "trayMenu",
                                       "displaySwitcher"]
    // How many of each panel there are: counted, not flagged, because a
    // loader switched off and on again builds the new one before the old one
    // is gone (it is deleted at the end of the turn), and the old one's
    // goodbye must not take the new one's place with it.
    property var present: ({})
    property var demanded: ({})
    // { panel, args }: the open that waits for its panel, or null.
    property var pending: null
    function isPresent(panelId) { return (present[panelId] || 0) > 0 }
    function reportPresent(panelId, on) {
        const count = Math.max(0, (present[panelId] || 0) + (on ? 1 : -1))
        const next = Object.assign({}, present)
        if (count > 0) next[panelId] = count
        else delete next[panelId]
        present = next
        // Built for an open that waits: it runs once the panel is complete
        // (this is called from inside its creation), unless another open or a
        // close came first.
        if (on && pending && pending.panel === panelId) Qt.callLater(openPending)
        if (count > 0) return
        if (pending && pending.panel === panelId) pending = null
        // Unloaded while it was open (the dock switched off): put the scrim down.
        if (active === panelId) close(panelId)
    }
    function canOpen(panelId) {
        return lazyPanels.indexOf(panelId) < 0 || isPresent(panelId)
    }
    function demand(panelId) {
        if (lazyPanels.indexOf(panelId) < 0 || demanded[panelId] === true) return
        const next = Object.assign({}, demanded)
        next[panelId] = true
        demanded = next
    }
    // The panel's feature went off (shell.qml): its loader lets it go, and it
    // is built again only when it is opened again.
    function release(panelId) {
        if (demanded[panelId] !== true) return
        const next = Object.assign({}, demanded)
        delete next[panelId]
        demanded = next
    }
    function openPending() {
        if (!pending) return
        const waiting = pending
        pending = null
        open(waiting.panel, waiting.args)
    }
    // Not built by the next turn: its loader's feature is off. The open is
    // dropped rather than left to fire whenever the panel is built later.
    function dropUnbuilt() {
        if (pending && !isPresent(pending.panel)) pending = null
    }

    function open(panelId, options) {
        if (!canOpen(panelId)) {
            if (lazyPanels.indexOf(panelId) < 0) return false
            // Set before the demand: a LazyLoader builds its item at once
            // (`active` loads synchronously; while the shell itself is still
            // being built, within the same turn), and the panel reports in
            // from inside that.
            pending = { panel: panelId, args: options || {} }
            demand(panelId)
            if (!isPresent(panelId)) Qt.callLater(dropUnbuilt)
            return true
        }
        pending = null
        // Kept once opened, until its feature goes (release): the tour's
        // loader, for one, would let it go the moment it marks itself
        // completed, in the middle of its closing.
        demand(panelId)
        // `onScreen`: a panel that belongs to a place on one screen (the
        // dock's menu, beside its icon) opens there, wherever the focus is.
        const wanted = options && typeof options.onScreen === "string"
            ? Quickshell.screens.find(item => item.name === options.onScreen) : null
        if (wanted) screenName = wanted.name
        else useFocusedScreen()
        // Switching panels: close the old one before the arguments change, so
        // it keeps its own placement (anchorX …) during its close animation.
        if (active.length && active !== panelId) active = ""
        args = options || {}
        if (HyprlandService.fullscreenOn(screen)) scrimOverFullscreen += 1
        active = panelId
        scrimWanted = true
        return true
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
        // An open still waiting for its panel is closed as well.
        if (pending && (panelId === undefined || pending.panel === panelId)) pending = null
        if (panelId === undefined || active === panelId) {
            const returnTo = panelId !== undefined && args ? args.returnTo : null
            // The panel underneath may have gone meanwhile (the start menu
            // unloaded with the dock while a pairing dialog was over it):
            // then there is nothing to hand back to.
            const back = returnTo && canOpen(returnTo.panel) ? returnTo : null
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
