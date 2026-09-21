import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/origin/OriginLogic.js" as Origin

// On-screen display for volume, microphone mute, screen brightness and the
// keyboard backlight, and for a short message such as the new desktop mode. It
// reacts to value changes from any source (hardware keys, other apps) and
// stays hidden while the control center or the volume popup, where the same
// sliders live, is open.
//
// It comes out of the notch when there is one, because that is what a notch is
// for, and sits at the bottom of the screen when there is not. A notch hidden
// behind a fullscreen window reports no rectangle, so an OSD raised over a
// film still appears where it always did rather than over the film's top edge.
PanelWindow {
    id: window
    property string kind: ""           // volume | mic | brightness | kbdBacklight | message
    readonly property bool isMessage: kind === "message"
    property string message: ""
    property string messageIcon: ""
    property bool armed: false
    readonly property bool suppressed: ["controlCenter", "volumePopup"].indexOf(PanelService.active) >= 0
    readonly property real level: kind === "brightness" ? BrightnessService.value
        : kind === "kbdBacklight" ? KbdBacklightService.value
        : kind === "mic" ? AudioService.micVolume : AudioService.volume
    readonly property bool mutedState: kind === "mic" ? AudioService.micMuted
        : kind === "kbdBacklight" ? KbdBacklightService.current === 0
        : kind === "volume" && AudioService.muted
    readonly property string icon: isMessage ? messageIcon
        : kind === "brightness" ? (level > 0.66 ? "󰃠" : level > 0.33 ? "󰃟" : "󰃞")
        : kind === "kbdBacklight" ? "󰌌"
        : kind === "mic" ? (AudioService.micMuted ? "󰍭" : "󰍬")
        : AudioService.volumeIcon(AudioService.volume, AudioService.muted)
    // A stepped light shows its steps. `maximum` decides how many, so three is
    // this machine's answer and not the shell's; 0 means a plain track, which
    // is every other kind.
    readonly property int segments: kind === "kbdBacklight" ? KbdBacklightService.segments : 0
    // The keyboard light says which step it is on. "0% / 50% / 100%" on a
    // track that looks like a hundred promises a fineness it does not have.
    readonly property string valueText: kind === "kbdBacklight" ? KbdBacklightService.label
        : mutedState ? "Muted" : Math.round(level * 100) + "%"
    property bool showing: false

    function show(nextKind) {
        if (!armed || suppressed || !SettingsService.value("desktop.osd")) return
        kind = nextKind
        showing = true
        hideTimer.restart()
    }

    // A message is the answer to something the user just pressed, so it shows
    // even while a panel is open and without waiting for the arming timer.
    function showMessage(text, glyph) {
        if (!SettingsService.value("desktop.osd")) return
        message = text
        messageIcon = glyph
        kind = "message"
        showing = true
        hideTimer.restart()
    }

    readonly property var targetScreen: PanelService.focusedScreen()
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    // What it comes out of: the notch, or - in bar mode - the volume widget it
    // belongs to, or the middle of the bar when that widget is not on it.
    readonly property string barEdge: LayoutService.barEdge(screenName)
    readonly property bool barAtBottom: barEdge === "bottom"
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    readonly property var notch: LayoutService.notchRect(screenName)
        || LayoutService.barItemRect(screenName, "volume")
        || Origin.barSpot(LayoutService.barBottom(screenName),
                          targetScreen ? targetScreen.width : 0, "centre", Metrics.screenMargin,
                          barEdge, targetScreen ? targetScreen.height : 0)
    readonly property real boxWidth: Metrics.osdWidth
    readonly property real boxHeight: Metrics.pillHeight + Metrics.spaceMd * 2
    // Out of the notch when there is one, at the bottom of the screen when
    // there is not - and nothing at all until the screen is known, because a
    // place computed from a width of zero is the left-hand margin, which is
    // what put the volume bar in the top left corner.
    // Out of the thing it belongs to, downwards from a top edge and upwards
    // from a bottom one - a box that came out downwards from a bar at the
    // bottom would leave the screen.
    // And sideways out of a bar that runs down the screen: coming out
    // *downwards* from a spot halfway down the left edge would put it over the
    // middle of the screen with the bar beside it, which is neither where it
    // came from nor out of the way.
    readonly property var fromNotch: barVertical
        ? Origin.beside(notch, boxWidth, boxHeight,
                        targetScreen ? targetScreen.width : 0,
                        targetScreen ? targetScreen.height : 0,
                        Metrics.screenMargin, Metrics.spaceSm, barEdge === "right")
        : barAtBottom
        ? Origin.above(notch, boxWidth, boxHeight,
                       targetScreen ? targetScreen.width : 0,
                       Metrics.screenMargin, Metrics.spaceSm)
        : Origin.under(notch, boxWidth,
                       targetScreen ? targetScreen.width : 0,
                       Metrics.screenMargin, Metrics.spaceSm)
    readonly property var place: fromNotch !== null ? fromNotch
        : Origin.atBottom(boxWidth, boxHeight,
                          targetScreen ? targetScreen.width : 0,
                          targetScreen ? targetScreen.height : 0,
                          Metrics.osdBottomMargin, Metrics.screenMargin)

    screen: targetScreen
    // Only once there is somewhere to be: a layer surface that is already
    // mapped does not reliably take a new anchor, so these two never change
    // for the life of the surface and only the margins move.
    visible: place !== null && (showing || card.opacity > 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true }
    margins {
        top: window.place ? window.place.y : 0
        left: window.place ? window.place.x : 0
    }
    implicitWidth: boxWidth
    implicitHeight: boxHeight
    WlrLayershell.namespace: "buchhwin-osd"
    WlrLayershell.layer: WlrLayer.Overlay

    Timer { id: hideTimer; interval: Metrics.osdTimeout; onTriggered: window.showing = false }
    // Ignore the initial values reported while services start.
    Timer { interval: 2500; running: true; onTriggered: window.armed = true }

    Connections {
        target: AudioService
        function onVolumeChanged() { window.show("volume") }
        function onMutedChanged() { window.show("volume") }
        function onMicMutedChanged() { window.show("mic") }
    }
    Connections {
        target: BrightnessService
        function onValueChanged() { if (Date.now() >= BrightnessService.quietUntil) window.show("brightness") }
    }
    Connections {
        target: KbdBacklightService
        function onCurrentChanged() { window.show("kbdBacklight") }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: height / 2
        color: Colors.pillFor("osd")
        border.width: Metrics.borderWidth
        border.color: Colors.pillBorder
        opacity: window.showing ? 1 : 0
        scale: Animations.motionEnabled ? (window.showing ? 1 : Effects.hoverScaleFrom) : 1
        Behavior on opacity { NumberAnimation { duration: window.showing ? Animations.popupOpen : Animations.popupClose; easing.type: window.showing ? Animations.easingEnter : Animations.easingExit } }
        Behavior on scale { NumberAnimation { duration: Animations.popupOpen; easing.type: Animations.easingEnter } }

        // Drawn where it rests and carried back onto the notch while it
        // appears, so it travels out of it. `opacity` is the progress, so
        // there is one animation rather than two that have to agree.
        readonly property var homeward: window.fromNotch && Animations.motionEnabled
            ? Origin.offsetTo(window.notch, { x: window.fromNotch.x, y: window.fromNotch.y,
                                              width: window.width, height: window.height })
            : null
        transform: Translate {
            x: card.homeward ? card.homeward.x * (1 - card.opacity) : 0
            y: card.homeward ? card.homeward.y * (1 - card.opacity) : 0
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.spaceLg
            anchors.rightMargin: Metrics.spaceLg
            spacing: Metrics.spaceMd

            ShellIcon { glyph: window.icon; size: Metrics.iconMd; color: window.mutedState ? Colors.mutedText : Colors.text }

            ShellText {
                Layout.fillWidth: true
                visible: window.isMessage
                text: window.message
                role: "small"
            }

            Item {
                id: track
                visible: !window.isMessage
                Layout.fillWidth: true
                implicitHeight: Metrics.progressTrack

                // A continuous track for a value that is continuous.
                Rectangle {
                    anchors.fill: parent
                    visible: window.segments === 0
                    radius: height / 2
                    color: Colors.track
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, window.level))
                        height: parent.height
                        radius: height / 2
                        color: window.mutedState ? Colors.mutedText : Colors.accent
                        Behavior on width { NumberAnimation { duration: Animations.move(Animations.control); easing.type: Animations.easing } }
                    }
                }

                // One box per step for a light that has steps. The width is
                // read from the row rather than constrained into it: reading
                // feeds nothing back.
                Row {
                    anchors.fill: parent
                    visible: window.segments > 0
                    spacing: Metrics.spaceXs
                    Repeater {
                        model: window.segments
                        Rectangle {
                            required property int index
                            width: window.segments > 0
                                ? (track.width - (window.segments - 1) * Metrics.spaceXs) / window.segments : 0
                            height: track.height
                            radius: height / 2
                            color: index < KbdBacklightService.current ? Colors.accent : Colors.track
                            Behavior on color { ColorAnimation { duration: Animations.hover } }
                        }
                    }
                }
            }

            ShellText {
                visible: !window.isMessage
                Layout.minimumWidth: Metrics.iconXl
                horizontalAlignment: Text.AlignRight
                text: window.valueText
                role: "small"
                font.features: { "tnum": 1 }
            }
        }
    }
}
