pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

// BlueZ adapter and devices. Discovery only runs while a page requests it.
Singleton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
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
    property bool agentReady: false
    // Crash restarts pause the process through this flag so the `running`
    // binding survives; after five failures the agent stays off.
    property bool agentPaused: false
    property int agentFailures: 0
    property var request: null            // { id, kind, name, passkey, preview }
    property var queue: []
    property var displayCode: null        // { name, passkey } shown without an answer

    function handleAgentLine(line) {
        let message = null
        try { message = JSON.parse(line) } catch (error) { return }
        if (message.kind === "ready") { agentReady = true; agentFailures = 0; return }
        if (message.kind === "error") { agentReady = false; return }
        if (message.kind === "display") {
            displayCode = { name: message.name, passkey: message.passkey }
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
        if (!request.preview && agentProc.running)
            agentProc.write(JSON.stringify({ id: request.id, accept: accept, value: value || "" }) + "\n")
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
            displayCode = { name: sample.name, passkey: sample.passkey }
            PanelService.openOver("pairing")
        } else {
            showRequest(sample)
        }
    }

    Process {
        id: agentProc
        stderr: ErrorLog { label: "BluetoothService.agentProc" }
        running: root.agentAllowed && root.available && !root.agentPaused
        command: [Paths.script("bluetooth-agent.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.handleAgentLine(data) }
        onRunningChanged: {
            if (running) { root.agentReady = false; return }
            root.agentReady = false
            if (root.request && !root.request.preview) root.finishRequest()
            if (!root.agentAllowed || !root.available || root.agentPaused) return
            root.agentFailures += 1
            if (root.agentFailures > 5) return
            root.agentPaused = true
            agentRestart.interval = 5000 * Math.pow(2, root.agentFailures - 1)
            agentRestart.restart()
        }
    }
    Timer {
        id: agentRestart
        onTriggered: root.agentPaused = false
    }

    function setEnabled(value) { if (available) adapter.enabled = value }
    function setDiscovering(value) { if (enabled) adapter.discovering = value }
    function setDiscoverable(value) { if (enabled) adapter.discoverable = value }
    function toggleConnection(device) {
        if (!device) return
        if (device.connected) device.disconnect()
        else if (device.paired || device.bonded) device.connect()
        else device.pair()
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
