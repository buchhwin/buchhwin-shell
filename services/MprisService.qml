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
    // consumer. A data: url is handed straight through; an http(s) one is
    // fetched (below); only a path can be checked, and only a path goes stale.
    readonly property string rawArtUrl: active ? (active.trackArtUrl || "") : ""
    property string artUrl: ""

    function localPath(url) {
        const text = String(url || "")
        if (text.indexOf("file://") !== 0) return ""
        // A bare "%" in a file name is a malformed escape and throws; the
        // undecoded path is the better guess then.
        try { return decodeURIComponent(text.slice(7)) } catch (error) { return text.slice(7) }
    }

    // Remote art is fetched by curl into the cache and consumers load the file.
    // Qt's own HTTP/2 client fails against Spotify's image CDN (the shell log:
    // "qt.network.http2.connection: HEADERS on invalid stream", then every
    // Image bound to the url shows nothing and the record has no label);
    // curl is told --http1.1 and never sees the problem. One fetch per track
    // change, here, not one per Image. Covers older than 30 days are swept
    // from the directory with the first fetch of a session.
    readonly property string coverDir: Paths.cacheDir + "/covers"
    property bool coversSwept: false
    function remote(url) { return /^https?:\/\//.test(String(url || "")) }

    function checkArt() {
        // The value is read here and not through a property bound to the same
        // thing: a change handler is not promised that a derived binding has
        // caught up, which this project has already paid for once.
        const url = rawArtUrl
        const path = localPath(url)
        if (!remote(url) && !path.length) {
            artUrl = url
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
        if (remote(url)) {
            const file = coverDir + "/" + Qt.md5(url) + ".img"
            const sweep = coversSwept ? "" : 'find "$1" -type f -mtime +30 -delete 2>/dev/null; '
            coversSwept = true
            artCheck.command = ["sh", "-c",
                'mkdir -p -- "$1" && ' + sweep
                + '{ test -s "$2" || { curl -fsSL --http1.1 --max-time 15 -o "$2.part" -- "$3" && mv -f -- "$2.part" "$2"; }; }',
                "sh", coverDir, file, url]
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
            root.artUrl = code === 0 ? artCheck.pending : ""
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
