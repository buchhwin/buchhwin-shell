import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/network/WireguardLogic.js" as W

ShellRoot {
    Component.onCompleted: {
        const key = "A".repeat(43) + "="
        T.eq([W.isKey(key), W.isKey("A".repeat(43) + "B"), W.isKey("short="), W.isKey(" " + key + " ")],
             [true, false, false, true], "a WireGuard key is 44 base64 characters")
        T.eq([W.isCidr("10.0.0.2/32"), W.isCidr("fd00::2/128"), W.isCidr("10.0.0.300/32"), W.isCidr("10.0.0.0/33"), W.isCidr("10.0.0.2")],
             [true, true, false, false, true], "addresses with and without a prefix")
        T.eq([W.isEndpoint("vpn.example.org:51820"), W.isEndpoint("[fd00::1]:51820"), W.isEndpoint("vpn.example.org"), W.isEndpoint("host:70000")],
             [true, true, false, false], "an endpoint needs a port")
        T.eq([W.interfaceName("Office VPN"), W.interfaceName("Ein sehr langer Name hier"), W.interfaceName("!!!")],
             ["wg-office-vpn", "wg-ein-sehr-lan", "wg-tunnel"], "the interface name fits the kernel's 15")
        const form = { name: "Office", address: "10.0.0.2/32", dns: "10.0.0.1", privateKey: key, peerKey: key,
                       presharedKey: "", endpoint: "vpn.example.org:51820", allowedIps: "0.0.0.0/0, ::/0", keepalive: "25" }
        T.eq(W.errors(form), {}, "a whole form has no errors")
        T.eq(Object.keys(W.errors({ name: "", address: "x", privateKey: "", peerKey: key, endpoint: "a", allowedIps: "" })).sort(),
             ["address", "allowedIps", "endpoint", "name", "privateKey"], "each broken field is named")
        T.eq(W.config(form), "[Interface]\nPrivateKey = " + key + "\nAddress = 10.0.0.2/32\nDNS = 10.0.0.1\n\n[Peer]\nPublicKey = "
             + key + "\nEndpoint = vpn.example.org:51820\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25\n",
             "the form as a wg-quick file")
        T.eq([W.nameFromPath("/home/x/office-vpn.conf"), W.nameFromPath("")], ["office-vpn", "WireGuard"], "a file's name")
        T.finish("WireguardTest")
    }
}
