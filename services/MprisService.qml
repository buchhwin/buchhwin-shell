pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "media/MediaLogic.js" as Logic

// Media players. The position only refreshes while some UI tracks it.
Singleton {
    id: root
    readonly property var players: Mpris.players.values
    property string selectedName: ""
    property int trackers: 0
    readonly property var active: players.find(player => player.dbusName === selectedName)
        || players.find(player => player.isPlaying) || (players.length ? players[0] : null)
    readonly property bool hasPlayer: active !== null
    readonly property string title: active ? (active.trackTitle || active.identity || "") : ""
    readonly property string artist: active ? (active.trackArtist || "") : ""
    readonly property string album: active ? (active.trackAlbum || "") : ""
    // Cover art, checked before it is handed out.
    //
    // A player's art is often a temporary file it deletes when the track
    // changes - Chrome writes /tmp/.com.google.Chrome.XXXXXX and removes it on
    // the next one. A dead path given to an `Image` warns every time a surface
    // tries it, and there are seven consumers of this property across the bar,
    // the notch, two popups, the media card, a widget and the lock screen. On
    // a three-monitor dock that was 108 "Cannot open" warnings in one session
    // log, and it broke the smoke test, which reads the log.
    //
    // So the path is checked once per change, here, rather than by each
    // consumer. Anything that is not a local file (http, data:) is handed
    // straight through: only a path can be checked, and only a path goes stale.
    readonly property string rawArtUrl: active ? (active.trackArtUrl || "") : ""
    property string artUrl: ""

    function localPath(url) {
        const text = String(url || "")
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.slice(7)) : ""
    }

    function checkArt() {
        // The value is read here and not through a property bound to the same
        // thing: a change handler is not promised that a derived binding has
        // caught up, which this project has already paid for once.
        const url = rawArtUrl
        const path = localPath(url)
        if (!path.length) {
            artUrl = url
            return
        }
        artUrl = ""
        artCheck.running = false
        artCheck.pending = url
        artCheck.command = ["test", "-r", path]
        artCheck.running = true
    }
    onRawArtUrlChanged: checkArt()
    Component.onCompleted: checkArt()

    Process {
        id: artCheck
        // Which url this answer belongs to; a slow answer must not overwrite
        // the art of a track that has already started.
        property string pending: ""
        onExited: code => {
            if (root.rawArtUrl === artCheck.pending) root.artUrl = code === 0 ? artCheck.pending : ""
        }
    }
    readonly property bool playing: active !== null && active.isPlaying
    readonly property bool canShuffle: active !== null && active.canControl && active.shuffleSupported
    readonly property bool canLoop: active !== null && active.canControl && active.loopSupported
    // The PipeWire stream playing this player's audio (for its volume), else
    // null; players without a matching stream may offer MPRIS volume instead.
    readonly property var stream: {
        if (!active) return null
        const streams = AudioService.playbackStreams
        const index = Logic.streamIndex(active, streams.map(node => {
            const props = node.properties || {}
            return { appName: props["application.name"] || "", binary: props["application.process.binary"] || "",
                     appId: props["application.id"] || "", pid: Number(props["application.process.id"] || 0) }
        }))
        return index >= 0 ? streams[index] : null
    }
    readonly property bool hasVolume: stream !== null || (active !== null && active.canControl && active.volumeSupported)
    readonly property real volume: stream && stream.audio ? stream.audio.volume : active && active.volumeSupported ? active.volume : 0
    readonly property bool muted: stream !== null && stream.audio !== null && stream.audio.muted

    function select(player) { selectedName = player ? player.dbusName : "" }
    function togglePlaying() { if (active && active.canTogglePlaying) active.togglePlaying() }
    function next() { if (active && active.canGoNext) active.next() }
    function previous() { if (active && active.canGoPrevious) active.previous() }
    function toggleShuffle() { if (canShuffle) active.shuffle = !active.shuffle }
    function cycleLoop() { if (canLoop) active.loopState = Logic.nextLoopState(active.loopState) }
    function setVolume(value) {
        if (stream) AudioService.setVolume(stream, value)
        else if (active && active.canControl && active.volumeSupported) active.volume = Math.max(0, Math.min(1, value))
    }
    function toggleMute() { if (stream) AudioService.toggleMute(stream) }
    function seekTo(ratio) {
        if (active && active.canSeek && active.lengthSupported && active.length > 0)
            active.position = Math.max(0, Math.min(1, ratio)) * active.length
    }

    function formatTime(seconds) {
        if (!seconds || seconds < 0) return "0:00"
        const total = Math.floor(seconds)
        return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0")
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.trackers > 0 && root.playing
        onTriggered: if (root.active) root.active.positionChanged()
    }
}
