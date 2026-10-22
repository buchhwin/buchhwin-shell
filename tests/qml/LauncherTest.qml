import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/LaunchLogic.js" as Launch
import "../../services/launcher/FileSearch.js" as Files
import "../../services/launcher/WindowClassLogic.js" as WindowClass

// How the launcher starts an entry: always through scripts/launch-app.sh (a
// unit named after the entry, and the session's environment instead of the
// shell's own settings), the entry's working directory kept, overrides by
// their session launcher, and a Terminal=true entry in the session's
// terminal (scripts/launch-terminal.sh, which ends in launch-app.sh too).
ShellRoot {
    Component.onCompleted: {
        const script = name => "/s/" + name
        const overrides = { "kitty": "launch-kitty.sh", "brave-browser": "launch-brave.sh" }

        T.eq(Launch.launchContext({ id: "org.kde.dolphin", command: ["dolphin", "--new-window"], workingDirectory: "" }, overrides, script),
             { command: ["/s/launch-app.sh", "org.kde.dolphin", "dolphin", "--new-window"] },
             "an entry runs through launch-app.sh, named after its id")
        T.eq(Launch.launchContext({ id: "game", command: ["./run"], workingDirectory: "/opt/game" }, overrides, script),
             { command: ["/s/launch-app.sh", "game", "./run"], workingDirectory: "/opt/game" },
             "the entry's Path= goes along, as execute() passed it")
        T.eq(Launch.launchContext({ id: "htop", command: ["htop"], runInTerminal: true }, overrides, script),
             { command: ["/s/launch-terminal.sh", "--", "htop"] },
             "a Terminal=true entry runs in the session's terminal (execute() ran it with no terminal at all)")
        T.eq(Launch.launchContext({ id: "btop", command: ["btop", "--utf-force"], runInTerminal: true, workingDirectory: "/srv" }, overrides, script),
             { command: ["/s/launch-terminal.sh", "--", "btop", "--utf-force"], workingDirectory: "/srv" },
             "its arguments after --, never read as the terminal's options, and its Path= kept")
        T.eq(Launch.launchContext({ id: "htop", command: ["htop"], runInTerminal: false }, overrides, script).command,
             ["/s/launch-app.sh", "htop", "htop"], "Terminal=false: launch-app.sh as before")
        T.eq(Launch.launchContext({ id: "kitty", command: ["kitty"], runInTerminal: true }, overrides, script),
             { command: ["/s/launch-kitty.sh"] }, "an override wins over Terminal=true")
        T.eq(Launch.launchContext({ id: "kitty", command: ["kitty"] }, overrides, script),
             { command: ["/s/launch-kitty.sh"] }, "an override starts its session launcher")
        T.eq(Launch.launchContext({ id: "toString", command: ["x"] }, overrides, script).command[0], "/s/launch-app.sh",
             "an id that is a property of every object is no override")
        T.eq(Launch.launchContext({ id: "empty", command: [] }, overrides, script), null, "no command: nothing to run")
        T.eq(Launch.launchContext({ id: "", command: ["x"] }, overrides, script), null, "no id: launch-app.sh would refuse it")
        T.eq(Launch.launchContext(null, overrides, script), null, "no entry")
        // DesktopEntry.command is a list type, not a JS array.
        const listLike = { length: 2, 0: "code", 1: "--new-window" }
        T.eq(Launch.launchContext({ id: "code", command: listLike }, overrides, script).command,
             ["/s/launch-app.sh", "code", "code", "--new-window"], "a list-like command is copied")
        // Web apps and browser actions go through the browser's launcher
        // (wallet, --password-store), with the entry's arguments after it.
        const outlook = { id: "brave-faolnafnngnfdaknnbpnkhgohbobgegn-Default",
            command: ["/opt/brave-bin/brave", "--profile-directory=Default", "--app-id=faolnafnngnfdaknnbpnkhgohbobgegn"] }
        T.eq(Launch.launchContext(outlook, overrides, script).command,
             ["/s/launch-brave.sh", "--profile-directory=Default", "--app-id=faolnafnngnfdaknnbpnkhgohbobgegn"],
             "a Brave web app starts through launch-brave.sh")
        T.eq(Launch.launchContext({ id: "chrome-abc-Default", command: ["/opt/google/chrome/google-chrome", "--app-id=abc"] },
             overrides, script).command, ["/s/launch-chrome.sh", "--app-id=abc"], "a Chrome web app through launch-chrome.sh")
        T.eq(Launch.launchContext({ id: "chromium-app", command: ["chromium", "--app=https://example.org"] },
             overrides, script).command, ["/s/launch-chromium-browser.sh", "--app=https://example.org"], "Chromium the same")
        T.eq(Launch.launchContext({ id: "brave-beta-app", command: ["brave-browser-beta", "--app-id=x"] },
             overrides, script).command[0], "/s/launch-app.sh", "a beta build is another browser: not the stable launcher")
        T.eq(Launch.launchContext({ id: "bravery", command: ["/usr/bin/bravery"] }, overrides, script).command[0],
             "/s/launch-app.sh", "only the exact program names")
        const message = { id: "Neue-Nachricht", name: "Neue Nachricht", command: outlook.command.concat(
            ["--app-launch-url-for-shortcuts-menu-item=https://outlook.office.com/mail/deeplink/compose"]) }
        T.eq(Launch.actionContext(outlook, message, overrides, script).command,
             ["/s/launch-brave.sh"].concat(message.command.slice(1)), "a web app's action through launch-brave.sh")
        const braveEntry = { id: "brave-browser", command: ["brave"] }
        T.eq(Launch.actionContext(braveEntry, { id: "new-private-window", command: ["brave", "--incognito"] }, overrides, script).command,
             ["/s/launch-brave.sh", "--incognito"], "an override's action keeps the override, arguments after it")
        T.eq(Launch.actionContext({ id: "kitty", command: ["kitty"] }, { id: "new", command: ["kitty", "--single-instance"] },
             overrides, script).command, ["/s/launch-kitty.sh", "--single-instance"], "kitty's action through launch-kitty.sh")
        T.eq(Launch.actionContext({ id: "kitty", command: ["kitty"] }, { id: "other", command: ["kitten", "ssh"] },
             overrides, script).command, ["/s/launch-app.sh", "kitty", "kitten", "ssh"], "an action running another program goes the usual way")
        T.eq(Launch.actionContext({ id: "org.kde.dolphin", command: ["dolphin"], workingDirectory: "/srv" },
             { id: "new", command: ["dolphin", "--new-window"] }, overrides, script),
             { command: ["/s/launch-app.sh", "org.kde.dolphin", "dolphin", "--new-window"], workingDirectory: "/srv" },
             "a plain action: launch-app.sh with the entry's id and directory")
        T.eq(Launch.actionContext({ id: "htop", command: ["htop"], runInTerminal: true }, { id: "tree", command: ["htop", "-t"] },
             overrides, script).command, ["/s/launch-terminal.sh", "--", "htop", "-t"], "a terminal entry's action in the terminal")
        T.eq(Launch.actionContext(outlook, { id: "none", command: [] }, overrides, script), null, "an empty action: nothing")
        T.eq(Launch.actionContext(outlook, null, overrides, script), null, "no action")

        // The file search: the home folder as a pattern of its
        // own, so plocate's limit counts only matches under it - with the
        // query alone /usr and the hidden folders used up 200 matches and
        // "png" found nothing at home - and hidden folders left out after.
        T.eq(Files.command("/home/u", "report"), ["plocate", "-i", "-l", "5000", "--", "/home/u/", "report"],
             "the home folder first, both patterns from the index")
        T.eq(Files.paths("/home/u/a.png\n/usr/share/b.png\n/home/u/.cache/c.png\n/home/u/Pictures/.thumbs/d.png\n"
                         + "/home/uv/e.png\n/home/u/Pictures/f.png\n", "/home/u"), ["/home/u/a.png", "/home/u/Pictures/f.png"],
             "only the user's own files: not outside home, not hidden, not a neighbour's home")
        T.eq(Files.paths(Array.from({ length: 80 }, (unused, i) => "/home/u/f" + i).join("\n"), "/home/u").length, 50, "fifty rows at most")
        T.eq(Files.paths("", "/home/u"), [], "nothing found")
        T.eq(Files.indexCommand("/home/u"), ["plocate", "-c", "--", "/home/u/"], "the index is asked for the home folder")
        T.eq([Files.count("0\n"), Files.count("4636\n"), Files.count(""), Files.count("plocate: no db")], [0, 4636, -1, -1],
             "its count; no answer is not none")
        // A window whose entry does not name its class: Citrix Workspace's
        // "selfservice" drew the generic program icon in the dock.
        T.eq([WindowClass.aliasFor("selfservice"), WindowClass.aliasFor("SelfService "), WindowClass.aliasFor("Wfica"), WindowClass.aliasFor("")],
             ["citrix-workspace", "citrix-workspace", "", ""], "Citrix Workspace's window is its entry; the session and the rest go the usual way")
        T.eq(WindowClass.aliasFor("toString"), "", "only the table's own names")

        // A window whose class names no entry: the app its process runs as,
        // from the systemd unit the launcher named after the entry.
        const cgroup = unit => "0::/user.slice/user-1000.slice/user@1000.service/app.slice/" + unit + "\n"
        T.eq(WindowClass.unitEntryIds(cgroup("app-flatpak-com.modrinth.ModrinthApp-2745532194.scope")),
             ["com.modrinth.ModrinthApp", "flatpak-com.modrinth.ModrinthApp"], "a Flatpak's scope names its entry")
        T.eq(WindowClass.unitEntryIds(cgroup("app-buchhwin-brave\\x2dbrowser-7220.scope"))[0], "brave-browser",
             "the shell's own scope, the id unescaped")
        T.eq(WindowClass.unitEntryIds(cgroup("app-org.chromium.Chromium-7220.scope")), ["org.chromium.Chromium"], "a scope without a launcher")
        T.eq(WindowClass.unitEntryIds("0::/app.slice/app-flatpak-com.modrinth.ModrinthApp-27.scope "), ["com.modrinth.ModrinthApp", "flatpak-com.modrinth.ModrinthApp"],
             "a line with a space after it")
        T.eq(WindowClass.unitEntryIds(cgroup("app-org.kde.dolphin@0a1b2c.service")), ["org.kde.dolphin"], "Plasma's service")
        T.eq(WindowClass.unitEntryIds(cgroup("app-gnome-org.gnome.Nautilus@12.service"))[0], "org.gnome.Nautilus", "a launcher before a service's id")
        T.eq([WindowClass.unitEntryIds(cgroup("session-3.scope")), WindowClass.unitEntryIds(cgroup("plasma-kwin.service")),
              WindowClass.unitEntryIds(cgroup("app-.scope")), WindowClass.unitEntryIds(""), WindowClass.unitEntryIds("garbage")],
             [[], [], [], [], []], "no app's unit, no entry")
        T.eq([WindowClass.unitEntryUsable(["Game"]), WindowClass.unitEntryUsable(["System", "TerminalEmulator"]), WindowClass.unitEntryUsable(null)],
             [true, false, true], "a terminal's unit runs every program started in it: never its icon")

        T.finish("LauncherTest")
    }
}
