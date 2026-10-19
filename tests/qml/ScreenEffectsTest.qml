import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/hypr/ScreenEffectsLogic.js" as E
import "../../services/hypr/HyprCommands.js" as H

// The screen zoom's steps and the color filters' shaders
// (ScreenEffectsLogic), and what they become as compositor options.
ShellRoot {
    Component.onCompleted: {
        // Zoom: a ladder, the same way in and out.
        T.eq(E.zoomStep(1, 1), 1.25, "the first step in is 125 %")
        T.eq(E.zoomStep(1.25, 1), 1.5, "then 150 %")
        T.eq(E.zoomStep(2, -1), 1.5, "a step out goes back the same way")
        T.eq(E.zoomStep(1, -1), 1, "out from 100 % stays at 100 %")
        T.eq(E.zoomStep(8, 1), 8, "in at the top stays at the top")
        T.eq(E.zoomStep(1.7, 1), 2, "between two rungs, in goes to the next one up")
        T.eq(E.zoomStep(1.7, -1), 1.5, "and out to the next one down")
        T.eq(E.zoomStep(2, 0), 2, "no direction is no step")
        let factor = 1
        for (let i = 0; i < 3; ++i) factor = E.zoomStep(factor, 1)
        for (let i = 0; i < 3; ++i) factor = E.zoomStep(factor, -1)
        T.eq(factor, 1, "three in and three out land where they started")
        T.eq([E.clampZoom("x"), E.clampZoom(0.5), E.clampZoom(20), E.clampZoom(2.345)], [1, 1, 8, 2.35],
             "a factor from IPC is held to 1-8")
        T.eq([E.zoomActive(1), E.zoomActive(1.25)], [false, true], "zoomed above 100 %")
        T.eq([E.zoomNeedsSend(1, 1), E.zoomNeedsSend(2, 1), E.zoomNeedsSend(1, 2), E.zoomNeedsSend(2, 2), E.zoomNeedsSend(2, 2.001)],
             [true, true, true, false, false],
             "a change is sent, and 100 % always: a shell restarted while zoomed still has its way back")
        T.eq([E.zoomLabel(1), E.zoomLabel(2), E.zoomLabel(1.25)], ["Off", "2×", "1.25×"], "what the OSD says")
        T.eq(E.zoomOptions(3), { "cursor:zoom_factor": 3 }, "Hyprland's option")
        const zoom = H.options(E.zoomOptions(2))
        T.eq([zoom.legacy, zoom.lua], ["keyword cursor:zoom_factor 2", "hl.config({ cursor = { zoom_factor = 2 } })"],
             "the option in both dialects")

        // Color filters.
        T.eq(E.FILTERS.map(item => item.id), ["grayscale", "deuteranopia", "protanopia", "tritanopia", "invert"], "the filters")
        T.eq([E.normalizeFilter("protanopia"), E.normalizeFilter("sepia"), E.normalizeFilter(undefined)],
             ["protanopia", "grayscale", "grayscale"], "an unknown filter is the default one")
        T.eq(E.shaderPath(true, "grayscale", "/opt/shell/shaders/"), "/opt/shell/shaders/grayscale.frag", "the shader under the shell's folder")
        T.eq(E.shaderPath(false, "grayscale", "/opt/shell/shaders"), "", "off is no shader")
        T.eq(E.shaderPath(true, "../../etc/passwd", "/opt/shell/shaders"), "/opt/shell/shaders/grayscale.frag",
             "a name from settings.json is never a path")
        T.eq(E.shaderPath(true, "invert", ""), "", "no folder, no shader")
        const on = H.options(E.filterOptions(true, "tritanopia", "/s"))
        T.eq([on.legacy, on.legacyEmpty, on.lua],
             ["keyword decoration:screen_shader /s/tritanopia.frag", [], "hl.config({ decoration = { screen_shader = \"/s/tritanopia.frag\" } })"],
             "a filter on in both dialects")
        const off = H.options(E.filterOptions(false, "tritanopia", "/s"))
        T.eq([off.legacy, off.legacyEmpty, off.lua], ["", ["decoration:screen_shader"], "hl.config({ decoration = { screen_shader = \"\" } })"],
             "off empties the option, in the legacy dialect as a call of its own")
        T.eq([E.nextFilter("grayscale"), E.nextFilter("invert"), E.nextFilter("nothing")], ["deuteranopia", "grayscale", "deuteranopia"],
             "the next filter wraps")
        T.eq(E.filterLabel("deuteranopia"), "Red-green (green weak)", "a label")
        T.eq(E.filterOptionsList().length, E.FILTERS.length, "a picker lists every filter")
        T.finish("ScreenEffectsTest")
    }
}
