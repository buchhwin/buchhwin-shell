import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T

// SnapshotService and scripts/snapshot.py together, in the test's own
// configuration and state directories (tests/run-qml-test.sh sandboxes
// them): nothing automatic without a session (no BUCHHWIN_SHELL_PATH),
// a copy kept by hand, and the list read back. Restore and import end in a
// shell restart and are covered by snapshot_test.py and SnapshotTest.
ShellRoot {
    id: root
    property int step: 0

    Process {
        id: seed
        command: ["sh", "-c", "mkdir -p \"$1\" && printf '{\"appearance\": {}}\\n' > \"$1/settings.json\"", "sh", Paths.configDir]
        onExited: code => {
            T.eq(code, 0, "a setup to keep")
            SnapshotService.beforeWrite()
            T.eq(SnapshotService.takenDay, "", "nothing automatic outside a session")
            root.step = 1
            T.ok(SnapshotService.takeNow(), "a copy by hand starts")
            T.ok(!SnapshotService.takeNow(), "and a second one waits for it")
        }
    }
    Component.onCompleted: seed.running = true

    Connections {
        target: SnapshotService
        function onWorkingChanged() {
            if (root.step !== 1 || SnapshotService.working.length) return
            root.step = 2
            T.eq([SnapshotService.message, SnapshotService.messageError], ["Kept a copy of the setup now", false], "the helper's answer")
        }
        function onSnapshotsChanged() {
            if (root.step !== 2) return
            root.step = 3
            const list = SnapshotService.snapshots
            T.eq(list.length, 1, "the list read back")
            T.ok(list.length === 1 && /^manual-/.test(list[0].name) && list[0].files === 1, "one copy by hand, of one file")
            T.eq(SnapshotService.subtitle(list[0]).indexOf("Kept by hand · 1 file · "), 0, "with its words")
            T.ok(!SnapshotService.restore("../" + (list[0] || {}).name), "a name that is not listed is refused")
            T.finish("SnapshotServiceTest")
        }
    }
}
