import QtQuick
import qs.theme

// One UI slider: a thick rounded track with a large round handle on top.
// value is normalized from `from` to `to`; `moved` fires while dragging so
// services can apply the value (they debounce if needed).
Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    property bool enabledState: true
    // Opt-in keyboard focus, like the other controls. The slider already takes
    // focus from a click (that is what the wheel rule reads), so this only adds
    // it to the tab order.
    property bool focusOnTab: false
    readonly property bool pressed: mouse.pressed
    property real liveValue: value
    // Where the fill starts. `from` fills from the left end, as a level does;
    // a value with a middle (pointer speed from slow through 0 to fast) sets
    // its middle, and the fill runs from there to the knob on either side.
    property real origin: from
    signal moved(real value)
    signal released(real value)

    readonly property real ratio: to > from ? Math.max(0, Math.min(1, ((pressed ? liveValue : value) - from) / (to - from))) : 0
    readonly property real originRatio: to > from ? Math.max(0, Math.min(1, (origin - from) / (to - from))) : 0
    // What is drawn. The *value* springs, not the pixels: animating the fill's
    // width and the knob's x also animated every resize of the slider, so a
    // page that relaid itself left knobs gliding after the track. Under the
    // finger it follows directly, or the spring would fight the hand.
    property real shownRatio: ratio
    Behavior on shownRatio {
        enabled: Animations.motionEnabled && !root.pressed
        SpringMotion { kind: "fast"; precision: 0.001 }
    }

    activeFocusOnTab: focusOnTab && enabledState
    // A key is a whole gesture: `moved` and then `released`, as a wheel step
    // is. Only `released` used to come, and the volume and brightness
    // sliders, which apply on `moved`, did nothing at all - while the key
    // was still taken, so it did not move on either.
    function commit(target) {
        root.moved(target)
        root.released(target)
    }
    // Where one wheel event takes the value: a twentieth of the range, the
    // way the wheel turned. NaN for an event that turned nothing: Qt starts
    // and ends a touchpad swipe with one (ScrollBegin, ScrollEnd), and reading
    // it as "down" moved a focused slider a step at each end of the swipe.
    // Handed on, those reach the list around it (ScrollFeel).
    function wheelTarget(angle) {
        if (!angle) return NaN
        const step = (to - from) / 20
        return Math.max(from, Math.min(to, value + (angle > 0 ? step : -step)))
    }
    // Disabled, the keys are not the slider's: they go on to the panel.
    Keys.onLeftPressed: event => {
        if (enabledState) root.commit(Math.max(from, value - (to - from) / 20))
        else if (event) event.accepted = false
    }
    Keys.onRightPressed: event => {
        if (enabledState) root.commit(Math.min(to, value + (to - from) / 20))
        else if (event) event.accepted = false
    }
    // Up and Down are left to the panel, which moves between controls with
    // them; the bigger steps and the ends are here.
    Keys.onPressed: event => {
        if (!enabledState) return
        const span = to - from
        const target = event.key === Qt.Key_Home ? from
            : event.key === Qt.Key_End ? to
            : event.key === Qt.Key_PageUp ? Math.min(to, value + span / 5)
            : event.key === Qt.Key_PageDown ? Math.max(from, value - span / 5)
            : NaN
        if (isNaN(target)) return
        event.accepted = true
        root.commit(target)
    }
    // Named by the row it sits in (SettingRow and ListRow hand their label
    // over) or by the caller - a slider anywhere else ("Output volume",
    // "Brightness") says what it moves here, or a screen reader announces
    // "slider, 40%" and nothing more. The value is the item's own `value`,
    // which Qt's slider role reads; the text says it as a share of the range.
    property string accessibleName: ""
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: Math.round(root.ratio * 100) + "%"
    implicitWidth: Metrics.sliderWidth
    implicitHeight: Metrics.sliderHandle + Metrics.spaceXs
    opacity: enabledState ? 1 : Effects.disabledOpacity

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: Metrics.sliderHandle / 2
        width: parent.width - Metrics.sliderHandle
        height: Metrics.sliderTrack
        radius: height / 2
        color: mouse.containsMouse && root.enabledState ? Colors.trackHover : Colors.track
        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }

        Rectangle {
            id: fill
            x: parent.width * Math.min(root.originRatio, root.shownRatio)
            width: parent.width * Math.abs(root.shownRatio - root.originRatio)
            height: parent.height
            radius: parent.radius
            color: mouse.containsMouse && root.enabledState ? Colors.accentFillHover : Colors.accentFill
            Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        }
    }

    Rectangle {
        id: handle
        width: Metrics.sliderHandle
        height: Metrics.sliderHandle
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: track.width * root.shownRatio
        color: Colors.knob
        border.width: Metrics.borderWidth
        border.color: Colors.knobBorder
        scale: root.pressed ? Effects.knobPressScale : 1
        Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

        // The handle carries the focus ring: it marks the slider the wheel
        // will move.
        FocusRing { active: root.activeFocus; controlRadius: handle.radius }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -Metrics.spaceXs
        anchors.bottomMargin: -Metrics.spaceXs
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function valueAt(x) {
            const ratio = Math.max(0, Math.min(1, (x - track.x) / Math.max(1, track.width)))
            return root.from + ratio * (root.to - root.from)
        }
        onPressed: event => {
            root.forceActiveFocus()
            root.liveValue = valueAt(event.x)
            root.moved(root.liveValue)
        }
        onPositionChanged: event => { if (pressed) { root.liveValue = valueAt(event.x); root.moved(root.liveValue) } }
        onReleased: root.released(root.liveValue)
        // Scrolling a page must not change sliders it passes over: the wheel
        // only moves a slider that was used before (it has focus) or with Ctrl
        // held. Otherwise the event goes on to the scrolling view.
        onWheel: event => {
            const next = root.wheelTarget(event.angleDelta.y)
            if (isNaN(next) || (!root.activeFocus && !(event.modifiers & Qt.ControlModifier))) {
                event.accepted = false
                return
            }
            root.commit(next)
        }
    }
}
