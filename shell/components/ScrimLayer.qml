import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.theme
import qs.services

// The one scrim behind every panel.
//
// It used to belong to each panel: every `ShellPanel` drew its own
// full-screen rectangle and faded it with its own open and close. That works
// while one panel is on screen at a time, and **two are** whenever one hands
// over to another - the event editor over the dashboard, a Wi-Fi dialog over
// the control center. Then there are two scrims, fading on two different
// clocks (a close is 240 ms, an open 340) and separated by the round trip a
// new layer surface needs before it can draw at all. What reaches the screen
// is a flicker.
//
// Measured on a nested session with every duration stretched four times,
// sampling a corner of the screen well away from any card, 101 of 255 being
// one scrim and 129 being none:
//
//   each panel fades its own              101 → 107   the two fades do not add up
//   both hold theirs at full              101 →  79   two scrims, visibly darker
//   the one going out drops it at once    101 → 126   no scrim at all for a frame
//   the one going out holds it until gone 101 →  81   still one frame of two
//
// `layerrule = animation none` on the two namespaces changed none of them, so
// the compositor's own fade is not what it is. There is no arrangement of two
// scrims that is one scrim.
//
// So there is one, on its own surface, below every panel. It fades in when the
// first panel opens and out when the last one closes, and a handover does not
// touch it at all - which is the whole point.
PanelWindow {
    id: scrim

    // The panel that is on screen decides how deep it is: a dialog and the
    // session menu ask for a stronger one than a popup. On a handover the
    // colour changes under a scrim that is already at full strength, which is
    // a step in one value rather than a gap in the picture.
    property color tint: PanelService.scrimColor

    // **Not for Alt+Tab.** The switcher opens through PanelService like any
    // panel, so this used to fade the whole screen in the moment Alt+Tab was
    // pressed - while the switcher itself waits 110 ms (switcherShowDelay)
    // precisely so that a quick Alt+Tab does not flash, and nearly every
    // Alt+Tab is a quick one. Held, its own scrim lay over this one: 0.39
    // black instead of 0.22, in whatever tint the last panel had reported.
    // The switcher draws its own, after its delay, on its own full-screen
    // surface, which also takes the click beside its strip; so this one
    // neither dims nor catches for it.
    readonly property bool forSwitcher: PanelService.active === "switcher"

    screen: PanelService.screen
    // Mapped for as long as the dimming is on, not only while it is drawn.
    // See `level` below for what that buys and what it costs. With the
    // dimming off it is still mapped while a panel is open, undrawn: it is
    // what a click beside the panel lands on.
    visible: dimming || catching
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "buchhwin-scrim"
    // **Top, not Overlay.** Every panel is an Overlay surface, and the order
    // inside one layer is not something a client can decide - declaring this
    // first did not put it underneath, it put it over the power menu's own
    // card. A layer below them is the only ordering there is.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // **The click beside a panel lands here** (2026-10-13). A panel's surface
    // used to be the whole screen and caught that click itself; now it is the
    // size of its card (ShellPanel, `compactSurface`), so this surface - full
    // screen, in the Top layer below every panel (they are Overlay) and above
    // every window - takes it while a panel is open, and nothing at all
    // otherwise. Not above the bar, the notch or the dock: they are Top
    // surfaces too, and inside one layer the compositor stacks by creation.
    // They are made once the layout or the settings have loaded, after this
    // one, so they sit above it (`hyprctl layers`: scrim, notch, dock from the
    // bottom up) - it never dims them, and a click on them goes to them; the
    // panel's focus grab closes the panel then. Leaving the dock undimmed is
    // decided; dimming the bar and the notch would mean making this surface
    // again after theirs, a remap on every change.
    readonly property bool catching: PanelService.active.length > 0 && PanelService.outsideCloses && !forSwitcher
    mask: catching ? null : noInput
    Region { id: noInput }
    MouseArea {
        anchors.fill: parent
        enabled: scrim.catching
        acceptedButtons: Qt.AllButtons
        onClicked: PanelService.close()
    }

    // How much of it is there. A `PanelWindow` is a window, not an item, so it
    // has no opacity of its own: the rectangle carries it and this carries the
    // curve.
    //
    // **`visible` no longer follows it.** It did, on the reasoning that a
    // mapped surface at zero is a full-screen quad the compositor blends every
    // frame for nothing - which is true, and cheaper than the alternative it
    // was hiding: a layer surface needs a compositor round trip before it may
    // draw, and `visible: level > 0` paid that round trip on **every** panel
    // open. `hyprctl layers` with nothing open showed no `buchhwin-scrim` at
    // all, which is how it was found.
    //
    // Measured nested, five opens per panel per arm, the median worst frame
    // gap in ms, the session restarted for each arm:
    //
    //                          dashboard  controlCenter  launcher  overview
    //   dimming off                   18             33        24        20
    //   dimming on, remapped          19             50        34        17
    //   dimming on, mapped (this)     17             28        20        17
    //
    // So the remap was worth about one refresh on two panels of four and
    // nothing on the other two - a real cost, and not the 31-49 ms stall it
    // had been blamed for before anyone compared the two arms. That stall is
    // elsewhere. With the surface mapped, dimming costs nothing measurable at
    // all: it is now at least as fast as having no scrim on every panel, and
    // the dashboard came back 17 in all five rounds instead of scattering
    // between 17 and 40.
    //
    // The quad is free in return: at opacity 0 it is under `ignore_alpha 0.35`
    // and `layerrule = blur off, match:namespace ^(buchhwin-scrim)$` takes it
    // out of the catch-all as well.
    //
    // **One case still pays the round trip**: `screen` follows the panel, so
    // opening on a monitor the last panel did not use moves the surface, which
    // is a remap. A scrim per screen would answer that and costs a permanently
    // mapped full-screen quad per monitor - three at a three-screen desk -
    // and nobody has measured whether that is cheaper than one remap.
    //
    // Settings > Appearance can turn the dimming off altogether; then nothing
    // here is ever drawn and the surface is never mapped at all.
    readonly property bool dimming: SettingsService.value("appearance.panelScrim")
    property real level: (PanelService.scrimWanted && dimming && !forSwitcher) ? 1 : 0
    Behavior on level {
        enabled: Animations.enabled
        NumberAnimation {
            duration: PanelService.scrimWanted ? Animations.popupOpen : Animations.popupClose
            easing.type: PanelService.scrimWanted ? Animations.easingEnter : Animations.easingExit
        }
    }

    Rectangle {
        anchors.fill: parent
        color: scrim.tint
        opacity: scrim.level
    }
}
