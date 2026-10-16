import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/startmenu/StartMenuLogic.js" as S
import "../../services/system/UserDirsLogic.js" as U

// The start menu's arithmetic (services/startmenu/StartMenuLogic.js): the
// fastfetch logo cut into runs, the Saturn on the button, the A-Z list, the
// keys, the frequent apps, the places, the header's second line and the
// menus.
ShellRoot {
    FileView {
        id: saturnFile
        path: Qt.resolvedUrl("../../config/builtin-profiles/buchhwin/saturn.txt").toString().replace("file://", "")
        blockLoading: true
    }

    function app(id, name, extra) { return Object.assign({ id: id, name: name === undefined ? id : name, noDisplay: false }, extra || {}) }

    Component.onCompleted: {
        // ---- the ASCII logo -------------------------------------------------------
        T.eq(S.asciiRuns("$1ab$2cd").runs, [{ row: 0, col: 0, text: "ab", tone: 1 }, { row: 0, col: 2, text: "cd", tone: 2 }],
             "a colour change starts a run")
        T.eq(S.asciiRuns("a b").runs.map(run => run.col), [0, 2], "a space ends one")
        T.eq(S.asciiRuns("$2x\ny").runs.map(run => run.tone), [2, 1], "every line starts in the first colour")
        T.eq(S.asciiRuns("   x").runs[0].col, 3, "leading spaces are columns")
        T.eq(S.asciiRuns("a$$b").runs[0].text, "a$b", "$$ is a dollar sign")
        T.eq(S.asciiRuns("a$xb").runs[0].text, "a$xb", "any other $ is itself")
        T.eq(S.asciiRuns("ab\r\ncd\r\n\n$2  \n").rows, 2, "CR dropped, empty last lines too")
        T.eq(S.asciiRuns("ab   ").columns, 2, "the width ends at the last character")
        T.eq(S.asciiRuns("").runs, [], "no logo")
        const saturn = S.asciiRuns(saturnFile.text())
        T.eq([saturn.rows, saturn.columns, saturn.runs.length], [15, 55, 35], "the shipped Saturn: 15 rows, 55 columns, 35 runs")
        T.eq(saturn.runs[0], { row: 0, col: 46, text: "_.oo.", tone: 2 }, "its first run is the ring's tip")
        T.eq(saturn.runs[saturn.runs.length - 1], { row: 14, col: 1, text: "^^", tone: 2 }, "and its last")
        T.ok(saturn.runs.some(run => run.row === 7 && run.col === 35 && run.text === "-.." && run.tone === 1),
             "the planet goes on behind the ring")
        T.ok(saturn.runs.every(run => run.tone === 1 || run.tone === 2), "two colours, planet and ring")

        // ---- the Saturn on the button ------------------------------------------------
        const g = S.saturnGeometry(177, 100)
        const tilt = g.tilt * Math.PI / 180
        const halfW = Math.sqrt(Math.pow(g.ringA * Math.cos(tilt), 2) + Math.pow(g.ringB * Math.sin(tilt), 2)) + g.stroke / 2
        const halfH = Math.sqrt(Math.pow(g.ringA * Math.sin(tilt), 2) + Math.pow(g.ringB * Math.cos(tilt), 2)) + g.stroke / 2
        T.near(halfW, 88.5, "the tilted ring fills the box's width", 0.5)
        T.near(halfH, 50, "and its height", 0.5)
        T.ok(g.planet <= 50 && g.planet === 0.4 * 100, "the planet in the middle, 0.4 of the height")
        T.near(g.ringA / g.planet, 2.35, "the ring 2.35 times the planet", 0.01)
        T.eq(S.saturnGeometry(354, 100).planet, 40, "a wider box: the height decides")
        T.eq([S.saturnWidth(22), S.saturnWidth(0)], [39, 0], "the width for a height")

        // ---- all apps -----------------------------------------------------------------
        T.eq(["Ärger", "émail", "7-Zip", "", "zsh", "Ωmega"].map(S.letterOf), ["A", "E", "#", "#", "Z", "Ω"], "letters")
        const all = S.alphabet([app("b", "beta"), app("a2", "Alpha"), app("seven", "7-Zip"), app("ae", "Ärger"),
                                app("noname", ""), app("a2", "Alpha")])
        T.eq(all.letters, ["#", "A", "B", "N"], "# first, then A-Z; no name files by the id")
        T.eq(all.ids, ["seven", "a2", "ae", "b", "noname"], "by name within a letter, each app once")
        T.eq(all.rows.filter(row => row.kind === "header").length, 4, "one header a letter")
        T.eq(all.rows.filter(row => row.kind === "app").map(row => row.appIndex), [0, 1, 2, 3, 4], "apps counted on their own")
        T.eq(all.rows[0].key + " " + all.rows[1].key, "h:# a:seven", "keyed by strings")
        T.eq(S.alphabet(null).rows, [], "no apps")

        // ---- keys ---------------------------------------------------------------------
        const zones = [{ id: "pinned", count: 10, columns: 5 }, { id: "frequent", count: 3, columns: 2 },
                       { id: "places", count: 6, columns: 6 }, { id: "footer", count: 3, columns: 3 }]
        const field = { zone: "", index: 0 }
        T.eq(S.move(field, "down", zones), { zone: "pinned", index: 0 }, "down from the field: the first zone")
        T.eq(S.move({ zone: "pinned", index: 2 }, "down", zones), { zone: "pinned", index: 7 }, "a row down")
        T.eq(S.move({ zone: "pinned", index: 7 }, "down", zones), { zone: "frequent", index: 1 }, "past the grid into the next zone, column kept")
        T.eq(S.move({ zone: "pinned", index: 4 }, "down", [{ id: "pinned", count: 7, columns: 5 }]), { zone: "pinned", index: 6 },
             "into a shorter last row")
        T.eq(S.move({ zone: "pinned", index: 1 }, "up", zones), field, "up from the first row: the field")
        T.eq(S.move({ zone: "frequent", index: 0 }, "up", zones), { zone: "pinned", index: 5 }, "up into the last row above")
        T.eq(S.move({ zone: "pinned", index: 4 }, "right", zones), { zone: "pinned", index: 4 }, "right at a row's end stays")
        T.eq(S.move({ zone: "pinned", index: 5 }, "left", zones), { zone: "pinned", index: 5 }, "left at its start too")
        T.eq(S.move({ zone: "frequent", index: 2 }, "right", zones), { zone: "frequent", index: 2 }, "no item to the right")
        T.eq(S.move({ zone: "footer", index: 2 }, "tab", zones), field, "tab past the last zone: the field")
        T.eq(S.move(field, "backtab", zones), { zone: "footer", index: 0 }, "shift+tab from the field: the last zone")
        T.eq(S.move({ zone: "frequent", index: 1 }, "backtab", zones), { zone: "pinned", index: 0 }, "and back one")
        T.eq(S.move({ zone: "places", index: 3 }, "end", zones), { zone: "places", index: 5 }, "end stays in its zone")
        T.eq(S.move({ zone: "places", index: 3 }, "home", zones), { zone: "places", index: 0 }, "home too")
        T.eq(S.move({ zone: "all", index: 3 }, "pageDown", [{ id: "all", count: 9, columns: 1 }], 8), { zone: "all", index: 8 }, "a page, clamped")
        T.eq(S.move({ zone: "all", index: 3 }, "pageUp", [{ id: "all", count: 9, columns: 1 }], 8), { zone: "all", index: 0 }, "and up")
        T.eq(S.move({ zone: "gone", index: 3 }, "left", zones), field, "a zone that went: the field")
        T.eq(S.move({ zone: "pinned", index: 3 }, "down", []), field, "no zones: the field")
        T.eq(S.move({ zone: "pinned", index: 30 }, "left", zones), { zone: "pinned", index: 8 }, "an index past the end is clamped first")

        // ---- frequent ------------------------------------------------------------------
        const installed = [app("code"), app("kitty"), app("hidden", "hidden", { noDisplay: true }), app("dolphin")]
        T.eq(S.frequent(["code", "gone", "hidden", "kitty", "dolphin"], installed, ["kitty"], 5).map(entry => entry.id),
             ["code", "dolphin"], "installed, shown, not pinned")
        T.eq(S.frequent(["code", "kitty", "dolphin"], installed, [], 2).length, 2, "a limit")
        T.eq(S.frequent(["code"], null, null), [], "no entries")

        // ---- places ----------------------------------------------------------------------
        const german = 'XDG_DOCUMENTS_DIR="$HOME/Dokumente"\nXDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_PICTURES_DIR="/data/Bilder"\n'
            + 'XDG_MUSIC_DIR="$(rm -rf ~)"\nXDG_VIDEOS_DIR="$HOME"\n'
        T.eq(S.places(german, "/home/u").map(place => place.id + "=" + place.path),
             ["home=/home/u", "documents=/home/u/Dokumente", "downloads=/home/u/Downloads", "pictures=/data/Bilder"],
             "German folders, an absolute one; shell code and a bare $HOME are left out")
        T.eq(S.places("", "/home/u").map(place => place.id), ["home"], "without the file: home alone")
        T.ok(S.places(german, "/home/u").every(place => place.glyph.length > 0 && place.label.length > 0), "each with a glyph and a name")
        T.eq(U.userDir('XDG_DOWNLOAD_DIR="$HOME/Downloads"', "DOWNLOAD", "/h"), "/h/Downloads", "one key")
        T.eq(U.userDir('XDG_DOWNLOAD_DIR="$HOME/Downloads"', "down.*", "/h"), "", "a key is a name, never a pattern")

        // ---- the header's second line ------------------------------------------------------
        T.eq([S.uptimeSeconds("12345.67 54321.00\n"), S.uptimeSeconds("garbage"), S.uptimeSeconds("")], [12345, -1, -1], "/proc/uptime")
        T.eq([0, 59, 60, 3600, 8040, 90000, 3 * 86400 + 59].map(S.uptimeText),
             ["0 min", "0 min", "1 min", "1 h", "2 h 14 min", "1 d 1 h", "3 d"], "the two largest units")
        T.eq(S.uptimeText(-1), "", "no uptime")
        T.eq(S.infoRows("Arch Linux", "7.2.9-arch1-1\n", 8040).map(row => row.branch + row.key + "=" + row.value),
             ["╭─os=Arch Linux", "├─kernel=7.2.9-arch1-1", "╰─uptime=2 h 14 min"], "fastfetch's rows")
        T.eq(S.infoRows("Arch Linux", "", -1).map(row => row.branch + row.key), ["──os"], "what is known; one row on its own")
        T.eq(S.infoRows("", "", -1), [], "nothing known")

        // ---- menus -----------------------------------------------------------------------
        const kinds = rows => rows.map(row => row.kind + (row.enabled === false ? "(off)" : ""))
        T.eq(kinds(S.appMenuRows({ source: "pinned", pinned: true, pinIndex: 0, pinCount: 3, dockEnabled: true,
                                   actions: [{ id: "new-window", name: "New Window" }, null] })),
             ["open", "action", "unpinStart", "moveRight", "pinDock"], "a pinned tile, first of three: no move left")
        T.eq(kinds(S.appMenuRows({ source: "pinned", pinned: true, pinIndex: 2, pinCount: 3 })),
             ["open", "unpinStart", "moveLeft"], "the last one; no dock, no dock row")
        T.eq(kinds(S.appMenuRows({ source: "all", pinned: false, pinnedFull: true, dockEnabled: true, inDock: false, dockFull: true })),
             ["open", "pinStart(off)", "pinDock(off)"], "both full")
        T.eq(kinds(S.appMenuRows({ source: "frequent", dockEnabled: true, inDock: true, actions: "nonsense" })),
             ["open", "pinStart", "unpinDock"], "on the dock already; actions that are no list")
        T.eq(S.powerRows().map(row => row.kind + (row.confirm ? "?" : "")), ["suspend", "logout?", "reboot?", "poweroff?"],
             "sleep at once, the rest asks")
        const categories = [{ id: "browser", current: "brave-browser.desktop" }]
        T.eq(S.dockState(["org.kde.dolphin"], "org.kde.dolphin.desktop", categories), { pinned: true, pin: "org.kde.dolphin" }, "pinned by its id")
        T.eq(S.dockState(["@browser"], "brave-browser", categories), { pinned: true, pin: "@browser" }, "pinned as the default browser")
        T.eq(S.dockState(["@browser"], "brave-browser", []), { pinned: false, pin: "brave-browser" }, "the defaults not read yet")
        T.eq(S.dockState(["@settings"], "", categories), { pinned: false, pin: "" }, "no id")

        T.finish("StartMenuTest")
    }
}
