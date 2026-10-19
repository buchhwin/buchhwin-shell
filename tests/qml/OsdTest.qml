import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/osd/OsdLogic.js" as O

// When the on-screen display keeps quiet (shell/osd/OsdLogic.js): per kind
// for the panel that is open, a settling time after the default device
// changes, and the notch's display slot written only while it holds the OSD.
ShellRoot {
    Component.onCompleted: {
        // ---- a panel that shows the same control ----------------------------
        const tiles = ["wifi", "brightness", "battery", "audio"]
        T.eq(O.suppressed("volume", "volumePopup", tiles), true, "the volume popup has the volume")
        T.eq(O.suppressed("mic", "volumePopup", tiles), true, "and the microphone switch")
        T.eq(O.suppressed("brightness", "volumePopup", tiles), false, "but no brightness: the keys show it")
        T.eq(O.suppressed("kbdBacklight", "volumePopup", tiles), false, "nor the keyboard light")
        T.eq(O.suppressed("volume", "controlCenter", tiles), true, "the control center with an audio tile has the volume")
        T.eq(O.suppressed("brightness", "controlCenter", tiles), true, "and with a brightness tile the brightness")
        T.eq(O.suppressed("mic", "controlCenter", tiles), false, "no microphone tile: the mic key shows")
        T.eq(O.suppressed("mic", "controlCenter", tiles.concat(["microphone"])), true, "with one it does not")
        T.eq(O.suppressed("kbdBacklight", "controlCenter", tiles), false, "the keyboard light has no tile")
        T.eq(O.suppressed("volume", "controlCenter", ["wifi"]), false, "a control center without the audio tile")
        T.eq(O.suppressed("brightness", "controlCenter", ["wifi"]), false, "nor the brightness one")
        T.eq(O.suppressed("volume", "controlCenter", undefined), false, "no tiles known")
        T.eq(O.suppressed("volume", "", tiles), false, "no panel open")
        T.eq(O.suppressed("volume", "launcher", tiles), false, "a panel without the control")

        // ---- a default device that changes ---------------------------------
        const headset = { name: "headset" }
        const builtin = { name: "built-in" }
        T.eq(O.deviceChanged(null, builtin, false), false, "the first device the shell meets is where it starts")
        T.eq(O.deviceChanged(builtin, headset, true), true, "a headset taking over is not the user's doing")
        T.eq(O.deviceChanged(headset, null, true), true, "nor one unplugged with nothing in its place")
        T.eq(O.deviceChanged(null, builtin, true), true, "nor the device that comes back after it")
        T.eq(O.deviceChanged(builtin, builtin, true), false, "the same device is no change")

        // ---- how far from the screen's sides ---------------------------------
        T.eq(O.sideMargin(null, 1920, 16, 12), 16, "no origin: the screen margin")
        T.eq(O.sideMargin({ x: 900, y: 0, width: 120, height: 30 }, 1920, 16, -1), 16, "out of the middle: the margin")
        T.eq(O.sideMargin({ x: 1700, y: 0, width: 40, height: 30 }, 1920, 16, 12), 12,
             "out of an item in the status pill: the pill's outer edge at the windows' gap")
        T.eq(O.sideMargin({ x: 1700, y: 0, width: 40, height: 30 }, 1920, 16, -1), 16, "an attached bar: the margin")
        T.eq(O.sideMargin({ x: 1700, y: 0, width: 40, height: 30 }, 1920, 16, 24), 16, "never further in than the margin")
        T.eq(O.sideMargin({ x: 8, y: 0, width: 300, height: 34 }, 1920, 16, -1), 8, "a notch closer to the edge than the margin")
        T.eq(O.sideMargin({ x: -4, y: 0, width: 40, height: 30 }, 1920, 16, 12), 0, "never less than 0")

        // ---- the notch's slot ------------------------------------------------
        T.eq(O.publishes(true, false), true, "into the notch")
        T.eq(O.publishes(true, true), true, "and while it is there, every change")
        T.eq(O.publishes(false, true), true, "once more to leave it")
        T.eq(O.publishes(false, false), false, "and nothing while it is not there")
        T.finish("OsdTest")
    }
}
