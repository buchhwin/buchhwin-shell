pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import "audio/AudioRoutingLogic.js" as Routing

// PipeWire devices and application streams, per-app output routing and the
// microphone level meter of Settings > Audio.
Singleton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(node => !node.isStream && hasType(node, PwNodeType.AudioSink))
    readonly property var sources: nodes.filter(node => !node.isStream && hasType(node, PwNodeType.AudioSource)
                                                && !(node.name || "").endsWith(".monitor"))
    readonly property var playbackStreams: nodes.filter(node => node.isStream && hasType(node, PwNodeType.AudioOutStream))
    // The level meter's own recording stream does not count as "in use".
    readonly property var captureStreams: nodes.filter(node => node.isStream && hasType(node, PwNodeType.AudioInStream)
                                                       && !Routing.isMeterStream(node.name))
    readonly property bool ready: Pipewire.ready
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
    readonly property bool micMuted: source && source.audio ? source.audio.muted : true
    readonly property real micVolume: source && source.audio ? source.audio.volume : 0
    readonly property bool micInUse: captureStreams.length > 0

    // Routing: the "default" metadata entries, kept current by `pw-metadata -m`
    // while a page tracks them (app streams with their output selector).
    property int routingTrackers: 0
    property bool routingPaused: false
    property var routes: ({})
    readonly property var sinkInfo: sinks.map(node => ({
        id: node.id, name: node.name || "", label: label(node),
        serial: node.properties ? node.properties["object.serial"] : undefined
    }))
    readonly property var outputOptions: Routing.outputOptions(sinkInfo, "Default output")

    // Level meter: scripts/audio-level.py while a page tracks it. Nothing is
    // stored; it measures the default input and follows it when it changes.
    property int meterTrackers: 0
    property bool meterPaused: false
    property real inputLevel: 0
    property real inputPeak: 0
    readonly property bool meterRunning: levelProc.running

    function trackRouting() { routingTrackers += 1 }
    function untrackRouting() { routingTrackers = Math.max(0, routingTrackers - 1) }
    function trackMeter() { meterTrackers += 1 }
    function untrackMeter() { meterTrackers = Math.max(0, meterTrackers - 1) }

    // node.name of the sink the stream is pinned to, "" for the default output.
    function streamTarget(node) {
        return node ? Routing.streamTarget(routes, node.id, sinkInfo) : ""
    }

    // WirePlumber moves the stream and remembers the choice for the app.
    function routeStream(node, sinkName) {
        if (!node || !node.isStream) return
        const commands = sinkName.length
            ? [Routing.moveCommand(node.id, sinkInfo.find(sink => sink.name === sinkName))]
            : Routing.resetCommands(routes, node.id)
        for (const command of commands) {
            if (command.length) Quickshell.execDetached(command)
        }
    }

    function hasType(node, flag) {
        return node && (node.type & flag) === flag
    }

    function label(node) {
        if (!node) return "No device"
        return node.description || node.nickname || node.name || "Audio device"
    }

    function streamLabel(node) {
        if (!node) return ""
        const props = node.properties || {}
        return props["application.name"] || node.description || node.name || "Application"
    }

    function streamIcon(node) {
        const props = node && node.properties ? node.properties : {}
        return props["application.icon-name"] || ""
    }

    function deviceIcon(node, input) {
        const text = ((node && (node.description || node.name)) || "").toLowerCase()
        if (input) return text.includes("headset") ? "󰋎" : "󰍬"
        if (text.includes("headphone") || text.includes("headset") || text.includes("kopfhörer")) return "󰋋"
        if (text.includes("hdmi") || text.includes("displayport")) return "󰡁"
        if (text.includes("bluetooth") || text.includes("bluez")) return "󰂰"
        return "󰓃"
    }

    function volumeIcon(value, isMuted) {
        if (isMuted || value <= 0.001) return "󰝟"
        return value < 0.34 ? "󰕿" : value < 0.67 ? "󰖀" : "󰕾"
    }

    function setVolume(node, value) {
        if (!node || !node.audio) return
        node.audio.volume = Math.max(0, Math.min(1, value))
        if (value > 0 && node.audio.muted) node.audio.muted = false
    }

    function toggleMute(node) {
        if (node && node.audio) node.audio.muted = !node.audio.muted
    }

    function setDefaultSink(node) { if (node) Pipewire.preferredDefaultAudioSink = node }
    function setDefaultSource(node) { if (node) Pipewire.preferredDefaultAudioSource = node }

    PwObjectTracker {
        objects: root.sinks.concat(root.sources, root.playbackStreams, root.captureStreams)
    }

    Process {
        id: metadataMonitor
        stderr: ErrorLog { label: "AudioService.metadataMonitor" }
        running: root.routingTrackers > 0 && root.ready && !root.routingPaused
        command: ["pw-metadata", "-m", "-n", "default"]
        stdout: SplitParser { onRead: data => root.routes = Routing.applyLine(root.routes, data) }
        onRunningChanged: {
            if (running) return
            root.routes = ({})
            // Exited on its own (e.g. PipeWire restarted): start again shortly.
            if (root.routingTrackers > 0 && root.ready) { root.routingPaused = true; routingRetry.restart() }
        }
    }

    Timer { id: routingRetry; interval: 2000; onTriggered: root.routingPaused = false }

    Process {
        id: levelProc
        stderr: ErrorLog { label: "AudioService.levelProc" }
        running: root.meterTrackers > 0 && root.ready && !root.meterPaused
        command: [Paths.script("audio-level.py")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const sample = JSON.parse(data)
                    root.inputLevel = Number(sample.level) || 0
                    root.inputPeak = Number(sample.peak) || 0
                } catch (error) {}
            }
        }
        onRunningChanged: {
            if (running) return
            root.inputLevel = 0
            root.inputPeak = 0
            if (root.meterTrackers > 0 && root.ready) { root.meterPaused = true; meterRetry.restart() }
        }
    }

    Timer { id: meterRetry; interval: 3000; onTriggered: root.meterPaused = false }
}
