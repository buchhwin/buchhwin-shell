import QtQuick
import qs.theme
import qs.services

// A track change in the notch, for a few seconds. It is the one of the three
// displays that has no surface of its own to fall back on: a volume key has an
// OSD and a notification has a popup, and a new song has never announced
// itself at all. So this is the whole feature, and on a screen without a notch
// - or with the switch off - nothing happens, which is exactly what happened
// before.
//
// It watches the title rather than the player's state: pause and resume are
// not a new track, and announcing them would make the notch flicker every time
// somebody taps space.
QtObject {
    id: announcer

    readonly property string title: MprisService.title
    readonly property string artist: MprisService.artist
    readonly property string screenName: PanelService.screen ? PanelService.screen.name : ""
    // The first title after the shell starts is not a change, it is what was
    // already playing. Announcing it would put a display in the notch every
    // time the session comes up.
    property bool armed: false
    property bool showing: false

    readonly property bool inNotch: showing && title.length > 0
        && NotchService.takesDisplay("media", screenName)

    function publish() {
        NotchService.setDisplay("media", screenName, inNotch ? {
            kind: "media",
            icon: MprisService.playing ? Icons.play : Icons.pause,
            iconSource: MprisService.artUrl,
            title: title,
            subtitle: artist
        } : null)
    }

    property Connections watcher: Connections {
        target: MprisService
        function onTitleChanged() {
            if (!announcer.armed || !announcer.title.length) return
            announcer.showing = true
            hide.restart()
        }
    }

    property Timer arm: Timer {
        interval: 2500
        running: true
        onTriggered: announcer.armed = true
    }

    property Timer hide: Timer {
        interval: Metrics.notchTrackTimeout
        onTriggered: announcer.showing = false
    }

    onInNotchChanged: publish()
    onTitleChanged: publish()
}
