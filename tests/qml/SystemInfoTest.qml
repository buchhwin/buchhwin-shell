import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/system/SystemLogic.js" as SystemLogic

// Settings > About's reading (SystemInfoService): its lines parsed, and read
// once per session - the page is built again on every visit, and each visit
// used to start a shell and some fifteen processes of its own.
ShellRoot {
    id: root
    property int waits: 0

    Component.onCompleted: {
        const parsed = SystemInfoService.parse("os=Sample OS 1\nkernel=6.1.0\nnoise\n=empty key\ncpu=Sample CPU = fast\nramKib=16000000\n")
        T.eq([parsed.os, parsed.kernel, parsed.cpu], ["Sample OS 1", "6.1.0", "Sample CPU = fast"], "key=value lines, the value as it is")
        T.ok(!("noise" in parsed) && !("" in parsed), "a line without a key is left out")
        T.eq(parsed.ram, SystemLogic.formatBytes(16000000 * 1024), "memory in the System popup's units")
        T.eq(SystemInfoService.parse(undefined), {}, "nothing read, nothing shown")
        T.eq([SystemInfoService.asked, SystemInfoService.reads], [false, 0], "nothing is read before the page asks")
        SystemInfoService.load()
        SystemInfoService.load()
        wait.start()
    }
    Timer {
        id: wait; interval: 50; repeat: true
        onTriggered: {
            root.waits += 1
            if (!String(SystemInfoService.info.kernel || "").length && root.waits < 100) return
            stop()
            T.ok(String(SystemInfoService.info.kernel || "").length > 0, "the reading came back")
            SystemInfoService.load()
            later.start()
        }
    }
    Timer {
        id: later; interval: 300
        onTriggered: {
            T.eq(SystemInfoService.reads, 1, "read once, however often the page asks")
            T.finish("SystemInfoTest")
        }
    }
}
