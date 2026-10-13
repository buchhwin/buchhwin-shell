import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/network/WireguardLogic.js" as Logic

// A new WireGuard tunnel by hand (Settings > Network > VPN): the fields of a
// wg-quick file, checked as they are typed (WireguardLogic.errors), and sent
// to scripts/wireguard-helper.py as that file. "Generate" makes a key pair;
// the public half is what the server needs, and it can be copied from here.
ColumnLayout {
    id: form
    spacing: Metrics.spaceSm
    signal done()

    readonly property var values: ({
        name: nameField.text, address: addressField.text, dns: dnsField.text,
        privateKey: privateField.text, peerKey: peerField.text, presharedKey: pskField.text,
        endpoint: endpointField.text, allowedIps: allowedField.text, keepalive: keepaliveField.text
    })
    readonly property var problems: Logic.errors(values)
    readonly property bool complete: Object.keys(problems).length === 0
    // Errors only once something was typed into the field, not on an empty form.
    function problem(key, field) { return field.text.length && problems[key] ? problems[key] : "" }

    Connections {
        target: NetworkService
        function onWgPrivateChanged() { if (NetworkService.wgPrivate.length) privateField.text = NetworkService.wgPrivate }
        function onWgAdded() { form.done() }
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Name"
        hint: form.problem("name", nameField) || ("Interface " + Logic.interfaceName(nameField.text))
        ShellTextField { id: nameField; focusOnTab: true; Layout.fillWidth: true; placeholder: "Office" }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Address"
        hint: form.problem("address", addressField) || "This side of the tunnel, from the server's admin"
        ShellTextField { id: addressField; focusOnTab: true; Layout.fillWidth: true; placeholder: "10.0.0.2/32" }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "DNS"
        hint: form.problem("dns", dnsField) || "Optional"
        ShellTextField { id: dnsField; focusOnTab: true; Layout.fillWidth: true; placeholder: "10.0.0.1" }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Private key"
        hint: form.problem("privateKey", privateField)
            || (NetworkService.wgPublic.length ? "Public key: " + NetworkService.wgPublic : "Stays on this computer")
        ShellTextField {
            id: privateField
            focusOnTab: true
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholder: "Generate one, or paste yours"
            onAccepted: if (Logic.isKey(text)) NetworkService.wgPublicOf(text.trim())
        }
        ShellButton {
            focusOnTab: true
            compact: true
            text: "Generate"
            enabledState: NetworkService.wgState.length === 0
            onClicked: NetworkService.wgGenerate()
        }
        ShellButton {
            focusOnTab: true
            compact: true
            icon: Icons.copy
            toolTip: "Copy the public key for the server"
            enabledState: NetworkService.wgPublic.length > 0
            onClicked: Quickshell.clipboardText = NetworkService.wgPublic
        }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Server key"
        hint: form.problem("peerKey", peerField) || "The server's public key"
        ShellTextField { id: peerField; focusOnTab: true; Layout.fillWidth: true }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Preshared key"
        hint: form.problem("presharedKey", pskField) || "Optional"
        ShellTextField { id: pskField; focusOnTab: true; Layout.fillWidth: true; echoMode: TextInput.Password }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Endpoint"
        hint: form.problem("endpoint", endpointField) || "Where the server answers"
        ShellTextField { id: endpointField; focusOnTab: true; Layout.fillWidth: true; placeholder: "vpn.example.org:51820" }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Allowed IPs"
        hint: form.problem("allowedIps", allowedField) || "0.0.0.0/0, ::/0 sends everything through the tunnel"
        ShellTextField { id: allowedField; focusOnTab: true; Layout.fillWidth: true; text: "0.0.0.0/0, ::/0" }
    }
    SettingRow {
        Layout.fillWidth: true
        label: "Keepalive"
        hint: form.problem("keepalive", keepaliveField) || "Seconds; 25 keeps a tunnel behind NAT open"
        ShellTextField { id: keepaliveField; focusOnTab: true; Layout.fillWidth: true; text: "25" }
    }
    // What still stands between the form and a tunnel, in words, so a
    // disabled button is never the only answer.
    readonly property var labels: ({ name: "Name", address: "Address", dns: "DNS", privateKey: "Private key",
                                     peerKey: "Server key", presharedKey: "Preshared key", endpoint: "Endpoint",
                                     allowedIps: "Allowed IPs", keepalive: "Keepalive" })
    ShellText {
        Layout.fillWidth: true
        visible: !form.complete
        text: Object.keys(form.problems).map(key => form.labels[key] + ": " + form.problems[key]).join(" · ")
        role: "small"
        muted: true
        wrapMode: Text.Wrap
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        Item { Layout.fillWidth: true }
        ShellButton { focusOnTab: true; compact: true; text: "Cancel"; variant: "ghost"; onClicked: form.done() }
        ShellButton {
            focusOnTab: true
            compact: true
            variant: "accent"
            text: NetworkService.wgState === "adding" ? "Adding …" : "Add tunnel"
            enabledState: form.complete && NetworkService.wgState.length === 0
            onClicked: NetworkService.wgAdd(nameField.text.trim(), Logic.interfaceName(nameField.text), Logic.config(form.values))
        }
    }
}
