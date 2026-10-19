import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/ipc/IpcLogic.js" as I
import "../../services/profile/ProfileLogic.js" as P

// What shell.qml's IPC `get` handlers hand out (services/ipc/IpcLogic.js):
// `settings get` keeps the private settings to itself, and `audio get`
// names sinks by id, not by a node name that carries a Bluetooth address.
// Then what the handlers take: a popup's rect with no NaN or infinity in
// it, a control center page that is one, and several settings either all
// allowed or none written - read against the control center's own pages and
// shell.qml as it is.
ShellRoot {
    // The runner copies the whole tree beside the test.
    FileView { id: shellEntry; path: Quickshell.shellPath("shell.qml"); blockLoading: true }
    FileView { id: controlCenter; path: Quickshell.shellPath("shell/controlcenter/ControlCenter.qml"); blockLoading: true }

    // The body of one IpcHandler in shell.qml, by its target.
    function handler(text, target) {
        const start = text.indexOf('target: "' + target + '"')
        if (start < 0) return ""
        const end = text.indexOf("\n    }", start)
        return text.slice(start, end < 0 ? text.length : end)
    }

    Component.onCompleted: {
        // ---- settings get ------------------------------------------------------------
        T.eq(["weather.locationName", "weather.lat", "weather.lon", "colorPicker.history", "wallpaper.recentFolders",
              "calendar.hiddenCalendars", "wallpaper.path", "wallpaper.folder", "recording.folder", "launcher.searchUrl"]
             .filter(path => !I.privateSetting(path)), [], "the place, the histories, the calendars, the paths")
        T.ok(I.privateSetting("weather") && I.privateSetting("calendar") && I.privateSetting("wallpaper"),
             "a group that holds one: its whole object would carry it")
        T.ok(I.privateSetting("") && I.privateSetting(undefined) && I.privateSetting("  "), "and the whole file")
        T.ok(I.privateSetting("power.battery.lidAction") && I.privateSetting("display.x11Scale"), "a key inside a private group")
        T.ok(P.GLOBAL_SETTINGS.every(path => I.privateSetting(path)), "everything a profile leaves out as this machine's or this person's")
        T.eq(["appearance.theme", "appearance", "dock.position", "weather.enabled", "weatherly", "launcher.searchEngine"]
             .filter(path => I.privateSetting(path)), [], "the look is not private, nor a name that only starts alike")
        T.eq(I.withheldAnswer("Invented Town", ""), { withheld: true, set: true }, "only whether it is set") // private-data: invented
        T.eq(I.withheldAnswer({ lat: 0, lon: 0 }, { lat: 0, lon: 0 }), { withheld: true, set: false }, "a default is not set")
        T.ok(JSON.stringify(I.withheldAnswer("Invented Town", "")).indexOf("Invented") < 0, "the value never in the answer")
        T.ok(I.privateSetting("login.wallpaper") && I.privateSetting("login"),
             "the login screen's picture, a path like wallpaper.path, and the group that holds it")
        T.ok(!I.privateSetting("login.dateFormat") && !I.privateSetting("loginx"), "but not its other keys")

        // ---- audio get -----------------------------------------------------------------
        const sinks = [{ id: 51, name: "alsa_output.pci-0000_00_1f.3.analog-stereo" },
                       { id: 77, name: "bluez_output.00_11_22_33_44_55.1" }, null]
        T.eq(I.sinkIds(sinks), [51, 77], "sinks by id")
        T.ok(JSON.stringify(I.sinkIds(sinks)).indexOf("bluez") < 0, "no node name, no address")
        T.eq([I.sinkIdOf("bluez_output.00_11_22_33_44_55.1", sinks), I.sinkIdOf("", sinks), I.sinkIdOf("gone", sinks)],
             [77, "", ""], "a stream's target as its sink's id, the default as \"\"")
        T.eq([I.sinkFor("77", sinks).id, I.sinkFor("alsa_output.pci-0000_00_1f.3.analog-stereo", sinks).id], [77, 51],
             "route takes an id or a name")
        T.eq([I.sinkFor("99", sinks), I.sinkFor("", sinks), I.sinkFor("default", sinks)], [null, null, null], "nothing else")

        // ---- popup openAt ----------------------------------------------------------------
        T.eq(I.originArgs(100, 0, 40, 30), { anchorX: 120, anchorTop: 30, originX: 100, originY: 0, originWidth: 40, originHeight: 30 },
             "a pill's rect: the place below it and the rect it grows out of")
        T.eq([NaN, Infinity, -Infinity].map(bad => [I.originArgs(bad, 0, 40, 30), I.originArgs(0, bad, 40, 30),
                                                 I.originArgs(0, 0, bad, 30), I.originArgs(0, 0, 40, bad)]),
             [[null, null, null, null], [null, null, null, null], [null, null, null, null]],
             "a NaN or an infinity anywhere is no rect (the client hands \"nan\" and \"inf\" on as numbers)")
        T.eq([I.originArgs(0, 0, 0, 30), I.originArgs(0, 0, 40, -1), I.originArgs("1", 0, 40, 30)], [null, null, null],
             "nor an empty one, nor one that is no number")
        const popup = handler(shellEntry.text(), "popup")
        T.ok(popup.indexOf("IpcLogic.originArgs(") >= 0, "and shell.qml's openAt asks it")

        // ---- controlCenter openPage --------------------------------------------------------
        const chain = controlCenter.text().match(/detailPage:[\s\S]*?: null/)
        const pages = chain ? (chain[0].match(/page === "(\w+)"/g) || []).map(entry => entry.split('"')[1]) : []
        T.eq(pages.slice().sort(), I.CONTROL_CENTER_PAGES.slice().sort(), "the pages are the control center's own")
        T.ok(I.CONTROL_CENTER_PAGES.every(page => I.controlCenterPage(page)) && I.controlCenterPage(""),
             "each of them, and \"\" for the overview")
        T.eq(["foo", "Network", "overview", undefined].filter(page => I.controlCenterPage(page)), [undefined],
             "nothing else (no page at all is the overview)")
        T.ok(handler(shellEntry.text(), "controlCenter").indexOf("IpcLogic.controlCenterPage(page)") >= 0,
             "and shell.qml's openPage asks it")

        // ---- bar setWorkspaces ---------------------------------------------------------------
        const allowed = { "workspaces.mode": ["open", "gapless", "fixed"], "workspaces.count": [1, 2, 3, 10] }
        T.ok(I.allAllowed({ "workspaces.mode": "fixed", "workspaces.count": 3 }, allowed), "both allowed")
        T.eq([I.allAllowed({ "workspaces.mode": "open", "workspaces.count": 99 }, allowed),
              I.allAllowed({ "workspaces.mode": "bogus", "workspaces.count": 3 }, allowed),
              I.allAllowed({ "workspaces.mode": "open", "nope.key": 1 }, allowed),
              I.allAllowed({ "workspaces.count": "3" }, allowed)], [false, false, false, false],
             "one refused is all refused: a count out of range, an unknown mode, a key with no list, a string for a number")
        T.ok(handler(shellEntry.text(), "bar").indexOf("IpcLogic.allAllowed(values, SettingsService.allowed) && SettingsService.setAll(values)") >= 0,
             "and setWorkspaces checks both before it writes either, in one write")

        // ---- brightness preview ----------------------------------------------------------------
        const brightness = handler(shellEntry.text(), "brightness")
        T.ok(brightness.indexOf("function preview(") >= 0 && handler(shellEntry.text(), "kbdBacklight").indexOf("function preview(") >= 0,
             "the screen's backlight can be previewed like the keyboard's, without writing the host's")
        T.finish("IpcLogicTest")
    }
}
