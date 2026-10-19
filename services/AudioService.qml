pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import "audio/AudioRoutingLogic.js" as Routing
import "audio/AudioLabelLogic.js" as Labels
import "audio/MicLogic.js" as MicLogic

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
                                                       && !Routing.isShellCapture(node.name))
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

    // The label as a row shows it, { title, subtitle }: the port as the
    // title ("Speaker", "Digital Microphone") and the card under it, so the
    // part that tells two devices apart is not the part a narrow row cuts
    // off (AudioLabelLogic). `list` is the node's own list, sinks or sources.
    function labelParts(node, list) {
        if (!node) return { title: label(node), subtitle: "" }
        const props = node.properties || {}
        const others = Array.prototype.slice.call(list || []).filter(other => other !== node).map(other => label(other))
        return Labels.split(label(node), props["device.profile.description"] || "", others)
    }
    // The device on a line of its own beside a state ("In use · Digital
    // Microphone"): the port where the card goes without saying, else the
    // whole label (AudioLabelLogic.shortName).
    function shortLabel(node, list) {
        if (!node) return label(node)
        const props = node.properties || {}
        const others = Array.prototype.slice.call(list || []).filter(other => other !== node).map(other => label(other))
        return Labels.shortName(label(node), props["device.profile.description"] || "", others)
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

    // One step of a volume key (shell.qml's audio up/down): `delta` added to
    // the node's volume, within 0 and 1 as `wpctl set-volume -l 1.0` keeps
    // it, and the mute left alone, as wpctl leaves it. False while the node
    // is not bound, so the caller can hand the key to wpctl.
    function stepVolume(node, delta) {
        if (!node || !node.audio) return false
        node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + Number(delta)))
        return true
    }

    // ---- the microphone key: every microphone (MicLogic.plan) ----------------
    // The key muted the default input alone, and an app that had opened
    // another microphone (the laptop's own beside a headset) stayed live. Now
    // a press mutes every microphone, and the next one turns back on the
    // ones it muted and the default. With a single microphone, or with
    // Settings > Audio's switch off, it toggles the default as it always did.
    // The other microphones are bound for the press only (a bound node
    // reports its changes; nothing needs them otherwise): the press asks for
    // them, waits until they are ready - a few milliseconds, at most
    // `micKeyWait` - and lets them go a moment after.
    readonly property bool micKeyAll: SettingsService.value("audio.micKeyAll") !== false
    // After a press with more than one microphone: `muted` what it did,
    // `changed` how many it turned on again, `total` how many there are
    // (the OSD's "All microphones muted").
    signal microphonesSet(bool muted, int changed, int total)
    property bool micKeyBinding: false
    property bool micKeyPending: false
    property int micKeyTries: 0
    readonly property int micKeyWait: 600
    // The microphones the last press muted, by node name (an id is not kept
    // across a reconnect, a name is).
    property var micMutedByKey: []

    function micKey() {
        if (!micKeyAll || sources.length <= 1) {
            if (source && source.audio) toggleMute(source)
            else Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
            return
        }
        micKeyRelease.stop()
        micKeyBinding = true
        if (micKeyPending) return
        micKeyPending = true
        micKeyTries = 0
        // Bound already (a panel that shows them is open): at once.
        if (sources.every(node => node.ready && node.audio)) applyMicKey()
        else micKeyStep.restart()
    }
    function applyMicKey() {
        micKeyPending = false
        micKeyStep.stop()
        const list = sources.slice()
        // A node that is not bound yet reads as live (MicLogic.plan), so it
        // is muted rather than left open for not knowing.
        const step = MicLogic.plan(list.map(node => ({
            name: node.name || "", muted: node.ready && node.audio ? node.audio.muted : undefined
        })), source ? source.name || "" : "", micMutedByKey)
        micMutedByKey = step.remember
        for (const change of step.changes) {
            const node = list.find(item => (item.name || "") === change.name)
            if (!node) continue
            if (node.ready && node.audio) node.audio.muted = change.muted
            else Quickshell.execDetached(["wpctl", "set-mute", String(node.id), change.muted ? "1" : "0"])
        }
        microphonesSet(step.mute, step.mute ? 0 : step.changes.length, list.length)
        micKeyRelease.restart()
    }
    Timer {
        id: micKeyStep
        interval: 40
        repeat: true
        onTriggered: {
            root.micKeyTries += 1
            const ready = root.sources.every(node => node.ready && node.audio)
            if (ready || root.micKeyTries * interval >= root.micKeyWait) root.applyMicKey()
        }
    }
    Timer { id: micKeyRelease; interval: 2000; onTriggered: root.micKeyBinding = false }

    // ---- push to talk (MicLogic.talkStep) ------------------------------------
    // A key held turns the default microphone on, letting go puts it back the
    // way it was: muted again when the key turned it on, left on when it was
    // on before. A release the shell never hears cannot leave the microphone
    // on for good: the microphone's display stays on screen while the hold
    // lasts (Osd), the next press ends it, and so does MicLogic.TALK_LIMIT_MS.
    property bool talking: false
    property var talkState: ({ talking: false, restore: false })
    // The microphone the press turned on: a headset plugged in while the key
    // is held does not move the release to another one.
    property var talkNode: null
    function pushToTalk(down) {
        // A press while held ends the hold on the microphone it holds: the
        // shell missed a release (MicLogic.talkStep).
        const starting = down === true && !talkState.talking
        const node = starting ? source : talkNode
        const audio = node && node.audio ? node.audio : null
        if (starting && !audio) return
        const step = MicLogic.talkStep(talkState, down === true, audio ? audio.muted : false)
        talkState = step.state
        talking = step.state.talking
        talkNode = talking ? node : null
        if (talking) talkLimit.restart()
        else talkLimit.stop()
        if (step.set !== null && audio) audio.muted = step.set
    }
    Timer { id: talkLimit; interval: MicLogic.TALK_LIMIT_MS; onTriggered: root.pushToTalk(false) }

    function setDefaultSink(node) { if (node) Pipewire.preferredDefaultAudioSink = node }
    function setDefaultSource(node) { if (node) Pipewire.preferredDefaultAudioSource = node }

    // Binding a node is what fills in its `properties` and its live volume
    // and mute; its name, description, type and stream flag are there
    // without it. The default output and input are bound all the time (the
    // bar, the OSD, the notch and the mic tile follow them), every other
    // device and app stream only while something shows it: a bound stream
    // reports every property and parameter change for nothing otherwise.
    // Demand comes from the counters pages already hold - a stream row with
    // its output selector (routing), Settings > Audio (the meter), the media
    // player's volume (MprisService takes trackNodes) - and from the panels
    // whose own rows take none: the volume and privacy popups and the
    // control center's audio card. `micInUse` reads only the stream flags
    // and names, so the mic indicators need no binding.
    property int nodeTrackers: 0
    function trackNodes() { nodeTrackers += 1 }
    function untrackNodes() { nodeTrackers = Math.max(0, nodeTrackers - 1) }
    readonly property var nodePanels: ["volumePopup", "privacyPopup", "controlCenter"]
    readonly property bool nodesWanted: nodeTrackers > 0 || routingTrackers > 0 || meterTrackers > 0
        || nodePanels.indexOf(PanelService.active) >= 0
    // Released a moment after the last one leaves: a panel's `active` ends
    // where its close animation starts, and the rows still on screen then
    // must not lose their values; a quick reopen also binds nothing again.
    property bool nodesBound: false
    onNodesWantedChanged: {
        if (nodesWanted) {
            nodeRelease.stop()
            nodesBound = true
        } else {
            nodeRelease.restart()
        }
    }
    Component.onCompleted: nodesBound = nodesWanted
    Timer { id: nodeRelease; interval: 2000; onTriggered: root.nodesBound = root.nodesWanted }

    PwObjectTracker {
        objects: {
            const list = root.nodesBound ? root.sinks.concat(root.sources, root.playbackStreams, root.captureStreams)
                : root.micKeyBinding ? root.sources.slice() : []
            for (const node of [root.sink, root.source]) {
                if (node && list.indexOf(node) < 0) list.push(node)
            }
            return list
        }
    }

    Process {
        id: metadataMonitor
        stderr: ErrorLog { label: "AudioService.metadataMonitor" }
        running: root.routingTrackers > 0 && root.ready && !root.routingPaused
        command: Paths.bound(["pw-metadata", "-m", "-n", "default"])
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
