import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
WidgetBase {
    icon: AudioService.volumeIcon(AudioService.volume, AudioService.muted)
    label: Math.round(AudioService.volume * 100) + "%"
    name: "Volume"
    meter: AudioService.volume
    meterColor: AudioService.muted ? Colors.mutedText : Colors.accent
    // Which device it is going to, which is the question a percentage raises.
    detail: AudioService.sink ? AudioService.label(AudioService.sink) : ""

    // Scrolling over the widget changes the volume.
    WheelHandler {
        onWheel: event => AudioService.setVolume(AudioService.sink, AudioService.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05))
    }
}
