import QtQuick
import qs.theme
import "WheelLogic.js" as Wheel

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
    // `false` for a value that only ever creeps on by itself (a track's
    // position, a second at a time): the spring ran for ~180 ms after every
    // tick to move the knob under two pixels, which redrew the panel - and
    // the blur behind it - for a sixth of every second of playback.
    property bool glide: true
    Behavior on shownRatio {
        enabled: Animations.motionEnabled && !root.pressed && root.glide
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
    // Where `steps` wheel steps take the value: a twentieth of the range each,
    // the way the wheel turned, and no further than either end. NaN for no
    // step at all.
    function wheelTarget(steps) {
        if (!steps) return NaN
        return Math.max(from, Math.min(to, value + steps * (to - from) / 20))
    }
    // What the events of one turn of the wheel left over: a step is a notch
    // of it, however finely the wheel slices it (WheelLogic.js). One step per
    // event made a high-resolution wheel's eighth of a notch a whole step.
    property var wheelCarry: null
    // One wheel event, from the MouseArea below or from a test with a plain
    // object of the same fields. Returns whether the slider took it; what it
    // did not take goes on to the list around it (ScrollFeel). The rule is
    // WheelLogic.sliderStep: the wheel moves a slider that has the focus or
    // one under Ctrl, and a touchpad swipe only under Ctrl - a swipe over a
    // focused slider took every one of its 12 to 41 updates as a step and
    // ran the volume to an end; it scrolls the page now. Qt starts and ends a
    // swipe with an event that turned nothing (ScrollBegin, ScrollEnd); those
    // are always handed on, and reading them as "down" once moved a focused
    // slider a step at each end of the swipe.
    function wheel(event) {
        const answer = Wheel.sliderStep(root.wheelCarry, event.phase, event.angleDelta.y, event.pixelDelta.y,
                                        root.activeFocus, (event.modifiers & Qt.ControlModifier) !== 0)
        root.wheelCarry = answer.carry
        if (!answer.taken) return false
        const next = root.wheelTarget(answer.steps)
        if (!isNaN(next)) root.commit(next)
        return true
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
        // Scrolling a page must not change sliders it passes over: what the
        // slider does not take (`wheel` above) goes on to the scrolling view.
        onWheel: event => { event.accepted = root.wheel(event) }
    }
}
