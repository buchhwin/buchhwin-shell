pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// Wi-Fi through Quickshell.Networking (NetworkManager). VPN connections and
// addresses come from nmcli, refreshed only when `nmcli monitor` reports a
// change.
Singleton {
    id: root
    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    readonly property bool wifiAvailable: wifiDevice !== null && Networking.wifiHardwareEnabled
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var networks: {
        if (!wifiDevice) return []
        const seen = {}
        return wifiDevice.networks.values
            .filter(network => network.name && network.name.length && !seen[network.name] && (seen[network.name] = true))
            .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    }
    readonly property var current: networks.find(network => network.connected) || null
    readonly property bool connected: current !== null || wiredConnected
    property bool wiredConnected: false
    property var connections: []       // [{ name, uuid, type, active, device }]
    readonly property var vpns: connections.filter(item => item.type === "vpn" || item.type === "wireguard")
    readonly property var activeVpns: vpns.filter(item => item.active)
    property string address: ""

    readonly property string summary: !wifiEnabled && !wiredConnected ? "Off"
        : current ? current.name : wiredConnected ? "Wired" : "Not connected"

    function signalIcon(strength) {
        if (strength === undefined) return "󰤨"
        return strength > 0.75 ? "󰤨" : strength > 0.5 ? "󰤥" : strength > 0.25 ? "󰤢" : "󰤟"
    }

    readonly property string icon: !wifiEnabled && !wiredConnected ? "󰤮"
        : wiredConnected && !current ? "󰈀"
        : current ? signalIcon(current.signalStrength) : "󰤯"

    // ---- secured networks and hotspot (scripts/network-helper.py) -----------
    // Secrets go to the helper on stdin, never as process arguments.
    property string helperState: ""        // "", "connecting", "hotspot"
    property string helperError: ""
    property string pendingSsid: ""
    property string pendingSecret: ""
    property bool hotspotActive: false

    function isOpen(network) { return network !== null && network.security === WifiSecurityType.Open }
    function isEnterprise(network) {
        return network !== null && [WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap, WifiSecurityType.Wpa3SuiteB192,
                                    WifiSecurityType.Leap, WifiSecurityType.DynamicWep].indexOf(network.security) >= 0
    }
    function securityLabel(network) {
        if (!network) return ""
        if (isOpen(network) || network.security === WifiSecurityType.Owe) return "Open"
        if (network.security === WifiSecurityType.Sae) return "WPA3"
        if (network.security === WifiSecurityType.StaticWep) return "WEP"
        if (isEnterprise(network)) return "Enterprise (802.1X)"
        return "WPA2"
    }

    // Click on a network row: disconnect, reconnect, or ask for a password.
    // `returnArgs` reopens the calling panel page after the dialog.
    function activate(network, returnArgs) {
        if (!network) return
        if (network.connected) disconnectNetwork(network)
        else if (network.known || isOpen(network) || network.security === WifiSecurityType.Owe) connectNetwork(network)
        else if (isEnterprise(network)) openSystemDialog()
        else {
            helperError = ""
            PanelService.openOver("wifiPassword", { ssid: network.name, security: securityLabel(network) }, returnArgs)
        }
    }

    function connectWithPassword(ssid, secret, hidden) {
        if (helperProc.running || !ssid.length) return false
        helperError = ""
        helperState = "connecting"
        pendingSsid = ssid
        pendingSecret = secret
        helperProc.command = [Paths.script("network-helper.py"), "connect", "--ssid=" + ssid].concat(hidden ? ["--hidden"] : [])
        helperProc.running = true
        return true
    }

    function startHotspot(ssid, secret) {
        if (helperProc.running) return false
        helperError = ""
        helperState = "hotspot"
        pendingSecret = secret
        helperProc.command = [Paths.script("network-helper.py"), "hotspot-start", "--ssid=" + ssid]
        helperProc.running = true
        return true
    }

    // It used to be fired off detached and the hotspot marked as gone the same
    // instant, whatever the helper did with it: a failure read as a success and
    // the state only came back at the next refresh.
    function stopHotspot() {
        if (helperProc.running) return false
        helperError = ""
        helperState = "hotspot-stop"
        helperProc.command = [Paths.script("network-helper.py"), "hotspot-stop"]
        helperProc.running = true
        return true
    }

    Process {
        id: helperProc
        stderr: ErrorLog { label: "NetworkService.helperProc" }
        stdinEnabled: true
        onStarted: {
            write(root.pendingSecret + "\n")
            root.pendingSecret = ""
            stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let answer = null
                try { answer = JSON.parse(text.trim().split("\n").pop() || "{}") } catch (error) { answer = null }
                const state = root.helperState
                root.helperState = ""
                if (answer && answer.ok) {
                    root.helperError = ""
                    if (state === "hotspot") root.hotspotActive = true
                    if (state === "hotspot-stop") root.hotspotActive = false
                    if (PanelService.isOpen("wifiPassword")) PanelService.close("wifiPassword")
                } else {
                    root.helperError = answer && answer.error === "enterprise" ? answer.message
                        : answer && answer.error ? answer.error : "Action failed"
                }
                root.refresh()
            }
        }
        onExited: stdinEnabled = true
    }

    Process {
        id: hotspotStatusProc
        stderr: ErrorLog { label: "NetworkService.hotspotStatusProc" }
        command: [Paths.script("network-helper.py"), "hotspot-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hotspotActive = JSON.parse(text).active === true } catch (error) { root.hotspotActive = false }
            }
        }
    }

    function setWifiEnabled(enabled) { Networking.wifiEnabled = enabled }
    function setScanning(enabled) { if (wifiDevice) wifiDevice.scannerEnabled = enabled }
    function connectNetwork(network) { if (network) network.connect() }
    function disconnectNetwork(network) { if (network) network.disconnect() }
    function forget(network) { if (network) network.forget() }

    // KDE's editor for enterprise networks and VPN profiles.
    function openSystemDialog() {
        Quickshell.execDetached(["kcmshell6", "kcm_networkmanagement"])
        PanelService.close()
    }

    function setVpn(uuid, up) {
        Quickshell.execDetached(["nmcli", "connection", up ? "up" : "down", "uuid", uuid])
    }

    // nmcli -t escapes ':' inside values as '\:'.
    function splitTerse(line) {
        const fields = []
        let currentField = ""
        for (let i = 0; i < line.length; ++i) {
            const char = line[i]
            if (char === "\\" && i + 1 < line.length) { currentField += line[++i]; continue }
            if (char === ":") { fields.push(currentField); currentField = ""; continue }
            currentField += char
        }
        fields.push(currentField)
        return fields
    }

    function refresh() {
        if (!connectionsProc.running) connectionsProc.running = true
        if (!hotspotStatusProc.running) hotspotStatusProc.running = true
    }

    Process {
        id: connectionsProc
        stderr: ErrorLog { label: "NetworkService.connectionsProc" }
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = []
                let wired = false
                let device = ""
                for (const line of text.split("\n")) {
                    if (!line.length) continue
                    const [name, uuid, type, dev, active] = root.splitTerse(line)
                    const shortType = type.replace("802-11-wireless", "wifi").replace("802-3-ethernet", "ethernet")
                    const isActive = active === "yes"
                    result.push({ name: name, uuid: uuid, type: shortType, device: dev, active: isActive })
                    if (isActive && shortType === "ethernet") wired = true
                    if (isActive && (shortType === "wifi" || shortType === "ethernet") && !device.length) device = dev
                }
                root.connections = result
                root.wiredConnected = wired
                if (device.length) {
                    addressProc.command = ["nmcli", "-t", "-g", "IP4.ADDRESS", "device", "show", device]
                    addressProc.running = true
                } else {
                    root.address = ""
                }
            }
        }
    }

    Process {
        id: addressProc
        stderr: ErrorLog { label: "NetworkService.addressProc" }
        stdout: StdioCollector { onStreamFinished: root.address = text.split("\n")[0].split(" | ")[0].trim() }
    }

    Process {
        id: monitorProc
        stderr: ErrorLog { label: "NetworkService.monitorProc" }
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: debounce.restart() }
        onRunningChanged: if (!running) restartTimer.start()
    }
    Timer {
        id: restartTimer
        interval: 5000
        onTriggered: {
            root.refresh()
            monitorProc.running = true
        }
    }
    Timer { id: debounce; interval: 400; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
