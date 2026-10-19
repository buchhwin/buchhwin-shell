import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
import "../components/WheelLogic.js" as Wheel
WidgetBase {
    id: root
    icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
    label: Math.round(AudioService.volume * 100) + "%"
    name: "Volume"
    meter: AudioService.volume
    // Muted in the surface's muted ink, not the theme's: on the notch that
    // one is a grey made for a panel.
    // The level in the accent made for a fill (WidgetBase.levelFill): the
    // raw teal was 1.08:1 on a light track.
    meterColor: AudioService.muted ? root.mutedTextColor : root.levelFill
    // Which device it is going to, which is the question a percentage raises.
    detail: AudioService.sink ? AudioService.label(AudioService.sink) : ""

    // Scrolling over the widget changes the volume, 5 % a step - and a step
    // is a distance, not an event (WheelLogic.js): a notch of a wheel, or
    // 40 px of a two-finger swipe. One step per event made each of a swipe's
    // 12 to 41 updates a step, from 30 % to 100 % in the shortest one.
    // An event that turned nothing is no step: Qt ends a touchpad swipe with
    // one (ScrollEnd, no delta), and reading it as "down" would take 5 % off
    // after the swipe.
    WheelHandler {
        // What the events so far left short of a step.
        property var carry: null
        onWheel: event => {
            carry = Wheel.step(carry, event.phase, event.angleDelta.y, event.pixelDelta.y)
            if (carry.steps !== 0)
                AudioService.setVolume(AudioService.sink, AudioService.volume + carry.steps * 0.05)
        }
    }
}
