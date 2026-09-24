import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/input/InputLogic.js" as I

ShellRoot {
    Component.onCompleted: {
        const list = I.parseXkbList([
            "! model", "  pc105           Generic 105-key PC",
            "! layout", "  us              English (US)", "  de              German",
            "! variant", "  nodeadkeys      de: German (no dead keys)", "  intl            us: English (US, intl., with dead keys)",
            "! option", "  grp:alt_shift_toggle Alt+Shift"
        ].join("\n"))
        T.eq(list.layouts.map(l => l.value), ["us", "de"], "layouts sorted by label")
        T.eq(list.variants.de, [{ value: "nodeadkeys", label: "German (no dead keys)" }], "variants grouped by layout")
        T.eq(Object.keys(list.variants).sort(), ["de", "us"], "options section ignored")

        const settings = {
            "input.kbLayout": "de", "input.kbVariant": "", "input.repeatRate": 200, "input.repeatDelay": 10,
            "input.sensitivity": 0.333, "input.accelProfile": "weird", "input.mouseNaturalScroll": false,
            "input.touchpadNaturalScroll": true, "input.tapToClick": false, "input.disableWhileTyping": true
        }
        const values = I.values(path => settings[path])
        T.eq([values.repeat_rate, values.repeat_delay, values.sensitivity, values.accel_profile], [80, 150, 0.33, "adaptive"], "values clamped")
        T.eq(values["touchpad:scroll_factor"], 1, "missing scroll factor keeps the default")
        const scrolled = path => path === "input.touchpadScrollFactor" ? 1.35 : settings[path]
        T.eq(I.values(scrolled)["touchpad:scroll_factor"], 1.35, "scroll factor kept")
        T.eq(I.values(path => path === "input.touchpadScrollFactor" ? 9 : settings[path])["touchpad:scroll_factor"], 2, "scroll factor clamped")
        T.eq(I.values(path => path === "input.kbLayout" ? "de; exec rm" : settings[path]).kb_layout, "de", "layout injection rejected")
        // A setting that is not there is its default, not NaN: NaN is what
        // HyprCommands.luaValue refuses, and one refused option took every
        // input option down with it.
        const bare = I.values(path => undefined)
        T.eq([bare.repeat_rate, bare.repeat_delay, bare.sensitivity], [25, 600, 0], "missing numbers fall back to the defaults")
        T.eq([bare.kb_layout, bare.kb_variant], ["de", ""], "and a missing layout is not the word 'undefined'")
        T.eq(I.values(path => path === "input.repeatRate" ? "fast" : settings[path]).repeat_rate, 25, "so does a number that is not one")
        const options = I.optionMap(values)
        T.eq([options["input:kb_variant"], options["input:touchpad:tap-to-click"]], ["", false], "option map keeps types")
        T.eq(Object.keys(options).length, 11, "one option per setting")
        T.finish("InputTest")
    }
}
