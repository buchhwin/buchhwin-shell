pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "lock/LockLogic.js" as LockLogic

// Security key (a YubiKey or another FIDO2 key) for Settings > Lock Screen:
// whether pam-u2f, the lock's PAM file (/etc/pam.d/buchhwin-lock-key) and
// registered keys are there, and which key is plugged in - read by
// `scripts/security-key.py status` while a page tracks the service, asking
// the key nothing. Setting up, adding a key and turning it off run that
// script in a terminal (TerminalJob): they ask for the key's PIN, a touch
// and sudo, which are the user's to give, and never run in a nested session.
// The key only unlocks the lock screen: the login screen, sudo and the
// keyring stay with the password. The mode (lock.securityKey) is read by the
// lock screen before its first conversation.
Singleton {
    id: root

    readonly property bool realSession: Quickshell.env("BUCHHWIN_NESTED") !== "1"
    property int trackers: 0
    // `scripts/security-key.py status`; `known` once it answered.
    property var state: ({ known: false, module: false, tool: false, service: false, serviceCurrent: false,
                           keys: 0, devices: [], fido2Token: false, pins: [] })
    readonly property bool known: state.known === true
    readonly property bool installed: state.module === true && state.tool === true
    // The lock asks a key: its PAM file is in place and a key is registered.
    readonly property bool setUp: state.service === true && state.keys > 0
    // The PAM file is older than the one in the shell: setting up again renews it.
    readonly property bool outdated: state.service === true && state.serviceCurrent !== true
    readonly property int keys: state.keys || 0
    readonly property var devices: state.devices || []
    // The first plugged key's PIN tries, read without the PIN (fido2-token -I);
    // -1 while unknown or for a key without a PIN. A right PIN sets them back
    // to 8 on a YubiKey; at 0 its FIDO part has to be reset.
    readonly property int pinRetries: {
        const pin = (state.pins || [])[0]
        return pin && pin.set === true && typeof pin.retries === "number" ? pin.retries : -1
    }
    readonly property bool busy: job.busy
    property string message: ""
    property bool messageError: false

    // Unlock mode: auto | off (LockLogic.keyService).
    readonly property string mode: SettingsService.value("lock.securityKey")
    function setMode(value) {
        if (LockLogic.SECURITY_KEY_MODES.indexOf(value) < 0) return false
        return SettingsService.set("lock.securityKey", value)
    }

    function track() { trackers += 1 }
    function untrack() { trackers = Math.max(0, trackers - 1) }
    onTrackersChanged: if (trackers > 0) refresh()

    function refresh() {
        if (statusProc.running) return
        statusProc.running = true
    }

    // "setup", "add" or "off", in a terminal of its own.
    function run(command) {
        if (!realSession || job.busy || ["setup", "add", "off"].indexOf(command) < 0) return
        message = ""
        messageError = false
        job.start([Paths.script("launch-terminal.sh"), "--unit", job.unit, "--hold", "--title", "Security key", "--",
                   Paths.script("security-key.py"), command])
    }

    TerminalJob {
        id: job
        unit: "buchhwin-security-key"
        label: "SecurityKeyService.terminal"
        onEnded: root.refresh()
        onFailed: code => {
            root.message = job.failureText(code)
            root.messageError = true
        }
    }
    // A terminal started before a shell restart is still the page's.
    Component.onCompleted: if (realSession) job.watch()

    Process {
        id: statusProc
        command: [Paths.script("security-key.py"), "status"]
        stderr: ErrorLog { label: "SecurityKeyService.status" }
        stdout: StdioCollector {
            onStreamFinished: {
                let answer = null
                try { answer = JSON.parse(text.trim().split("\n").pop() || "{}") } catch (error) { answer = null }
                if (answer && answer.ok) root.state = Object.assign({ known: true }, answer)
            }
        }
    }
}
