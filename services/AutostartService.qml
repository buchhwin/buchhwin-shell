pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Apps started once per login of the buchhwin-shell session (setting
// `autostart.apps`, desktop entry ids). They are separate from Plasma's
// autostart; the standard XDG autostart entries are started by
// scripts/session-init.sh when `autostart.system` is on. A marker in
// XDG_RUNTIME_DIR keeps shell reloads from starting apps again. Nested test
// sessions never launch anything.
Singleton {
    id: root

    readonly property var apps: String(SettingsService.value("autostart.apps")).split(",").filter(id => id.length)
    readonly property bool realSession: (Quickshell.env("BUCHHWIN_SHELL_PATH") || "").length > 0
        && Quickshell.env("BUCHHWIN_NESTED") !== "1"
    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/buchhwin-shell-autostart-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none")
    property bool done: false

    function entry(id) {
        return DesktopEntries.applications.values.find(app => app.id === id) || null
    }

    // Stored comma-joined, so a comma is the one thing an id may not hold
    // (nor a control character). Citrix names its subscribed apps with
    // spaces and '$' ("Citrix_subscribed_XenApp 7.x.RDS-Name $S101-255"),
    // which a tidy-name rule refused; the id only ever finds a desktop entry.
    function setApps(list) {
        const seen = {}
        SettingsService.set("autostart.apps", list.filter(id => typeof id === "string" && /^[^,\u0000-\u001f\u007f]+$/.test(id)
            && !seen[id] && (seen[id] = true)).join(","))
    }
    function add(id) { setApps(apps.concat([id])) }
    function remove(id) { setApps(apps.filter(item => item !== id)) }

    function launchAll() {
        if (done || !realSession) return
        done = true
        markerFile.setText(new Date().toISOString() + "\n")
        for (const id of apps) {
            const app = entry(id)
            if (app) LauncherService.launchApp(app, false)
        }
    }

    // Wait for settings and desktop entries, then check the per-login marker.
    Timer {
        interval: 3000
        running: root.realSession && SettingsService.loaded && !root.done
        onTriggered: markerCheck.running = true
    }

    Process {
        id: markerCheck
        stderr: ErrorLog { label: "AutostartService.markerCheck" }
        command: ["test", "-e", root.marker]
        onExited: (code, status) => { if (code === 0) root.done = true; else root.launchAll() }
    }

    FileView { id: markerFile; path: root.marker; printErrors: false }
}
