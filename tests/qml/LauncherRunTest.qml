import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/launcher/ConvertLogic.js" as C

// LauncherService with the new sources wired in: "$ command" is a prefix of
// its own (not one of the switch's modes), a plain query asks every source
// without a TypeError while no compositor is there, and "= 10 km to mi"
// reaches qalc and comes back as a row once the typing has settled - with
// qalc's settings in the shell's cache folder (the sandbox's here), never the
// user's own. Without qalc on this machine the last part says so and passes.
ShellRoot {
    id: root

    Component.onCompleted: {
        T.eq(LauncherService.modeFor("$ htop").id, "run", "$ is the run prefix")
        T.ok(LauncherService.modes.every(mode => mode.id !== "run"), "and no mode of the switch")
        T.eq(LauncherService.modeFor("htop").id, "apps", "without it, apps as before")
        T.eq([LauncherService.modeFor("$100 to eur").id, LauncherService.modeFor("$ 100 to eur").id,
              LauncherService.modeFor("$7z x a.zip").id], ["apps", "run", "run"],
             "a dollar amount to convert is no command; a space or anything else after the $ is")
        const run = LauncherService.results("$ htop", "All")
        T.eq(run.map(entry => [entry.kind, entry.key, entry.title]), [["run", "run", "Run htop"]], "one row for the command")
        T.ok(typeof run[0].alternate === "function", "with a terminal as the alternate")
        T.eq(LauncherService.results("$", "All"), [], "nothing typed after it: no row")
        T.eq(JSON.parse(LauncherService.describe("$ make")), [{ kind: "run", key: "run", title: "Run make",
             subtitle: "Enter runs it · Ctrl+Enter in a terminal" }], "the IPC view of it")
        // Every source of the plain search, with nothing to find.
        T.ok(Array.isArray(LauncherService.results("zzqx", "All")), "a plain query asks every source")
        T.ok(Array.isArray(LauncherService.results("zzqx", "Internet")), "a category leaves the other sources out")
        T.eq(LauncherService.results("= 12 * (3 + 4)", "All").map(entry => entry.title), ["84"], "the calculator as before")
        T.eq(LauncherService.results("= 10 km to mi", "All"), [], "a conversion is not there at once")
        LauncherService.checkQalc()
        wait.start()
    }

    Timer {
        id: wait
        interval: 2500
        onTriggered: {
            if (LauncherService.qalcMissing) {
                console.warn("LauncherRunTest: qalc is not installed here, the conversion is not checked")
            } else {
                const rows = LauncherService.results("= 10 km to mi", "All")
                T.eq(rows.map(entry => [entry.kind, entry.key, entry.title]), [["calculator", "convert", "6.21371 mi"]],
                     "qalc's answer, once the typing has settled, rounded to read")
                T.ok(rows.length === 1 && rows[0].subtitle.indexOf("10 kilometers") === 0, "read as it was meant")
                T.ok(rows.length === 1 && rows[0].subtitle.indexOf("6.213711922 mi") > 0, "the full answer in the second line")
                T.eq(LauncherService.results("10 km to mi", "All")[0].key, "convert", "and first in the plain search")
            }
            LauncherService.launcherClosed()
            T.eq(LauncherService.convertAnswers, {}, "closing the launcher forgets the answers")
            T.eq(LauncherService.recentPath, "", "and lets the recent files go")
            if (LauncherService.qalcMissing) {
                T.finish("LauncherRunTest")
                return
            }
            // A run the close overtakes: its answer comes for no one.
            LauncherService.queueConversion(C.parse("20 C in F"))
            LauncherService.startConversion()
            LauncherService.launcherClosed()
            overtaken.start()
        }
    }

    Timer {
        id: overtaken
        interval: 1500
        onTriggered: {
            T.eq(LauncherService.convertAnswers, {}, "a run still going at the close leaves no answer behind")
            T.finish("LauncherRunTest")
        }
    }
}
