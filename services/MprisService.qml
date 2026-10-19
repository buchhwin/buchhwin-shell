pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "media/MediaLogic.js" as Logic
import "media/VisualizerLogic.js" as Visualizer

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
    // consumer. A data: url is handed straight through; an http(s) one is
    // fetched (below); only a path can be checked, and only a path goes stale.
    // Any other scheme is no cover (MediaLogic.artKind): handed on, Qt itself
    // would fetch it in every consumer, the lock screen included.
    readonly property string rawArtUrl: active ? (active.trackArtUrl || "") : ""
    property string artUrl: ""

    // Remote art is fetched by curl into the cache and consumers load the file.
    // Qt's own HTTP/2 client fails against Spotify's image CDN (the shell log:
    // "qt.network.http2.connection: HEADERS on invalid stream", then every
    // Image bound to the url shows nothing and the record has no label);
    // curl is told --http1.1 and never sees the problem. One fetch per track
    // change, here, not one per Image. Covers older than 30 days are swept
    // from the directory with the first fetch of a session, and the cache is
    // kept to its newest 200 covers and 100 MB. A cover is a picture, not a
    // download: curl takes http(s) only, three redirects at most, stops past
    // 20 MB (or at 15 s), and a fetch that fails leaves no part file behind
    // for the sweep. The directory and its files are the user's alone
    // (MediaLogic.coverCommand).
    readonly property string coverDir: Paths.cacheDir + "/covers"
    property bool coversSwept: false

    function checkArt() {
        // The value is read here and not through a property bound to the same
        // thing: a change handler is not promised that a derived binding has
        // caught up, which this project has already paid for once.
        const url = rawArtUrl
        const kind = Logic.artKind(url)
        const path = Logic.artPath(url)
        if (kind === "data" || kind === "none" || (kind === "file" && !path.length)) {
            artUrl = kind === "data" ? url : ""
            return
        }
        artUrl = ""
        // A check still running belongs to an older track: it is stopped and
        // this one starts once it has exited. Stopped and started in the same
        // turn, the new run could be lost, and the stopped curl's failure was
        // judged as the new track's - no cover after a skip.
        if (artCheck.running) {
            artCheck.stale = true
            artCheck.running = false
            return
        }
        artCheck.stale = false
        artCheck.pending = url
        if (kind === "remote") {
            const file = coverDir + "/" + Qt.md5(url) + ".img"
            artCheck.command = Logic.coverCommand(coverDir, file, url, !coversSwept)
            coversSwept = true
            artCheck.file = file
        } else {
            artCheck.file = ""
            artCheck.command = ["test", "-r", path]
        }
        artCheck.running = true
    }
    onRawArtUrlChanged: checkArt()
    Component.onCompleted: checkArt()

    Process {
        id: artCheck
        // Which url this answer belongs to, taken when the run starts; a slow
        // answer must not overwrite the art of a track that has already started.
        property string pending: ""
        // The cached file a remote url was fetched to; empty for a local path.
        property string file: ""
        // Stopped for a newer track, which starts once this run is gone.
        property bool stale: false
        onExited: code => {
            if (artCheck.stale) {
                Qt.callLater(root.checkArt)
                return
            }
            if (root.rawArtUrl !== artCheck.pending) return
            if (artCheck.file.length) {
                // Fetched: the file. Not fetched (offline, odd CDN): no
                // cover. Handing the url on put Qt's HTTP/2 client back in
                // the path this fetch exists to keep it out of (pitfall 28).
                root.artUrl = code === 0 ? "file://" + artCheck.file : ""
                return
            }
            root.artUrl = code === 0 ? Logic.artFileUrl(artCheck.pending) : ""
        }
    }
    readonly property bool playing: active !== null && active.isPlaying
    readonly property bool canShuffle: active !== null && active.canControl && active.shuffleSupported
    readonly property bool canLoop: active !== null && active.canControl && active.loopSupported
    // The PipeWire stream playing this player's audio (for its volume), else
    // null; players without a matching stream may offer MPRIS volume instead.
    // It is matched by the streams' properties, which a node only has while
    // AudioService binds it, and only the media popup and the control center
    // read it - both trackers. So it is looked for, and the streams are asked
    // for, only while one of them is open; before, every stream's properties
    // were read again on every change of any of them.
    readonly property bool streamWanted: trackers > 0
    onStreamWantedChanged: {
        if (streamWanted) AudioService.trackNodes()
        else AudioService.untrackNodes()
    }
    readonly property var stream: {
        if (!active || !streamWanted) return null
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
    // A player's length when it is a real one, else 0 (MediaLogic.realLength):
    // a live stream reports none, zero or INT64_MAX µs, and every consumer
    // asks here rather than trusting `length > 0` on its own - which let the
    // last of those through as a remaining time of 153 million minutes.
    function lengthOf(player) {
        return player ? Logic.realLength(player.lengthSupported, player.length) : 0
    }
    readonly property real trackLength: lengthOf(active)
    // There is a track to seek along: a length worth drawing a bar for.
    readonly property bool hasLength: trackLength > 0
    function seekTo(ratio) {
        if (active && active.canSeek && hasLength)
            active.position = Math.max(0, Math.min(1, ratio)) * trackLength
    }

    // m:ss, or h:mm:ss for a track of an hour or more (pass its length as
    // `reference`, so elapsed and remaining keep one shape).
    function formatTime(seconds, reference) {
        return Logic.formatTime(seconds, reference)
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.trackers > 0 && root.playing
        onTriggered: if (root.active) root.active.positionChanged()
    }

    // ---- the visualizer (VisualizerLogic) -----------------------------------
    // cava runs while the media popup shows the bars (it counts itself with
    // the switch on) and something plays; a pause or the popup closing ends
    // it. One frame per line, `visualizerBars` heights from 0 to 1.
    property int visualizerTrackers: 0
    // cava is not installed: noted once, so a popup does not try it on every
    // open; the next shell start looks again.
    property bool visualizerMissing: false
    property var visualizerBars: []
    readonly property bool visualizerRunning: visualizerProc.running
    readonly property bool visualizerWanted: Visualizer.wanted(visualizerTrackers, playing, visualizerMissing)
    // Named after the cache, so a nested session's configuration is its own.
    readonly property string visualizerConfig: Paths.runtimeDir + "/visualizer-" + Qt.md5(Paths.cacheDir).slice(0, 8) + ".conf"
    onVisualizerWantedChanged: if (!visualizerWanted) visualizerBars = []
    // For `widgets visualizer` over IPC.
    function visualizerStatus() {
        return { trackers: visualizerTrackers, wanted: visualizerWanted, running: visualizerRunning,
                 missing: visualizerMissing, bars: visualizerBars.length,
                 peak: visualizerBars.reduce((top, value) => Math.max(top, value), 0) }
    }

    Process {
        id: visualizerProc
        running: root.visualizerWanted
        command: Paths.bound(Visualizer.command(root.visualizerConfig, Visualizer.config(Visualizer.BARS, Visualizer.FRAMERATE)))
        stdout: SplitParser { onRead: data => root.visualizerBars = Visualizer.parseFrame(data, Visualizer.BARS) }
        onExited: code => {
            if (code === 127) root.visualizerMissing = true
            root.visualizerBars = []
        }
    }
}
