pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import "network/WireguardLogic.js" as WireguardLogic

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

    // The bars glyph (NetworkWidget, `options.glyph: "bars"`): of `total`, how
    // many are lit. Every one when wired, none when off or not connected, and
    // never none while connected.
    function signalBars(total) {
        if (!wifiEnabled && !wiredConnected) return 0
        if (current) return Math.max(1, Math.min(total, Math.ceil(Number(current.signalStrength || 0) * total)))
        return wiredConnected ? total : 0
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
    // Every network view - the popup, the control-center page, the settings
    // page - turns scanning on when it comes into view and off when it goes,
    // so this is also where the service learns that someone is looking.
    // Those views are the only readers of `hotspotActive`, and reading it
    // means running a python helper; with nobody looking it is left to the
    // next open (read at once then) rather than run on every NetworkManager
    // event of an idle session. A hotspot this shell started is the
    // exception: it can go down on its own, so it keeps being read.
    property bool viewOpen: false
    // The connection network-helper.py starts and asks about (HOTSPOT_ID).
    // Its showing up active in nmcli's list is when a view-less read is due:
    // a hotspot up before this shell, or started outside it.
    readonly property string hotspotName: "buchhwin-hotspot"
    property bool hotspotListed: false
    function setScanning(enabled) {
        viewOpen = enabled
        if (wifiDevice) wifiDevice.scannerEnabled = enabled
        if (enabled) refreshHotspot()
    }
    function refreshHotspot() { if (!hotspotStatusProc.running) hotspotStatusProc.running = true }
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

    // ---- WireGuard tunnels (scripts/wireguard-helper.py) --------------------
    // Added as the user's own NetworkManager connections, which need no
    // administrator password and which Plasma lists as well - one
    // NetworkManager, the same tunnels in both sessions. Keys go to the helper
    // on stdin, never as arguments; the private key a "Generate" makes is held
    // here only until the form takes it.
    property string wgState: ""          // "", "generating", "adding", "deleting"
    property string wgError: ""
    property string wgNotice: ""
    property string wgPrivate: ""
    property string wgPublic: ""
    property string wgPending: ""
    signal wgAdded()

    function wgGenerate() {
        if (wgProc.running) return
        wgError = ""
        wgState = "generating"
        wgProc.command = [Paths.script("wireguard-helper.py"), "genkey"]
        wgProc.running = true
    }
    // The public half of a key typed or pasted into the form.
    function wgPublicOf(privateKey) {
        if (wgProc.running) return
        wgState = "pubkey"
        wgPending = privateKey + "\n"
        wgProc.command = [Paths.script("wireguard-helper.py"), "pubkey"]
        wgProc.running = true
    }
    function wgAdd(name, ifname, configText) {
        if (wgProc.running) return false
        wgError = ""
        wgNotice = ""
        wgState = "adding"
        wgPending = configText
        wgProc.command = [Paths.script("wireguard-helper.py"), "add", "--name=" + name, "--ifname=" + ifname]
        wgProc.running = true
        return true
    }
    // A wg-quick file picked with kdialog. The settings panel closes first
    // (a dialog under a panel with the keyboard is unusable) and opens again
    // on its network page with the answer.
    function wgImport() {
        if (wgProc.running || wgPick.running) return
        wgError = ""
        wgNotice = ""
        PanelService.close()
        wgPick.running = true
    }
    function wgDelete(uuid) {
        if (wgProc.running) return
        wgError = ""
        wgState = "deleting"
        wgPending = ""
        wgProc.command = [Paths.script("wireguard-helper.py"), "delete", "--uuid=" + uuid]
        wgProc.running = true
    }

    Process {
        id: wgPick
        command: ["kdialog", "--title", "Import a WireGuard tunnel", "--getopenfilename",
                  Quickshell.env("HOME") || "/", "*.conf *.config|WireGuard tunnel\n*|All files"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (!path.length) return
                const name = WireguardLogic.nameFromPath(path)
                root.wgState = "importing"
                root.wgPending = ""
                wgProc.command = [Paths.script("wireguard-helper.py"), "add", "--name=" + name,
                                  "--ifname=" + WireguardLogic.interfaceName(name), "--file=" + path]
                wgProc.running = true
            }
        }
    }

    Process {
        id: wgProc
        stderr: ErrorLog { label: "NetworkService.wgProc" }
        stdinEnabled: true
        onStarted: {
            if (root.wgPending.length) write(root.wgPending)
            root.wgPending = ""
            stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let answer = null
                try { answer = JSON.parse(text.trim().split("\n").pop() || "{}") } catch (error) { answer = null }
                const state = root.wgState
                root.wgState = ""
                if (!answer || !answer.ok) {
                    root.wgError = answer && answer.error ? answer.error : "The helper did not answer"
                } else if (state === "generating") {
                    root.wgPrivate = answer["private"]
                    root.wgPublic = answer["public"]
                } else if (state === "pubkey") {
                    root.wgPublic = answer["public"]
                } else if (state === "adding" || state === "importing") {
                    root.wgNotice = answer.warning || "Added. It is in Plasma's network list too."
                    root.wgPrivate = ""
                    root.wgPublic = ""
                    root.wgAdded()
                }
                if (state === "importing") PanelService.open("settings", { page: "network" })
                root.refresh()
            }
        }
        onExited: stdinEnabled = true
    }

    // nmcli -t escapes ':' inside values as '\:'.
    function splitTerse(line) {
        const fields = []
        let currentField = ""
        for (let i = 0; i < line.length; ++i) {
            const ch = line[i]
            if (ch === "\\" && i + 1 < line.length) { currentField += line[++i]; continue }
            if (ch === ":") { fields.push(currentField); currentField = ""; continue }
            currentField += ch
        }
        fields.push(currentField)
        return fields
    }

    // A change reported while nmcli runs gets one more run after it, or the
    // list could keep the state from before that change.
    property bool refreshQueued: false
    function refresh() {
        if (connectionsProc.running) refreshQueued = true
        else connectionsProc.running = true
        // Not at start any more: a hotspot started before this shell, or
        // outside it, is read once the connection list shows it (below), and
        // on almost every login there is none to read.
        if (viewOpen || hotspotActive) refreshHotspot()
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
                // Only a list that changed is handed on: a new array every
                // run rebuilt everything bound to the VPNs for nothing.
                if (JSON.stringify(result) !== JSON.stringify(root.connections)) root.connections = result
                const listed = result.some(item => item.active && item.name === root.hotspotName)
                if (listed && !root.hotspotListed) root.refreshHotspot()
                root.hotspotListed = listed
                root.wiredConnected = wired
                root.readAddress(device)
            }
        }
        onExited: {
            if (!root.refreshQueued) return
            root.refreshQueued = false
            Qt.callLater(root.refresh)
        }
    }

    // A running Process keeps the command it was started with, so a device
    // asked for while one runs is read once that run has exited.
    property string addressDevice: ""
    property bool addressQueued: false
    function readAddress(device) {
        addressDevice = device
        if (!device.length) {
            address = ""
            return
        }
        if (addressProc.running) { addressQueued = true; return }
        addressProc.device = device
        addressProc.command = ["nmcli", "-t", "-g", "IP4.ADDRESS", "device", "show", device]
        addressProc.running = true
    }

    Process {
        id: addressProc
        stderr: ErrorLog { label: "NetworkService.addressProc" }
        // The device this run was started for.
        property string device: ""
        stdout: StdioCollector {
            onStreamFinished: if (addressProc.device === root.addressDevice) root.address = text.split("\n")[0].split(" | ")[0].trim()
        }
        onExited: {
            if (!root.addressQueued) return
            root.addressQueued = false
            Qt.callLater(() => root.readAddress(root.addressDevice))
        }
    }

    Process {
        id: monitorProc
        stderr: ErrorLog { label: "NetworkService.monitorProc" }
        running: true
        command: Paths.bound(["nmcli", "monitor"])
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
    // `nmcli monitor` reports one change as several lines (device, connection,
    // addresses, each a few hundred ms apart on a reconnect); 1.5 s gathers a
    // whole reconnect into one nmcli run, where 400 ms ran it three or four
    // times for the same state.
    Timer { id: debounce; interval: 1500; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
