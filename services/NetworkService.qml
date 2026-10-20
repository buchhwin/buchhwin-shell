pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import "network/WireguardLogic.js" as WireguardLogic
import "network/ScanLogic.js" as ScanLogic
import "network/SignalLogic.js" as Signal
import "network/VpnLogic.js" as VpnLogic
import "network/PortalLogic.js" as Portal
import "network/ShareLogic.js" as Share

// Wi-Fi through Quickshell.Networking (NetworkManager). VPN connections and
// addresses come from nmcli, refreshed only when `nmcli monitor` reports a
// change.
Singleton {
    id: root
    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    readonly property bool wifiAvailable: wifiDevice !== null && Networking.wifiHardwareEnabled
    // NetworkManager's radio flag. It stays on where there is no adapter at
    // all (its default), so on its own it is not "Wi-Fi works".
    readonly property bool wifiEnabled: Networking.wifiEnabled
    // Wi-Fi that can find networks: the flag on and an adapter to search
    // with. Lists, "Searching for networks …" and "Hidden network …" go by
    // this; on a machine without an adapter they sat beside "No Wi-Fi adapter
    // found" and searched forever.
    readonly property bool wifiUsable: wifiEnabled && wifiAvailable
    readonly property bool searching: wifiUsable && networks.length === 0
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
    // Whether nmcli's list has been read once: before, an empty list is not
    // "no VPN" (the OSD's VPN message waits for it).
    property bool connectionsRead: false
    readonly property var vpns: connections.filter(item => item.type === "vpn" || item.type === "wireguard")
    readonly property var activeVpns: vpns.filter(item => item.active)
    property string address: ""

    // NetworkManager's connectivity check (Arch: ping.archlinux.org, every
    // few minutes and on each change): whether the connection reaches the
    // internet. "unknown" where no check is configured - never shown.
    // Quickshell.Networking reads the check since Quickshell 0.3: on
    // Fedora's 0.2.1 snapshot neither the property nor NetworkConnectivity
    // exists, and the switch below stopped at a ReferenceError there.
    readonly property string connectivity: {
        if (typeof NetworkConnectivity === "undefined") return "unknown"
        switch (Networking.connectivity) {
        case NetworkConnectivity.Full: return "full"
        case NetworkConnectivity.Limited: return "limited"
        case NetworkConnectivity.Portal: return "portal"
        case NetworkConnectivity.None: return "none"
        default: return "unknown"
        }
    }
    // Connected, but not to the internet: the glyph takes a "!", the line
    // says why (SignalLogic.note) - once it has held for a few seconds
    // (SignalLogic.limitedShown): right after a reconnect NetworkManager's
    // check has not reached the internet yet, and the "!" flashed.
    readonly property bool limitedNow: connected && Signal.limited(connectivity)
    property real limitedSince: -1
    property bool limited: false
    // A portal's preview (IPC) says what a real one says.
    readonly property string note: portalPreview ? Signal.note("portal") : limited ? Signal.note(connectivity) : ""
    function settleLimited() {
        const now = Date.now()
        // A clock set back counts from now.
        if (limitedSince > now) limitedSince = now
        limited = Signal.limitedShown(limitedNow, limitedSince, now)
        // Until it shows, asked again for what is left (Signal.limitedWait).
        const wait = Signal.limitedWait(limitedNow, limitedSince, now)
        if (wait > 0) {
            limitedTimer.interval = wait
            limitedTimer.restart()
        } else {
            limitedTimer.stop()
        }
    }
    function updateLimited() {
        limitedSince = limitedNow ? Date.now() : -1
        settleLimited()
    }
    onLimitedNowChanged: updateLimited()
    Timer { id: limitedTimer; interval: Signal.LIMITED_SETTLE_MS; onTriggered: root.settleLimited() }

    readonly property string summary: (!wifiUsable && !wiredConnected ? "Off"
        : current ? current.name : wiredConnected ? "Wired" : "Not connected")
        + (note.length ? " \u00b7 " + note : "")

    // A network of the list, by its strength in NetworkManager's four steps
    // (SignalLogic) - the one in use through `wifiIcon`, which knows about
    // the internet as well.
    function signalIcon(strength) {
        return Signal.glyph(strength, false, false)
    }

    // The bars glyph (NetworkWidget, `options.glyph: "bars"`): of `total`, how
    // many are lit. Every one when wired, none when off or not connected, and
    // never none while connected - the same steps as the glyphs.
    function signalBars(total) {
        if (!wifiUsable && !wiredConnected) return 0
        if (current) return Math.max(1, Signal.lit(current.signalStrength, total, true))
        return wiredConnected ? total : 0
    }

    // Wi-Fi as the bar shows it: off, the connected network's strength (with
    // a "!" while it does not reach the internet), or not connected.
    readonly property string wifiIcon: !wifiUsable ? "󰤮"
        : current ? Signal.glyph(current.signalStrength, limited, true) : "󰤯"
    readonly property string icon: !wifiUsable && !wiredConnected ? "󰤮"
        : wiredConnected && !current ? "󰈀"
        : wifiIcon

    // ---- captive portals (PortalLogic) ---------------------------------------
    // A hotel's, a train's or a guest network's sign-in page. The way there is
    // a plain http address the portal answers in its place - NetworkManager's
    // own check address, which is how it found the portal - opened in the
    // default browser on a click; the shell fetches nothing itself, and no
    // window opens without one. `portalPreview` shows the button and the
    // line without a portal (IPC `network previewPortal`, screenshots); a
    // click then opens nothing.
    property bool portalPreview: false
    readonly property bool signInNeeded: portalPreview || Portal.signInNeeded(connectivity, limited)
    readonly property string portalName: portalPreview ? "Example network"
        : Portal.networkName(current ? current.name : "", wiredConnected)

    function openPortal() {
        PanelService.close()
        if (portalPreview) {
            console.info("buchhwin-shell: network: sign-in page (preview, nothing opened)")
            return
        }
        if (!portalUri.running) portalUri.running = true
    }
    // The check address is asked for at the click, not kept: it is
    // NetworkManager's setting, read once per sign-in. Without an answer (no
    // check configured, busctl missing) the fallback page opens.
    Process {
        id: portalUri
        stderr: ErrorLog { label: "NetworkService.portalUri" }
        command: ["busctl", "--system", "--auto-start=no", "get-property", "org.freedesktop.NetworkManager",
                  "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", "ConnectivityCheckUri"]
        stdout: StdioCollector {
            onStreamFinished: Quickshell.execDetached([Paths.script("launch-default.sh"), "browser",
                                                       Portal.signInUrl(Portal.parseUri(text))])
        }
    }

    // One notification per network, once its portal has held for the settle
    // time; again only after the network reached the internet in between
    // (signed in, and the portal back the next day) and the cooldown has
    // passed, so a flap of the check or of the Wi-Fi never notifies twice
    // (PortalLogic.notifyStep). Its "Sign in" does what the button does.
    // Only in the real session: a nested shell's notify-send reaches the
    // host's notification server.
    readonly property bool notifyAllowed: AppearanceService.realSession && Quickshell.env("BUCHHWIN_NESTED") !== "1"
    readonly property bool portalNotify: SettingsService.value("network.portalNotify") !== false
    property var portalState: ({ notified: {} })
    // The title of the notice that is out, so it can go once the internet
    // is back.
    property string portalNoticeTitle: ""
    readonly property string portalInput: [Portal.connectionKey(current ? current.name : "", wiredConnected),
                                           Portal.signInNeeded(connectivity, limited), connectivity, portalNotify].join("|")
    onPortalInputChanged: portalCheck.restart()
    Timer { id: portalCheck; interval: 500; onTriggered: root.checkPortal() }
    function checkPortal() {
        const step = Portal.notifyStep(portalState, {
            key: Portal.connectionKey(current ? current.name : "", wiredConnected),
            portal: Portal.signInNeeded(connectivity, limited), full: connectivity === "full",
            now: Date.now(), enabled: portalNotify && notifyAllowed
        })
        portalState = step.state
        if (step.dismiss) dismissPortalNotice()
        if (!step.notify) return
        const text = Portal.notice(Portal.networkName(current ? current.name : "", wiredConnected))
        dismissPortalNotice()
        portalNoticeTitle = text.title
        portalNotice.createObject(root, {
            command: Paths.bound(["timeout", "10m", "notify-send", "--app-name=Network", "--icon=" + text.icon,
                                  "--action=signin=Sign in", "--", text.title, text.body])
        })
    }
    function dismissPortalNotice() {
        if (!portalNoticeTitle.length) return
        const title = portalNoticeTitle
        portalNoticeTitle = ""
        const list = NotificationService.history
        for (let i = list.length - 1; i >= 0; --i) {
            const item = list[i]
            if (item && item.appName === "Network" && item.summary === title) item.dismiss()
        }
    }
    // notify-send waits for the answer until its notice closes; ten minutes
    // is time enough to click, and the shell's history keeps the notice
    // after that with its button doing nothing (DrivesService's way).
    Component {
        id: portalNotice
        Process {
            id: noticeRun
            running: true
            stderr: ErrorLog { label: "NetworkService.portalNotice" }
            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim() === "signin") root.openPortal()
                    noticeRun.destroy()
                }
            }
        }
    }

    // ---- network drives (ShareLogic) -------------------------------------------
    // The automount points and the mounted network shares, for the VPN popup:
    // read from /proc/self/mountinfo and from nothing else. A path under an
    // automount is never listed, tested or opened by the shell while no VPN is
    // up - touching one with its server out of reach starts a mount that hangs
    // the caller, and a few such tries leave the automount failed until an
    // administrator resets it. Read when a view opens and on each
    // NetworkManager change while one is open; nothing otherwise.
    property var shares: []
    property bool sharesRead: false
    property int shareViewers: 0
    readonly property bool vpnUp: activeVpns.length > 0
    readonly property var sharesSummary: Share.summary(shares, vpnUp)
    function watchShares(enabled) {
        shareViewers = ScanLogic.scanViewers(shareViewers, enabled)
        if (enabled) readShares()
    }
    function readShares() {
        if (sharesProc.running) sharesQueued = true
        else sharesProc.running = true
    }
    property bool sharesQueued: false
    function shareStatus(share) { return Share.status(share) }
    function shareOpenable(share) { return Share.openable(share, vpnUp) }
    // The file manager at the drive, which mounts it: only with a VPN up.
    function openShare(share) {
        if (!Share.openable(share, vpnUp)) return
        Quickshell.execDetached([Paths.script("launch-default.sh"), "files", share.point])
        PanelService.close()
    }
    Process {
        id: sharesProc
        stderr: ErrorLog { label: "NetworkService.sharesProc" }
        command: ["cat", "/proc/self/mountinfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = Share.shares(Share.parseMountinfo(text))
                if (JSON.stringify(next) !== JSON.stringify(root.shares)) root.shares = next
                root.sharesRead = true
            }
        }
        onExited: {
            if (!root.sharesQueued) return
            root.sharesQueued = false
            Qt.callLater(root.readShares)
        }
    }

    // ---- secured networks and hotspot (scripts/network-helper.py) -----------
    // Secrets go to the helper on stdin, never as process arguments.
    property string helperState: ""        // "", "connecting", "hotspot"
    property string helperError: ""
    property string pendingSsid: ""
    property string pendingSecret: ""
    // Whether network-helper.py's hotspot connection is up, from nmcli's list
    // (ScanLogic.parseConnections) - set at once by a start or stop here,
    // and corrected by the refresh that follows it.
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

    function setWifiEnabled(enabled) { Networking.wifiEnabled = enabled }
    // Every network view - the popup, the control-center page, the settings
    // page - turns scanning on when it comes into view and off when it goes,
    // so this is also where the service learns that someone is looking.
    // Those views are the only readers of `address`, and reading it is an
    // nmcli run of its own; with nobody looking it is left to the next open
    // (read at once then) rather than run on every NetworkManager event of an
    // idle session.
    property bool viewOpen: false
    // The connection network-helper.py starts (HOTSPOT_ID); its being active
    // in nmcli's list is `hotspotActive`.
    readonly property string hotspotName: "buchhwin-hotspot"
    // How many views are open (ScanLogic.scanViewers): the scan and
    // `viewOpen` stay on until the last one has gone.
    property int scanViewers: 0
    function setScanning(enabled) {
        const before = scanViewers
        scanViewers = ScanLogic.scanViewers(scanViewers, enabled)
        const on = scanViewers > 0
        viewOpen = on
        if (wifiDevice) wifiDevice.scannerEnabled = on
        if (enabled && before === 0) readAddress(addressDevice)
    }
    // An adapter that appears (or comes back) while a view is open scans too.
    onWifiDeviceChanged: if (wifiDevice && scanViewers > 0) wifiDevice.scannerEnabled = true
    function connectNetwork(network) { if (network) network.connect() }
    function disconnectNetwork(network) { if (network) network.disconnect() }
    function forget(network) { if (network) network.forget() }

    // KDE's editor for enterprise networks and VPN profiles.
    function openSystemDialog() {
        // Through launch-app.sh: the session's environment (the Plasma look,
        // none of the shell's own settings) and a unit of its own.
        Quickshell.execDetached([Paths.script("launch-app.sh"), "kcm_networkmanagement", "kcmshell6", "kcm_networkmanagement"])
        PanelService.close()
    }

    // ---- VPN switches (VpnLogic) ---------------------------------------------
    // One nmcli per switch, watched: the row shows where it is going while
    // nmcli works ("Connecting …"), and a tunnel that does not come up says
    // why in a notification instead of nothing.
    property var vpnPending: ({})        // { uuid: { up, seq } }
    property int vpnSeq: 0
    property string vpnError: ""
    property string lastVpnUuid: ""
    readonly property string vpnPendingText: VpnLogic.pendingText(vpnPending)
    // The tunnel the quick tile brings up: the one used last, else the first.
    readonly property string preferredVpnUuid: VpnLogic.preferred(vpns, lastVpnUuid)

    function connectionByUuid(uuid) { return connections.find(item => item.uuid === uuid) || null }
    function vpnChecked(item) { return VpnLogic.checked(item, vpnPending) }
    function vpnStatus(item) { return VpnLogic.status(item, vpnPending) }

    function setVpn(uuid, up) {
        if (!uuid || !uuid.length) return
        const entry = vpnPending[uuid]
        if (entry && entry.up === (up === true)) return
        vpnSeq += 1
        vpnPending = VpnLogic.begin(vpnPending, uuid, up === true, vpnSeq)
        vpnError = ""
        if (up) lastVpnUuid = uuid
        const item = connectionByUuid(uuid)
        const run = vpnSwitch.createObject(root, {
            uuid: uuid, up: up === true, seq: vpnSeq, name: item ? item.name : "",
            // The exit status on the first line, then what nmcli said: one
            // stream, so the answer and its status never arrive apart.
            command: ["sh", "-c", 'out=$(nmcli connection "$1" uuid "$2" 2>&1); code=$?; printf "%s\n%s\n" "$code" "$out"',
                      "sh", up ? "up" : "down", uuid]
        })
        run.running = true
    }

    function vpnFinished(run, text) {
        const step = VpnLogic.finish(vpnPending, run.uuid, run.seq)
        const answer = step.current ? VpnLogic.result(text) : null
        // Done: the list says so before the refresh below has read it again.
        if (answer && answer.ok) connections = VpnLogic.settled(connections, run.uuid, run.up)
        vpnPending = step.pending
        if (answer) {
            if (!answer.ok) {
                const title = "VPN “" + (run.name || "tunnel") + "” did not " + (run.up ? "connect" : "disconnect")
                vpnError = title + ": " + answer.message
                if (AppearanceService.realSession)
                    Quickshell.execDetached(["notify-send", "--app-name=Network", "--icon=network-vpn", "--", title, answer.message])
                else
                    console.info("buchhwin-shell: network: notification (nested, not sent):", title, "—", answer.message)
            }
        }
        refresh()
    }

    Component {
        id: vpnSwitch
        Process {
            id: switchRun
            property string uuid: ""
            property bool up: false
            property int seq: 0
            property string name: ""
            property bool answered: false
            stderr: ErrorLog { label: "NetworkService.vpnSwitch" }
            stdout: StdioCollector {
                onStreamFinished: {
                    root.vpnFinished(switchRun, text)
                    switchRun.answered = true
                    switchRun.release()
                }
            }
            // Gone once it has both answered and exited, in whichever order
            // the two arrive.
            function release() { if (answered && !running) destroy() }
            onRunningChanged: release()
        }
    }

    // ---- WireGuard tunnels (scripts/wireguard-helper.py) --------------------
    // Added as the user's own NetworkManager connections, which need no
    // administrator password and which Plasma lists as well - one
    // NetworkManager, the same tunnels in both sessions. Keys go to the helper
    // on stdin, never as arguments. The private key a "Generate" makes is held
    // here, in memory only, until the tunnel is added or the form is canceled:
    // the usual order is to generate, send the public key to the server's
    // admin and close Settings to wait, and the page is let go a minute later -
    // the form fills itself from here again.
    property string wgState: ""          // "", "generating", "adding", "deleting"
    property string wgError: ""
    property string wgNotice: ""
    property string wgPrivate: ""
    property string wgPublic: ""
    // Which private key wgPublic was made from (a tag, not the key): the form
    // shows and copies the public key only while its field holds that key.
    property string wgPublicFrom: ""
    property string wgRequested: ""
    property string wgPending: ""
    signal wgAdded()

    function wgTag(privateKey) { return Qt.md5(String(privateKey || "").trim()) }
    // The public key that belongs to what a form's private-key field holds,
    // or "" (WireguardLogic.publicFor).
    function wgPublicFor(privateText) { return WireguardLogic.publicFor(privateText, wgPublic, wgPublicFrom, wgTag) }
    // Cancel: the generated key goes, and the public key with it.
    function wgForget() {
        wgPrivate = ""
        wgPublic = ""
        wgPublicFrom = ""
    }

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
        wgRequested = wgTag(privateKey)
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

    // kdialog through launch-app.sh, for the session's environment (the
    // Plasma look and icons); a scope keeps its stdout, which is the answer.
    Process {
        id: wgPick
        command: [Paths.script("launch-app.sh"), "org.kde.kdialog", "kdialog", "--title", "Import a WireGuard tunnel", "--getopenfilename",
                  Quickshell.env("HOME") || "/", "*.conf *.config|WireGuard tunnel\n*|All files"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                // Cancel (or no kdialog): back to where the import started,
                // as an answer does - not the bare desktop.
                if (!path.length) {
                    PanelService.open("settings", { page: "network" })
                    return
                }
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
                    root.wgPublicFrom = root.wgTag(answer["private"])
                } else if (state === "pubkey") {
                    root.wgPublic = answer["public"]
                    root.wgPublicFrom = root.wgRequested
                } else if (state === "adding" || state === "importing") {
                    root.wgNotice = answer.warning || "Added. It is in Plasma's network list too."
                    root.wgForget()
                    root.wgAdded()
                }
                root.wgRequested = ""
                if (state === "importing") PanelService.open("settings", { page: "network" })
                root.refresh()
            }
        }
        onExited: stdinEnabled = true
    }

    // nmcli -t escapes ':' inside values as '\:' (ScanLogic.splitTerse).
    function splitTerse(line) { return ScanLogic.splitTerse(line) }

    // A change reported while nmcli runs gets one more run after it, or the
    // list could keep the state from before that change.
    property bool refreshQueued: false
    // Whether nmcli monitor has reported anything since the last read (or
    // the monitor is down): a view that opens can skip its own read when it
    // has not (`refreshIfStale`).
    property bool changedSinceRead: true
    function refresh() {
        changedSinceRead = false
        if (connectionsProc.running) refreshQueued = true
        else connectionsProc.running = true
    }
    function refreshIfStale() {
        if (changedSinceRead || !monitorProc.running) refresh()
    }

    Process {
        id: connectionsProc
        stderr: ErrorLog { label: "NetworkService.connectionsProc" }
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = ScanLogic.parseConnections(text, root.hotspotName)
                // Only a list that changed is handed on: a new array every
                // run rebuilt everything bound to the VPNs for nothing.
                if (JSON.stringify(parsed.connections) !== JSON.stringify(root.connections))
                    root.connections = parsed.connections
                root.hotspotActive = parsed.hotspot
                root.wiredConnected = parsed.wired
                root.connectionsRead = true
                // A tunnel up or down changes what the drives' list says
                // and, mounted or unmounted after it, what it lists.
                if (root.shareViewers > 0) root.readShares()
                // The address only for a view that shows it; the device is
                // kept for the next one that opens (setScanning).
                if (root.viewOpen) root.readAddress(parsed.device)
                else root.addressDevice = parsed.device
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
        // Its first line is the state at its start (ScanLogic.monitorNews).
        property bool first: true
        stdout: SplitParser {
            onRead: data => {
                const news = ScanLogic.monitorNews(data, monitorProc.first)
                monitorProc.first = false
                if (!news) return
                root.changedSinceRead = true
                debounce.restart()
            }
        }
        onRunningChanged: {
            if (running) { first = true; return }
            root.changedSinceRead = true
            restartTimer.start()
        }
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
    Component.onCompleted: {
        refresh()
        updateLimited()
    }
}
