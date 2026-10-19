import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/origin/OriginLogic.js" as Origin
import "../components/PanelPlaceLogic.js" as Place
import "OsdLogic.js" as Logic
import "../../services/audio/MicLogic.js" as MicLogic
import "../../services/lock/LockLogic.js" as LockLogic

// On-screen display for volume, microphone mute, screen brightness and the
// keyboard backlight, and for a short message such as the new desktop mode. It
// reacts to value changes from any source (hardware keys, other apps) and
// stays hidden for a kind while a panel that shows the same control is open:
// the volume popup, or the control center with that tile (OsdLogic.suppressed).
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
    readonly property real level: kind === "brightness" ? BrightnessService.osdLevel
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
        if (!armed || !SettingsService.value("desktop.osd")) return
        if (Logic.suppressed(nextKind, PanelService.active, LayoutService.quickTypes)) return
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
    // A message is as wide as its words, up to Metrics.osdMessageMaxWidth: at
    // the levels' width the one that says what to do was cut off ("Leave
    // full screen in the Citrix toolba…"). Read from the text's natural width,
    // which does not wrap and so does not follow the box (no loop).
    readonly property real boxWidth: isMessage
        ? Math.min(Metrics.osdMessageMaxWidth, Math.max(Metrics.osdWidth, messageText.implicitWidth + Metrics.iconMd
                                                                              + Metrics.spaceMd + Metrics.spaceLg * 2))
        : Metrics.osdWidth
    // The box out of a bar's pill ends at the pill's outer edge rather than
    // at the screen margin further in: never further in than what it comes
    // out of, never less than 0 (as ShellPanel's PanelPlaceLogic.outerClear).
    // What it comes out of in bar mode is an item inside a pill, so the end
    // of a floating bar or of the pills counts too (PillBar's inset); an
    // attached bar runs to the screen's sides.
    readonly property bool fromFloatingBar: !LayoutService.notchRect(screenName)
        && LayoutService.barItemRect(screenName, "volume") !== null
        && !(LayoutService.bar.style === "bar" && LayoutService.bar.position === "attached")
    readonly property real sideMargin: Logic.sideMargin(notch, targetScreen ? targetScreen.width : 0, Metrics.screenMargin,
        fromFloatingBar ? Math.max(Metrics.barMargin, SettingsService.gapsOut) : -1)
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
                       sideMargin, Metrics.spaceSm)
        : Origin.under(notch, boxWidth,
                       targetScreen ? targetScreen.width : 0,
                       sideMargin, Metrics.spaceSm)
    // The notch can be the display itself, and then this surface stays away
    // rather than drawing the same thing twice. There is no second timer: the
    // notch mirrors `showing`, which this one already owns.
    readonly property bool inNotch: showing && NotchService.takesDisplay("osd", screenName)
    onInNotchChanged: publish()
    onKindChanged: publish()
    onLevelChanged: publish()
    onMutedStateChanged: publish()
    onShowingChanged: publish()
    // Whether the notch holds this OSD now, so the slot is cleared once when
    // it leaves and left alone while it is not there (OsdLogic.publishes).
    property bool published: false
    function publish() {
        if (!Logic.publishes(inNotch, published)) return
        NotchService.setDisplay("osd", screenName, inNotch ? {
            kind: "osd", icon: icon,
            level: isMessage ? undefined : level,
            segments: segments,
            muted: mutedState,
            value: isMessage ? message : valueText
        } : null)
        published = inNotch
    }

    // A dock shown at the bottom of this screen: the box stands above it
    // rather than on it. Read only while the dock is on, so an OSD never
    // starts the dock's service.
    readonly property real dockLift: SettingsService.value("dock.enabled") === true ? DockService.liftFor(screenName) : 0
    readonly property var bottomPlace: Origin.atBottom(boxWidth, boxHeight,
                          targetScreen ? targetScreen.width : 0,
                          targetScreen ? targetScreen.height : 0,
                          Math.max(Metrics.osdBottomMargin, dockLift + Metrics.spaceMd), Metrics.screenMargin)
    // And beside a side bar, clear of a dock beyond it (the bottom has its
    // lift above): the box came out over the dock.
    readonly property var sideDock: SettingsService.value("dock.enabled") === true && DockService.position !== "bottom"
        ? Object.assign({ position: DockService.position, shown: DockService.shownOn[screenName] === true,
             reach: DockService.reachOn[screenName] || 0 },
           Place.dockSpan(DockService.bodies[screenName], DockService.position,
                          targetScreen ? targetScreen.x : 0, targetScreen ? targetScreen.y : 0))
        : null
    readonly property var place: fromNotch !== null
        ? (barAtBottom && dockLift > 0 ? { x: fromNotch.x, y: Math.max(0, fromNotch.y - dockLift) }
            : Place.clearOfDock(fromNotch, boxWidth, boxHeight, targetScreen ? targetScreen.width : 0,
                                targetScreen ? targetScreen.height : 0, sideDock, barEdge,
                                LayoutService.barBottom(screenName), Metrics.spaceSm))
        : bottomPlace

    screen: targetScreen
    // Only once there is somewhere to be: a layer surface that is already
    // mapped does not reliably take a new anchor, so these two never change
    // for the life of the surface and only the margins move.
    visible: !inNotch && place !== null && (showing || card.opacity > 0)
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

    // The microphone stays on screen while push to talk holds it on: its
    // display is the one sign that the key is doing what it should.
    Timer {
        id: hideTimer
        interval: Metrics.osdTimeout
        onTriggered: {
            if (window.kind === "mic" && AudioService.talking) restart()
            else window.showing = false
        }
    }
    // Ignore the initial values reported while services start.
    Timer { interval: Animations.startupQuiet; running: true; onTriggered: window.armed = true }
    // A new output - headphones connecting over Bluetooth, a dock - comes
    // with its own volume, and the jump to it is not something the user did.
    // Two seconds of quiet after the default sink changes, so the OSD only
    // answers a key. The sink is compared rather than its own signal waited
    // for: which of "sink" and "volume" is notified first is not promised.
    // The same for the input: a headset unplugged leaves no source or the
    // built-in microphone, whose mute state differs (no source reads as
    // muted), and that raised "Microphone muted" with no key pressed.
    Timer { id: sinkSettling; interval: Animations.sinkSettle }
    Timer { id: sourceSettling; interval: Animations.sinkSettle }
    property var lastSink: null
    property bool sinkSeen: false
    property var lastSource: null
    property bool sourceSeen: false
    function volumeMoved() {
        const sink = AudioService.sink
        if (sink !== lastSink) {
            const changed = Logic.deviceChanged(lastSink, sink, sinkSeen)
            lastSink = sink
            sinkSeen = sinkSeen || sink !== null
            if (changed && toastOutput && armed && sink !== null) outputToastTimer.restart()
            if (changed) { sinkSettling.restart(); return }
        }
        if (!sinkSettling.running) show("volume")
    }
    function micMoved() {
        const source = AudioService.source
        if (source !== lastSource) {
            const changed = Logic.deviceChanged(lastSource, source, sourceSeen)
            lastSource = source
            sourceSeen = sourceSeen || source !== null
            if (changed) { sourceSettling.restart(); return }
        }
        // The microphone key's own message ("All microphones muted") is
        // what the press said; the default input's mute arriving a moment
        // later must not replace it with the plain display.
        if (Date.now() < micMessageUntil) return
        if (!sourceSettling.running) show("mic")
    }
    property real micMessageUntil: 0
    function microphonesSet(muted, changed, total) {
        const text = MicLogic.message(muted, changed, total)
        micMessageUntil = MicLogic.messageHold(text, Date.now(), Metrics.osdTimeout)
        if (text.length) showMessage(text, muted ? "󰍭" : "󰍬")
    }

    // ---- short messages for state changes (Settings > Desktop) ---------------
    // Each one off unless turned on (OsdLogic.outputToast and the rest): the
    // output that plays now, the charger, a VPN, Caps Lock. Nothing is
    // watched for one that is off, and none speaks in the first moments of a
    // session, while the services report where they start.
    readonly property bool toastOutput: SettingsService.value("toasts.output") === true
    readonly property bool toastCharger: SettingsService.value("toasts.charger") === true
    readonly property bool toastVpn: SettingsService.value("toasts.vpn") === true
    readonly property bool toastCaps: SettingsService.value("toasts.capsLock") === true

    // The output: its name once the new default has settled (a headset
    // connecting brings its sink, then its profile).
    property string lastOutputLabel: ""
    Timer {
        id: outputToastTimer
        interval: 800
        onTriggered: {
            const sink = AudioService.sink
            const label = sink ? AudioService.shortLabel(sink, AudioService.sinks) : ""
            const text = Logic.outputToast(window.lastOutputLabel, label)
            window.lastOutputLabel = label
            if (text.length && window.toastOutput) window.showMessage(text, AudioService.deviceIcon(sink, false))
        }
    }

    // The charger: what was last said against now, 1.5 s after a change -
    // UPower reports a resume or a dock in several steps.
    function chargerNow() {
        return { hasBattery: PowerService.hasBattery, onBattery: PowerService.onBattery,
                 charging: PowerService.charging, percent: PowerService.percent }
    }
    property var lastCharger: null
    Timer {
        id: chargerToastTimer
        interval: 1500
        onTriggered: {
            const now = window.chargerNow()
            const text = Logic.chargerToast(window.lastCharger, now)
            window.lastCharger = now
            if (text.length) window.showMessage(text, PowerService.icon)
        }
    }
    Connections {
        target: PowerService
        enabled: window.toastCharger && window.armed
        function onOnBatteryChanged() { chargerToastTimer.restart() }
        function onChargingChanged() { chargerToastTimer.restart() }
    }

    // A VPN: the tunnels that are up, against the last list read - once
    // NetworkService has read its list at all (an empty one before is not
    // "disconnected").
    function vpnNow() { return NetworkService.activeVpns.map(item => ({ uuid: item.uuid, name: item.name })) }
    property var lastVpns: null
    Timer {
        id: vpnToastTimer
        interval: 300
        onTriggered: {
            if (!NetworkService.connectionsRead) return
            const now = window.vpnNow()
            const text = window.lastVpns === null ? "" : Logic.vpnToast(window.lastVpns, now)
            window.lastVpns = now
            if (text.length) window.showMessage(text, "󰖂")
        }
    }
    Connections {
        // No target while the message is off: the OSD alone never starts
        // the network service.
        target: window.toastVpn ? NetworkService : null
        enabled: window.armed
        function onActiveVpnsChanged() { vpnToastTimer.restart() }
        function onConnectionsReadChanged() { vpnToastTimer.restart() }
    }

    // Where each one starts: taken when it is turned on, or once the
    // session's first moments are over.
    function startToasts() {
        if (!armed) return
        if (toastCharger && lastCharger === null) lastCharger = chargerNow()
        if (toastVpn && lastVpns === null && NetworkService.connectionsRead) lastVpns = vpnNow()
        if (toastOutput) lastOutputLabel = AudioService.sink ? AudioService.shortLabel(AudioService.sink, AudioService.sinks) : ""
    }
    onArmedChanged: startToasts()
    onToastChargerChanged: { lastCharger = null; startToasts() }
    onToastVpnChanged: { lastVpns = null; startToasts() }
    onToastOutputChanged: startToasts()

    // Caps Lock: its key's release bind sends `osd capsLock` (it does not
    // take the key from the window), and the state comes from the
    // compositor, which keeps it - asked only while the message is on.
    function capsLock() {
        if (!toastCaps || capsRead.running) return
        capsRead.running = true
    }
    Process {
        id: capsRead
        stderr: ErrorLog { label: "Osd.capsRead" }
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const state = LockLogic.keyboardState(text)
                window.showMessage(Logic.capsToast(state.capsLock), "󰘲")
            }
        }
    }

    // A message with sample text whatever the settings say, for screenshots
    // (IPC `osd previewToast`): output, charger, vpn, capsLock, mics.
    function previewToast(kindName) {
        const sample = Logic.previewToast(kindName)
        if (!sample) return false
        showMessage(sample.text, sample.icon)
        return true
    }
    // Flags only (IPC `osd get`).
    function osdState() {
        return { showing: showing, kind: kind, inNotch: inNotch, talking: AudioService.talking,
                 toasts: { output: toastOutput, charger: toastCharger, vpn: toastVpn, capsLock: toastCaps } }
    }

    Connections {
        target: AudioService
        function onVolumeChanged() { window.volumeMoved() }
        function onMutedChanged() { window.volumeMoved() }
        function onSinkChanged() { window.volumeMoved() }
        function onMicMutedChanged() { window.micMoved() }
        function onSourceChanged() { window.micMoved() }
        function onMicrophonesSet(muted, changed, total) { window.microphonesSet(muted, changed, total) }
        // Push to talk shows the microphone while held, even when it was on
        // already and nothing changed.
        function onTalkingChanged() { if (AudioService.talking) window.show("mic") }
    }
    Connections {
        target: BrightnessService
        function onValueChanged() { if (Date.now() >= BrightnessService.quietUntil) window.show("brightness") }
        // A brightness key on an external screen (DDC/CI): its level, not the
        // backlight's (BrightnessService.osdLevel).
        function onDdcStepped() { window.show("brightness") }
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
                id: messageText
                Layout.fillWidth: true
                visible: window.isMessage
                text: window.message
                role: "small"
                elide: Text.ElideRight
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
                        color: window.mutedState ? Colors.mutedText : Colors.accentFill
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
                            color: index < KbdBacklightService.current ? Colors.accentFill : Colors.track
                            Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
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
