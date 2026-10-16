import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
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

    // Scrolling over the widget changes the volume. An event that turned
    // nothing is no step: Qt ends a touchpad swipe with one (ScrollEnd, no
    // delta), and reading it as "down" would take 5 % off after the swipe.
    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y !== 0)
                AudioService.setVolume(AudioService.sink, AudioService.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05))
        }
    }
}
