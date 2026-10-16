import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/ipc/IpcLogic.js" as I
import "../../services/profile/ProfileLogic.js" as P

// What shell.qml's IPC `get` handlers hand out (services/ipc/IpcLogic.js):
// `settings get` keeps the private settings to itself (security#0), and
// `audio get` names sinks by id, not by a node name that carries a
// Bluetooth address (security#9).
ShellRoot {
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
        T.finish("IpcLogicTest")
    }
}
