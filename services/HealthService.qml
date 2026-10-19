pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "health/HealthLogic.js" as Logic
import "fingerprint/FingerprintLogic.js" as FingerprintLogic

// Settings > About's Health: the session's read-only checks
// (scripts/session-check.sh --json) and the package doctor
// (scripts/doctor.sh --json), run when the page opens - at most once a minute,
// or on "Check again" - with what the shell itself knows on top (HealthLogic).
// Each finding comes with its fix: a command to copy for the steps that need
// sudo (the faillock lines, logind's lid, plocate's index, the reader's PAM
// line), a button for the ones that are the user's own. Nothing runs while
// the page is closed; a check changes nothing.
Singleton {
    id: root

    property var sessionItems: []
    property var doctorItems: []
    property real lastRun: 0
    readonly property bool running: sessionProc.running || doctorProc.running
    // The shell's own share, live while anything reads it.
    readonly property var shellItems: Logic.shellItems({
        reader: { available: FingerprintService.available, fingers: FingerprintService.fingers.length,
                  pamMissing: FingerprintLogic.pamLineMissing(DistroService.family, FingerprintService.lockEnabled),
                  onCommand: DistroService.fingerprintOnCommand },
        vpn: { count: NetworkService.vpns.length, tile: LayoutService.quickTypes.indexOf("vpn") >= 0 },
        apps: DefaultAppsService.categories
    })
    readonly property var items: Logic.merge([sessionItems, doctorItems, shellItems])
    readonly property string summary: Logic.summary(items, lastRun > 0, running)
    readonly property bool healthy: lastRun > 0 && !running && items.length === 0

    function actionLabel(action) { return Logic.actionLabel(action) }
    function levelLabel(level) { return Logic.levelLabel(level) }

    // The page's open: again only when the last run is a minute old.
    function check(force) {
        if (running || (!force && !Logic.due(lastRun, Date.now()))) return
        FingerprintService.peek()
        DefaultAppsService.refresh()
        sessionProc.running = true
        doctorProc.running = true
    }

    function act(action) {
        if (action === "restartShell") SessionService.restartShell()
        else if (action === "enrollFinger" || action === "lockScreen") PanelService.open("settings", { page: "lockScreen" })
        else if (action === "vpnTile") LayoutService.quickAdd("vpn")
        else if (action === "defaultApps") PanelService.open("settings", { page: "defaultApps" })
    }

    // session-check finds the running shell by this path (its IPC and log).
    readonly property string shellDir: Paths.shellFile("").replace(/\/$/, "")
    Process {
        id: sessionProc
        command: ["timeout", "60", Paths.script("session-check.sh"), "--json"]
        environment: ({ BUCHHWIN_SHELL_PATH: root.shellDir })
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessionItems = Logic.parseLines(text, "session").items
                root.lastRun = Date.now()
            }
        }
    }
    Process {
        id: doctorProc
        command: ["timeout", "60", Paths.script("doctor.sh"), "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.doctorItems = Logic.parseLines(text, "doctor").items
                root.lastRun = Date.now()
            }
        }
    }
}
