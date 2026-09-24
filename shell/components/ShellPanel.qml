import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.theme
import qs.services
import "../../services/arrange/ArrangeLogic.js" as Arrange

// Full-screen overlay hosting one floating panel card. Handles focus, scrim,
// Escape, click-outside and the open/close transition.
PanelWindow {
    id: window
    required property string panelId
    property string placement: "top-right"   // top-right, center, top-center, right
    property real cardWidth: Metrics.controlCenterWidth
    property real cardHeight: -1               // -1 follows content height
    property real maxCardHeight: anchorBottom >= 0 ? anchorBottom - Metrics.screenMargin
        : height - (anchorTop >= 0 ? anchorTop : Metrics.screenMargin) - bottomOffset
    // What is really left below where the card starts, which without an anchor
    // is `topOffset` (under the notch or the bar) rather than the screen edge.
    // `maxCardHeight` measures from the edge and so promises more room than
    // there is; a panel that fills its budget runs past the bottom of the
    // screen and clips its last rows away with no way to reach them.
    //
    // This is not folded into `maxCardHeight` on purpose. Doing that clamps
    // every panel for the first time, and at least one of them has content
    // whose size follows the body height - which turns the clamp into a
    // binding loop on `targetHeight`. Panels that need the honest figure ask
    // for it; fixing the rest is its own piece of work.
    readonly property real roomBelowTop: Math.max(0, height - topOffset - bottomOffset)
    property color scrimColor: Colors.scrim
    // A panel the user may drag by the strip along the top of its card.
    // `moveX`/`moveY` are an offset from where the panel would otherwise sit,
    // not an absolute position: a different screen, a bar appearing or the
    // window changing size then moves the panel with it instead of stranding
    // it off the edge. They are clamped so the card cannot leave the screen,
    // which also means a drag that runs into an edge does not build up a debt
    // to undo on the way back.
    // A panel the user may resize, by a grip on the bottom-left corner of its
    // card. The panel says what it may be resized to (`sizeBounds`), when the
    // grip is reachable (`gripShown`) and where the result is kept (`resized`);
    // everything else is here, because the control center and the dashboard had
    // a copy of it each and the two had already drifted apart in their
    // comments.
    //
    // While the grip is pulled the card takes the size under the hand, so the
    // panel resizes live; the release is only when it is written down.
    property bool resizable: false
    property bool gripShown: false
    property var sizeBounds: ({})
    property bool sizing: false
    property real dragWidth: 0
    property real dragHeight: 0
    signal resized(real width, real height)

    property bool movable: false
    property real moveX: 0
    property real moveY: 0
    // Where a movable panel starts when it opens. A panel that remembers its
    // place binds this to a setting and saves `moved`.
    property real savedMoveX: 0
    property real savedMoveY: 0
    signal moved(real x, real y)
    property bool dismissOnOutsideClick: true
    property bool showCard: true
    // A panel casts a shadow so it reads as lifted off the desktop; one over a
    // strong scrim (session menu, dialogs) needs a deeper one to stay separate.
    property bool shadow: true
    readonly property bool overScrim: scrimColor === Colors.scrimStrong
    readonly property int elevationMax: overScrim ? Effects.elevation3Max : Effects.elevation2Max
    readonly property real elevationBlur: overScrim ? Effects.elevation3Blur : Effects.elevation2Blur
    readonly property real elevationOpacity: overScrim ? Effects.elevation3Opacity : Effects.elevation2Opacity
    readonly property int elevationOffset: overScrim ? Effects.elevation3Offset : Effects.elevation2Offset
    // Panels open next to what opened them: centred below a pill or widget
    // (anchorX/anchorTop), above a widget in the lower half (anchorBottom).
    // Opened by a hotkey, top-right panels follow the desktop clock: below it,
    // centred on it unless it sits in the right third, and below the pill bar.
    readonly property var clockRect: LayoutService.clockRect(screen ? screen.name : "")
    // How far the bar reaches into this screen, and from which edge. A bar at
    // the bottom keeps a panel off the bottom of the screen instead of off the
    // top, so the one number turns into one of two offsets.
    readonly property real barInset: LayoutService.barBottom(screen ? screen.name : "")
    readonly property string barEdge: LayoutService.barEdge(screen ? screen.name : "")
    readonly property bool barAtBottom: barEdge === "bottom"
    readonly property bool barAtLeft: barEdge === "left"
    readonly property bool barAtRight: barEdge === "right"
    readonly property bool barVertical: barAtLeft || barAtRight
    // A vertical bar takes nothing off the top, so the panel's top offset
    // stops pretending it does.
    readonly property real barBottom: barAtBottom || barVertical ? -1 : barInset
    readonly property real clockBottom: clockRect ? clockRect.y + clockRect.height + Metrics.spaceSm : -1
    readonly property real clockCentre: clockRect ? clockRect.x + clockRect.width / 2 : -1
    property real topOffset: clockBottom >= 0 || barBottom >= 0
        ? Math.max(clockBottom, barBottom >= 0 ? barBottom + Metrics.spaceSm : -1) : Metrics.panelTopOffset
    // What a panel has to stay clear of at the bottom: the bar when it is
    // there, otherwise the screen margin every panel already keeps.
    readonly property real bottomOffset: barAtBottom && barInset >= 0
        ? barInset + Metrics.spaceSm : Metrics.screenMargin
    // The same pair for a bar that runs down one side. `under` and `above`
    // have a twin in `beside`, and so does this.
    readonly property real leftOffset: barAtLeft && barInset >= 0
        ? barInset + Metrics.spaceSm : Metrics.screenMargin
    readonly property real rightOffset: barAtRight && barInset >= 0
        ? barInset + Metrics.spaceSm : Metrics.screenMargin
    // Panels opened from a pill are centred below it (screen x in PanelService.args).
    // The arguments are kept while closing: PanelService clears them at once,
    // which would move the card to its default place during the animation.
    property var openArgs: ({})
    function argNumber(name) { return openArgs && typeof openArgs[name] === "number" ? openArgs[name] : -1 }
    // A top-right panel opened by a hotkey follows the desktop clock, so it
    // lands under the thing that told you the time. In notch mode the clock
    // *is* the notch, dead centre, so the panel ends up centred - which is
    // right for a panel about the notch and wrong for one that belongs in the
    // corner. `followClock` is how a panel says it belongs in the corner.
    property bool followClock: true
    readonly property real anchorX: spotAlong >= 0 && !barVertical ? spotAlong
        : argNumber("anchorX") >= 0 ? argNumber("anchorX")
        : followClock && placement === "top-right" && clockCentre >= 0 && clockCentre < width * 2 / 3
            ? clockCentre : -1
    readonly property real anchorTop: argNumber("anchorTop")
    readonly property real anchorBottom: argNumber("anchorBottom")
    // The third anchor concept, for a bar that runs down the screen: "beside
    // me, centred on this height". The x follows from which side the bar is
    // on, so it needs no second number.
    readonly property real anchorY: spotAlong >= 0 && barVertical ? spotAlong : argNumber("anchorY")

    // Where the bar says panels open, when it says anything: "widget" leaves
    // the pill's own anchor alone, the other three pin every panel to a place
    // along the bar whatever opened it. Wanting the control center under your
    // hand and wanting it always in the middle are both reasonable and only
    // the user knows which.
    readonly property string barSpot: LayoutService.barPanelSpot()
    readonly property real spotSpan: barVertical ? height : width
    readonly property real spotAlong: barSpot === "start" ? Metrics.screenMargin
        : barSpot === "centre" ? spotSpan / 2
        : barSpot === "end" ? spotSpan - Metrics.screenMargin
        : -1
    // Panels grow out of what opened them: the collapsed notch, or the pill or
    // widget that passes its rect in openArgs. `morph: false` is the escape
    // hatch for a panel where the grow does not read well.
    property bool morph: true
    readonly property real originX: argNumber("originX")
    readonly property real originY: argNumber("originY")
    readonly property real originWidth: argNumber("originWidth")
    readonly property real originHeight: argNumber("originHeight")
    // The notch reports its collapsed rect, so a hotkey-opened panel grows out
    // of it without the caller passing anything.
    readonly property var notchOrigin: LayoutService.notchShown ? clockRect : null
    readonly property bool hasOrigin: morph && Animations.motionEnabled
        && (originWidth > 0 || (notchOrigin !== null && notchOrigin !== undefined))
    readonly property real fromX: originWidth > 0 ? originX : notchOrigin ? notchOrigin.x : 0
    readonly property real fromY: originWidth > 0 ? originY : notchOrigin ? notchOrigin.y : 0
    readonly property real fromWidth: originWidth > 0 ? originWidth : notchOrigin ? notchOrigin.width : 0
    readonly property real fromHeight: originWidth > 0 ? originHeight : notchOrigin ? notchOrigin.height : 0

    // The item that should have the keyboard when the panel opens, normally a
    // search field. Set it and the panel focuses it itself: keyScope steps
    // aside instead of racing it, and Escape still closes because the card
    // carries the same handler and *is* an ancestor of the content.
    property Item keyForward: null
    default property alias content: body.data
    readonly property alias card: card
    readonly property real cardTargetWidth: card.targetWidth
    // The height the card was granted, for content that sizes itself to it
    // (the control center's and the dashboard's lists). Worked out from the
    // request and the room rather than read back from the card: reading
    // `card.targetHeight` subscribed the content to the very property that
    // measures the content, and when a panel switched from a stored height
    // to measuring - the control center opening a page - the old
    // subscription fired inside the measurement and Qt reported a binding
    // loop on `targetHeight`. Without a stored height nothing is granted,
    // and -1 says so; readers already ask `cardHeight > 0` first.
    readonly property real cardTargetHeight: cardHeight > 0 ? Math.min(cardHeight, maxCardHeight) : -1
    readonly property bool wanted: PanelService.active === panelId
    property bool shown: false
    // An unclipped layer over the card, anchored to the window rather than to
    // the card, which clips. What has to leave the card is drawn here: the
    // ghost an arrange surface drags, and its drop marker.
    readonly property alias overlay: overlayLayer
    // Where the card really is, for anything that has to sit on its corner -
    // a grip that resizes the panel. Read only: the card places itself.
    readonly property alias cardRect: card
    signal escapePressed()

    function requestClose() { PanelService.close(panelId) }
    function escapeKey() {
        // A drag takes Escape for itself: it cancels the drag and keeps the
        // panel, which is what every other editor in the shell does.
        if (LayoutService.arrangeDragging.length) {
            LayoutService.arrangeDragging = ""
            return
        }
        escapePressed()
        requestClose()
    }
    function focusEntry() {
        if (!keyForward) return
        if (typeof keyForward.focusInput === "function") keyForward.focusInput()
        else keyForward.forceActiveFocus()
    }

    screen: PanelService.screen
    visible: shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "buchhwin-" + panelId
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onWantedChanged: {
        if (wanted) {
            openFrames = 0
            openWorstMs = 0
            progress.armed = false
            progress.value = 0
            openArgs = PanelService.args
            // The scrim is **not** drawn here: there is one for all panels, on
            // its own surface below them (shell/components/ScrimLayer.qml),
            // because two panels are on screen whenever one hands over to
            // another and two scrims fading past each other is a visible
            // flicker. Saying how deep this one wants it is all that is left.
            PanelService.reportScrim(panelId, scrimColor)
            // A panel that may be moved starts where it was left.
            if (movable) { moveX = savedMoveX; moveY = savedMoveY }
            closeTimer.stop()
            shown = true
            progress.target = 1
            Qt.callLater(focusEntry)
        } else {
            progress.target = 0
            closeTimer.restart()
        }
    }

    Connections {
        target: PanelService
        function onArgsChanged() { if (window.wanted) window.openArgs = PanelService.args }
    }

    Timer {
        id: closeTimer
        interval: Animations.popupClose + 20
        onTriggered: if (!window.wanted) window.shown = false
    }

    QtObject {
        id: progress
        property real target: 0
        // Time-based, and **started on the first frame that is actually
        // drawn**. Both halves of that were measured, and each one alone was
        // wrong:
        //
        // Time alone: a panel's layer surface is created at the moment it
        // opens, and the compositor needs a round trip to configure it before
        // anything can be drawn. The clock does not wait, so the first frame
        // that reached the screen was already most of the way through - six
        // open-and-close cycles rendered seven frames in total, measured with
        // QSG_RENDER_TIMING. An animation almost nobody saw.
        //
        // Frames alone: advancing by `frameTime` once per frame sounds
        // honest, but the client is not locked to the display. A 220 ms open
        // reported **18** frames on a 60 Hz screen, which is 13 refreshes -
        // so a third of them were drawn in about 11 ms, never shown, and the
        // motion took its step sizes from when the shell happened to render
        // rather than from when the screen happened to show. Uneven steps in
        // an even time is exactly what "not smooth" looks like.
        //
        // So: the curve runs on the clock, which is uniform, and the clock
        // does not start until the surface has put one frame on the screen.
        property bool armed: false
        property real value: 0
        Behavior on value {
            // Off until the first frame: an animation that is already running
            // while nothing can be drawn is the first mistake above.
            enabled: progress.armed && Animations.enabled
            NumberAnimation {
                duration: progress.target > 0 ? Animations.popupOpen : Animations.popupClose
                easing.type: progress.target > 0 ? Animations.easingEnter : Animations.easingExit
            }
        }
        // Closing needs no wait: the surface has been on the screen all along.
        onTargetChanged: if (target === 0 || !Animations.enabled) { armed = true; value = target }
    }

    // A sibling, not a child of `progress`: a QtObject holds properties and
    // takes no children at all. It runs only until the surface has drawn its
    // first frame; from there the clock carries the motion.
    // How many frames the last open actually got. Counts only, readable over
    // IPC (`editor get`): "the animation is choppy" and "the animation is
    // short of frames" are different claims, and this is the one that can be
    // checked on the machine the complaint came from rather than on a nested
    // session that was never the problem.
    property int openFrames: 0
    // The longest gap between two of them, in milliseconds. The count alone
    // says an animation was drawn; this says whether it was drawn *evenly*.
    // Thirteen frames with one 60 ms gap in the middle is a count of fourteen
    // and a stutter anybody can see.
    property int openWorstMs: 0
    FrameAnimation {
        // Only while something is actually moving: to start the clock on the
        // first frame, and to count the frames the motion is drawn in. Left
        // running for the whole time a panel is open it ticks on every frame
        // of a still picture, which is a callback per refresh for nothing.
        running: Animations.enabled && window.shown
            && (!progress.armed || progress.value !== progress.target)
        onTriggered: {
            if (!progress.armed) {
                progress.armed = true
                progress.value = progress.target
                return
            }
            if (progress.value === progress.target) return
            window.openFrames += 1
            window.openWorstMs = Math.max(window.openWorstMs, Math.round(frameTime * 1000))
            if (progress.target > 0 && Math.abs(progress.value - 1) < 0.02)
                PanelService.reportOpenFrames(window.panelId, window.openFrames, window.openWorstMs)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: window.dismissOnOutsideClick
        onClicked: window.requestClose()
    }

    // Holds the panel's key focus while nothing inside the card wants it. The
    // content is a sibling of this item, not a child, so a key pressed inside
    // the card never reaches it - a panel with a keyForward hands the focus to
    // that field instead and lets the card handle Escape.
    Item {
        id: keyScope
        anchors.fill: parent
        focus: window.wanted && !window.keyForward
        Keys.onEscapePressed: window.escapeKey()
    }

    // The shadow is cast by an invisible twin of the card, not by putting the
    // card itself behind a MultiEffect: a lone rounded rectangle is a trivial
    // texture that is only redrawn when the geometry changes, while the card
    // would be re-rendered on every hover inside it.
    Rectangle {
        id: shadowCaster
        visible: false
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        color: Colors.shadow
        layer.enabled: true
    }
    MultiEffect {
        source: shadowCaster
        anchors.fill: shadowCaster
        visible: window.showCard && window.shadow
        opacity: progress.value
        shadowEnabled: true
        shadowColor: Colors.shadow
        blurMax: window.elevationMax
        shadowBlur: window.elevationBlur
        shadowOpacity: window.elevationOpacity
        shadowVerticalOffset: window.elevationOffset
        // The caster is painted too, and the panel is translucent, so an
        // unmasked shadow would darken the panel from underneath. Masked by
        // the caster itself, inverted, only what falls outside the card is
        // drawn. autoPadding stays on, or the shadow is clipped to the rect it
        // is supposed to spread beyond.
        maskEnabled: true
        maskSource: shadowCaster
        maskInverted: true
    }

    Rectangle {
        id: card
        // The layer that draws a tooltip for any control inside this card. It
        // is named here, on an ancestor of the content, because a control finds
        // it by walking up its own parents - the layer itself lives on the
        // overlay, which is a sibling of the card and unclipped.
        readonly property Item toolTipLayer: tips
        // The size and place the panel settles at. The card itself may be
        // smaller while it grows out of what opened it.
        readonly property real targetWidth: Math.min(window.cardWidth, window.width - Metrics.screenMargin * 2)
        readonly property real targetHeight: window.cardHeight > 0 ? Math.min(window.cardHeight, window.maxCardHeight)
            : Math.min(body.childrenRect.height + Metrics.panelPadding * 2, window.maxCardHeight)
        // A vertical bar pushes the panel sideways rather than down, so a
        // panel opened from one of its pills comes out *beside* it and every
        // other panel simply keeps clear of it.
        readonly property real targetX: window.placement === "center" ? (window.width - targetWidth) / 2
            : window.anchorY >= 0
                ? (window.barAtRight ? Math.max(window.leftOffset, window.width - window.rightOffset - targetWidth)
                                     : window.leftOffset)
            : window.anchorX >= 0 && window.placement !== "right"
                ? Math.max(window.leftOffset, Math.min(window.width - targetWidth - window.rightOffset, window.anchorX - targetWidth / 2))
            : window.placement === "top-center" ? (window.width - targetWidth) / 2
            : window.width - targetWidth - window.rightOffset
        // A panel opened with no anchor sits under the bar when the bar is at
        // the top, and above it when it is at the bottom. Its anchor is fixed
        // for the panel's whole life and only this margin moves, which is what
        // a mapped layer surface will accept.
        readonly property real targetY: window.placement === "center" ? (window.height - targetHeight) / 2
            : window.placement === "right" ? Metrics.screenMargin
            // Centred on the pill that opened it, clamped into the screen.
            : window.anchorY >= 0
                ? Math.max(Metrics.screenMargin,
                           Math.min(window.height - targetHeight - Metrics.screenMargin, window.anchorY - targetHeight / 2))
            : window.anchorBottom >= 0 ? Math.max(Metrics.screenMargin, window.anchorBottom - targetHeight)
            : window.anchorTop >= 0 ? Math.min(window.anchorTop, window.height - targetHeight - window.bottomOffset)
            : window.barAtBottom ? window.height - targetHeight - window.bottomOffset
            : window.topOffset
        // Linear in the transition's own eased progress, so the grow follows
        // the same curve as the fade.
        function grow(from, to) { return window.hasOrigin ? from + (to - from) * progress.value : to }

        // The card stays centred on the interpolated centre, so it really does
        // widen out of the notch or the pill. Offsetting the start by the
        // *settled* width instead put the left edge at its final place on the
        // first frame and grew the card rightwards from there, which read as
        // "it starts on the left". `growing` is read instead of `width` so the
        // x binding does not depend on its own result.
        readonly property real growing: grow(window.fromWidth, targetWidth)
        // Where it really sits: the place the panel would take, plus however
        // far the user has dragged it, clamped into the screen.
        readonly property real placedX: window.movable
            ? Math.max(Metrics.screenMargin,
                       Math.min(window.width - targetWidth - Metrics.screenMargin, targetX + window.moveX))
            : targetX
        readonly property real placedY: window.movable
            ? Math.max(window.topOffset,
                       Math.min(window.height - targetHeight - window.bottomOffset, targetY + window.moveY))
            : targetY
        width: growing
        height: grow(window.fromHeight, targetHeight)
        x: grow(window.fromX + window.fromWidth / 2, placedX + targetWidth / 2) - growing / 2
        y: grow(window.fromY, placedY)
        radius: Metrics.radiusPanel
        // Escape from inside the panel: the card is an ancestor of the content,
        // so a key the content did not take arrives here.
        Keys.onEscapePressed: window.escapeKey()
        color: "transparent"
        clip: window.showCard
        opacity: progress.value

        // The chrome is a child rather than the card itself, so `showCard:
        // false` can take the background, the border and the clipping away and
        // still leave the geometry, the focus and Escape in place. That is
        // what a panel that fills the screen and draws its own background
        // needs (the overview).
        Rectangle {
            anchors.fill: parent
            visible: window.showCard
            radius: parent.radius
            border.width: Metrics.borderWidth
            border.color: Colors.panelBorder
            // Not one flat fill: the panel catches a little light along its top
            // edge, which gives a large surface a direction. Two stops on one
            // rectangle, so it stays a single scene-graph node.
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(Colors.panelFor(window.panelId),
                    Qt.rgba(Colors.sheen.r, Colors.sheen.g, Colors.sheen.b, Effects.sheenTop)) } // style: the sheen colour and its strength are both tokens
                GradientStop { position: 1; color: Qt.tint(Colors.panelFor(window.panelId),
                    Qt.rgba(Colors.sheen.r, Colors.sheen.g, Colors.sheen.b, Effects.sheenBottom)) } // style: see above
            }
        }
        scale: Animations.motionEnabled && !window.hasOrigin
            ? Effects.hoverScaleFrom + (1 - Effects.hoverScaleFrom) * progress.value : 1
        transform: Translate {
            y: Animations.motionEnabled && !window.hasOrigin ? (1 - progress.value) * -Metrics.spaceSm : 0
        }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => event.accepted = false }

        // Dragging a movable panel. The strip is below `body` (z 1), so
        // anything the panel puts along its top keeps its own clicks; what is
        // left up there is a title, which is text.
        //
        // The offset accumulates from the press point and is never re-based:
        // the strip moves with the card, so once the card has followed the
        // pointer the local position is back where the press was, and the next
        // event's offset is again exactly what is still to move. Re-basing it
        // on every event moves the card once and then stops.
        MouseArea {
            id: mover
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Metrics.controlHeight
            enabled: window.movable && window.showCard
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real fromX: 0
            property real fromY: 0
            onPressed: mouse => { fromX = mouse.x; fromY = mouse.y }
            onPositionChanged: mouse => {
                if (!pressed) return
                window.moveX = card.placedX - card.targetX + (mouse.x - fromX)
                window.moveY = card.placedY - card.targetY + (mouse.y - fromY)
            }
            onReleased: window.moved(window.moveX, window.moveY)
            // Back to where the panel places itself.
            onDoubleClicked: {
                window.moveX = 0
                window.moveY = 0
                window.moved(0, 0)
            }
        }

        Item {
            id: body
            // Above optional card backgrounds (PopupPanel backdrop).
            z: 1
            // Not anchors.fill: the content keeps the size the panel settles
            // at while the card grows, so no layout runs per frame and the
            // card clips what does not fit yet.
            x: Metrics.panelPadding
            y: Metrics.panelPadding
            width: Math.max(0, card.targetWidth - Metrics.panelPadding * 2)
            // With a stored height the content gets exactly that - the granted
            // figure, never `card.targetHeight`, which is what measures the
            // content when nothing is stored: a body that read it stayed
            // subscribed across the switch, and a child that filled its parent
            // then set the measurement that set its parent, which is the
            // binding loop again. Without a stored height the content is
            // given the room instead - the most the card can be - and the card
            // clips to what it settles at.
            height: Math.max(0, (window.cardHeight > 0 ? window.cardTargetHeight : window.maxCardHeight)
                                - Metrics.panelPadding * 2)
        }
    }

    // After the card, so it paints above it. What it holds is usually a
    // picture - a drag ghost - but a grip on the card's corner lives here too,
    // because the card clips and a grip on its edge would be cut in half.
    Item {
        id: overlayLayer
        anchors.fill: parent
        z: 10

        Rectangle {
            id: gripDot
            visible: window.resizable && window.gripShown && window.showCard
            // Far enough in that a round grip clears a round corner. A circle
            // of radius g sits inside a corner of radius r only while its
            // centre is within r - g of the arc's centre, and the centre of a
            // grip inset by `i` on both edges is at √2 (r - i - g) from it. At
            // a flat 2 px the grip hung 2.1 px outside the card's bottom-left
            // corner at the default 20 px rounding, which reads as a stray dot
            // beside the panel rather than a handle on it.
            //
            // A corner smaller than the grip has no room to escape into, so
            // the term goes negative there and the plain inset stands. The
            // extra step is breathing room: the bare minimum has the grip
            // *touching* the arc, which still reads as a dot on the edge
            // rather than one inside the card.
            readonly property int inset: Math.max(Metrics.spaceXxs,
                Math.ceil((card.radius - width / 2) * (1 - Math.SQRT1_2)) + Metrics.spaceXxs)
            x: card.x + inset
            y: card.y + card.height - height - inset
            width: Metrics.iconSm
            height: width
            radius: width / 2
            // Accent and opaque, like the handle on every tile: at 11.5 % white
            // it vanished on a light panel.
            color: grip.pulling || grip.containsMouse ? Colors.accentHover : Colors.accent
            border.width: Metrics.borderWidth
            border.color: Colors.accent

            MouseArea {
                id: grip
                anchors.fill: parent
                anchors.margins: -Metrics.spaceXs
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeBDiagCursor
                readonly property bool pulling: window.sizing
                // The corner the card is anchored by, taken once at the press.
                // The live edge cannot be used: a panel anchored to the desktop
                // clock has *both* edges move with the width, so the drag
                // chased its own result - the gearing halved and it never
                // landed where it was let go.
                property real fromRight: 0
                property real fromTop: 0
                property real pressX: 0
                property real pressY: 0
                property bool moved: false
                onPressed: mouse => {
                    const point = mapToItem(overlayLayer, mouse.x, mouse.y)
                    fromRight = card.x + card.width
                    fromTop = card.y
                    pressX = point.x
                    pressY = point.y
                    moved = false
                    window.dragWidth = card.width
                    window.dragHeight = card.height
                    window.sizing = true
                }
                onPositionChanged: mouse => {
                    if (!window.sizing) return
                    const point = mapToItem(overlayLayer, mouse.x, mouse.y)
                    if (!moved) {
                        if (Math.abs(point.x - pressX) + Math.abs(point.y - pressY) < Metrics.dragThreshold) return
                        moved = true
                    }
                    const wanted = Arrange.panelDragTo(point.x, point.y,
                                                       { right: fromRight, top: fromTop }, window.sizeBounds)
                    window.dragWidth = wanted.width
                    window.dragHeight = wanted.height
                }
                onReleased: {
                    if (!window.sizing) return
                    window.sizing = false
                    // A press that never moved is not a resize. It used to
                    // write the size the card happened to be clamped to at that
                    // moment, which on a narrower screen silently shrank the
                    // stored one.
                    if (moved) window.resized(window.dragWidth, window.dragHeight)
                    moved = false
                }
                onCanceled: {
                    window.sizing = false
                    moved = false
                }
            }
        }

        // Above the drag ghost: a tooltip explains a control, and a control is
        // never the thing being dragged.
        ToolTipLayer { id: tips; z: 1 }
    }
}
