pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import "bluetooth/BluetoothLogic.js" as Logic

// BlueZ adapter and devices. Discovery only runs while a page requests it.
Singleton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    // `!!`, not `!== null`: without an adapter Quickshell hands over
    // undefined as well, which got past the check and threw in every reader
    // of `adapter.name` (Settings > Bluetooth).
    readonly property bool available: !!adapter
    readonly property bool enabled: available && adapter.enabled
    readonly property var devices: available ? adapter.devices.values : []
    readonly property var connected: devices.filter(device => device.connected)
    readonly property var paired: devices.filter(device => !device.connected && (device.paired || device.bonded))
    // Unnamed devices only advertise their address; they are noise in the list.
    readonly property var nearby: devices.filter(device => !device.connected && !device.paired && !device.bonded
        && device.name && device.name.length && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(device.name))
    readonly property bool discovering: available && adapter.discovering

    readonly property string summary: !available ? "Unavailable"
        : !enabled ? "Off"
        : connected.length === 1 ? connected[0].name
        : connected.length > 1 ? connected.length + " devices connected" : "On"

    readonly property string icon: !enabled ? "󰂲" : connected.length ? "󰂱" : "󰂯"

    // ---- pairing agent (scripts/bluetooth-agent.py) --------------------------
    // The agent answers BlueZ pairing requests through PairingDialog. Nested
    // test sessions (sandboxed XDG_CONFIG_HOME) never register it, so the host
    // desktop keeps its own agent.
    readonly property bool agentAllowed: Quickshell.env("BUCHHWIN_NESTED") !== "1"
        && ((Quickshell.env("XDG_CONFIG_HOME") || "").length === 0
            || Quickshell.env("XDG_CONFIG_HOME") === Quickshell.env("HOME") + "/.config")
    // Only while a pairing can come in or is under way (BluetoothLogic.agentWanted).
    // It is a Python process of about 11 MB, and it used to idle through every
    // session - with Bluetooth off too - while BlueZ asks it nothing outside
    // a pairing.
    readonly property bool agentWanted: agentAllowed && available && Logic.agentWanted({
        enabled: enabled, viewers: discoveryViewers, discoverable: enabled && adapter.discoverable,
        grace: pairingGrace.running, pairing: devices.some(device => device.pairing),
        untrusted: devices.some(device => (device.paired || device.bonded) && !device.trusted),
        // A preview (IPC, screenshots) answers nothing and needs no agent.
        asking: (request !== null && request.preview !== true) || queue.length > 0
            || (displayCode !== null && displayCode.preview !== true)
    })
    property bool agentReady: false
    // Crash restarts pause the process through this flag so the `running`
    // binding survives; after five failures the agent stays off.
    property bool agentPaused: false
    property int agentFailures: 0
    // The shell stopped the agent (agentWanted went false while it ran).
    property bool agentStopAsked: false
    onAgentWantedChanged: {
        if (!agentWanted && agentProc.running) agentStopAsked = true
        watchAgentStart()
    }
    // Whether a view says "Pairing service is starting …": only once the
    // agent has been wanted and not ready for a while. It starts as a view
    // opens and is ready a fraction of a second later, and a caption bound
    // to `agentReady` alone came and went with every open, the popup's
    // height with it.
    readonly property bool agentStarting: agentAllowed && enabled && !agentReady && agentSlow
    property bool agentSlow: false
    function watchAgentStart() {
        if (agentWanted && !agentReady) {
            if (!agentSlow && !agentSlowTimer.running) agentSlowTimer.start()
        } else {
            agentSlowTimer.stop()
            agentSlow = false
        }
    }
    onAgentReadyChanged: watchAgentStart()
    Component.onCompleted: watchAgentStart()
    Timer { id: agentSlowTimer; interval: 1500; onTriggered: root.agentSlow = true }
    property var request: null            // { id, kind, name, passkey, preview }
    property var queue: []
    property var displayCode: null        // { name, passkey, device, … } shown without an answer

    function handleAgentLine(line) {
        let message = null
        try { message = JSON.parse(line) } catch (error) { return }
        if (message.kind === "ready") { agentReady = true; agentFailures = 0; return }
        if (message.kind === "error") { agentReady = false; return }
        if (message.kind === "display") {
            displayCode = Logic.displayFor(message, pairingStates)
            if (!request) PanelService.openOver("pairing")
            return
        }
        if (message.kind === "cancel") {
            if (message.id === undefined) {
                // BlueZ cancelled everything; queued requests are dead too.
                queue = []
                finishRequest()
            } else if (request && request.id === message.id) finishRequest()
            else queue = queue.filter(item => item.id !== message.id)
            displayCode = null
            return
        }
        if (message.id === undefined) return
        if (request) queue = queue.concat([message])
        else showRequest(message)
    }

    function showRequest(message) {
        request = message
        PanelService.openOver("pairing")
    }

    function respond(accept, value) {
        if (!request) return
        if (!request.preview && agentProc.running) {
            agentProc.write(JSON.stringify({ id: request.id, accept: accept, value: value || "" }) + "\n")
            // The agent stays for the rest of that pairing (pairingGrace). The
            // answer only leaves on the next turn of the event loop, while
            // the stop that the question's end could bring is a signal sent
            // at once: it would reach the agent first, and the agent would
            // cancel what the user had just accepted.
            pairingGrace.restart()
        }
        finishRequest()
    }

    function finishRequest() {
        request = null
        if (queue.length) {
            const next = queue[0]
            queue = queue.slice(1)
            showRequest(next)
        } else if (!displayCode) {
            PanelService.close("pairing")
        }
    }

    // Shows the dialog with sample data; answers never reach BlueZ.
    function previewPairing(kind) {
        const sample = { id: -1, kind: kind, name: "Example device", passkey: "482913", preview: true }
        if (kind === "display") {
            displayCode = { name: sample.name, passkey: sample.passkey, preview: true }
            PanelService.openOver("pairing")
        } else {
            showRequest(sample)
        }
    }

    Process {
        id: agentProc
        stderr: ErrorLog { label: "BluetoothService.agentProc" }
        running: root.agentWanted && !root.agentPaused
        command: [Paths.script("bluetooth-agent.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.handleAgentLine(data) }
        onRunningChanged: {
            if (running) { root.agentReady = false; return }
            root.agentReady = false
            if (root.request && !root.request.preview) root.finishRequest()
            // Switching Bluetooth off, or the last view closing, stops the
            // agent too; counted as a crash, that armed the backoff and the
            // next power-on waited for it (BluetoothLogic.agentStopped).
            const asked = root.agentStopAsked
            root.agentStopAsked = false
            const stop = Logic.agentStopped(root.agentFailures, root.agentWanted, root.agentPaused, asked)
            if (!stop) return
            root.agentFailures = stop.failures
            if (stop.retryIn < 0) return
            root.agentPaused = true
            agentRestart.interval = Math.max(1, stop.retryIn)
            agentRestart.restart()
        }
    }
    Timer {
        id: agentRestart
        onTriggered: root.agentPaused = false
    }

    function setEnabled(value) { if (available) adapter.enabled = value }

    // ---- discovery ----------------------------------------------------------
    // **Counted, not switched** (BluetoothLogic.discoveryStep). Every view
    // that lists nearby devices - the popup, the control center's page,
    // Settings - asks for discovery while it is on screen and lets go when it
    // leaves: `setDiscovering(true)` and `setDiscovering(false)` are one view
    // arriving and leaving, in pairs, as every caller already made them. A
    // plain switch let the last one out win, and the popup's "Bluetooth
    // settings" link ended the search under the page meant for pairing.
    // Settings' "Stop searching" is a false of its own; with the page as the
    // only viewer it ends the search as before, and the page's own false when
    // it closes finds nobody left to count down.
    property int discoveryViewers: 0

    function setDiscovering(value) {
        const step = Logic.discoveryStep(discoveryViewers, value, enabled,
                                         available && adapter.discovering)
        discoveryViewers = step.viewers
        if (step.start !== null) adapter.discovering = step.start
    }

    // An adapter switched on, or one that appears, while a view is open
    // starts searching then - the popup used to ask for that itself, with a
    // `setDiscovering(true)` that nothing ever paired. Only ever a start: an
    // adapter that comes up already searching for someone else (bluetoothctl)
    // is not this shell's to stop.
    onEnabledChanged: if (enabled && discoveryViewers > 0 && !adapter.discovering) adapter.discovering = true

    function setDiscoverable(value) { if (enabled) adapter.discoverable = value }
    function toggleConnection(device) {
        if (!device) return
        if (device.connected) device.disconnect()
        else if (device.paired || device.bonded) device.connect()
        else {
            pairingStarted = Logic.startPairing(pairingStarted, device.address)
            pairingGrace.restart()
            device.pair()
        }
    }

    // ---- after a pairing ------------------------------------------------------
    // Every listed device's pairing state in one list, so one handler hears
    // any of them change (BluetoothLogic.afterPairing, displayStep).
    readonly property var pairingStates: devices.map(device => ({
        address: device.address, path: device.dbusPath, paired: device.paired || device.bonded,
        pairing: device.pairing, connected: device.connected, trusted: device.trusted
    }))
    // Pairings this shell started, by address, until they are over.
    property var pairingStarted: ({})
    onPairingStatesChanged: settlePairing(true)

    // A pairing this shell started is trusted and connected once it has
    // paired; a code on screen goes once its device has paired.
    function settlePairing(grace) {
        if (Object.keys(pairingStarted).length) {
            const step = Logic.afterPairing(pairingStarted, pairingStates, grace)
            pairingStarted = step.started
            for (const address of step.trust) {
                const device = devices.find(item => String(item.address || "").toUpperCase() === address)
                if (!device) continue
                if (!device.trusted) device.trusted = true
                if (!device.connected) device.connect()
            }
        }
        if (displayCode && displayCode.device) {
            const shown = Logic.displayStep(displayCode, pairingStates)
            if (shown.done) {
                displayCode = null
                if (!request) PanelService.close("pairing")
            } else if (shown.display !== displayCode) {
                displayCode = shown.display
            }
        }
    }

    // How long a pairing this shell started may take to begin and end: the
    // agent stays up for it, and a pairing never seen is forgotten after.
    // An answer to the agent (respond) starts it again.
    Timer {
        id: pairingGrace
        interval: 90000
        onTriggered: root.settlePairing(false)
    }
    function forget(device) { if (device) device.forget() }

    function deviceIcon(device) {
        const icon = device ? (device.icon || "") : ""
        if (icon.includes("headset") || icon.includes("headphone")) return "󰋋"
        if (icon.includes("audio")) return "󰓃"
        if (icon.includes("keyboard")) return "󰌌"
        if (icon.includes("mouse")) return "󰍽"
        if (icon.includes("phone")) return "󰏲"
        if (icon.includes("gaming") || icon.includes("joystick")) return "󰊴"
        if (icon.includes("computer")) return "󰟀"
        return "󰂯"
    }

    function deviceStatus(device) {
        if (!device) return ""
        if (device.pairing) return "Pairing …"
        const battery = device.batteryAvailable ? " · " + Math.round(device.battery * 100) + "%" : ""
        if (device.connected) return "Connected" + battery
        if (device.paired || device.bonded) return "Paired"
        return "Nearby"
    }
}
