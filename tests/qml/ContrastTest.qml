import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/ContrastLogic.js" as C

ShellRoot {
    Component.onCompleted: {
        T.near(C.contrast("#000000", "#ffffff"), 21, "black on white", 1e-6)
        T.near(C.contrast("#ffffff", "#000000"), 21, "order does not matter", 1e-6)
        T.near(C.contrast("#4f8ff7", "#4f8ff7"), 1, "same colour")
        T.eq([C.contrast("nope", "#ffffff"), C.contrast("#ffffff", "")], [-1, -1], "invalid colours")
        T.near(C.contrast("#767676", "#ffffff"), 4.54, "WCAG reference grey", 0.01)

        const light = "#ffffff"
        const dark = "#15171c"
        T.eq(C.textOn("#4f8ff7", light, dark), light, "default blue keeps white text")
        T.eq(C.textOn("#8b6cf6", light, dark), light, "purple keeps white text")
        T.eq(C.textOn("#50e2cb", light, dark), dark, "light teal gets dark text")
        T.eq(C.textOn("#e7b43c", light, dark), dark, "yellow gets dark text")
        T.eq(C.textOn("#f28b3c", light, dark), dark, "orange gets dark text")
        T.eq(C.textOn("#4f8ff7", light, dark, 4.5), dark, "a stricter minimum picks the better one")
        T.eq(C.textOn("#000000", light, dark, 30), light, "light stays when dark is not better")
        T.eq(C.textOn("nope", light, dark), light, "invalid background keeps the light colour")

        T.eq(C.toHex({ r: 1, g: 0.5, b: 0 }), "#ff8000", "hex from channels")
        T.eq(C.toHex({ r: 2, g: -1, b: 0.0 }), "#ff0000", "channels are clamped")
        const hsl = C.toHsl({ r: 0x4f / 255, g: 0x8f / 255, b: 0xf7 / 255 })
        T.eq(C.toHex(C.fromHsl(hsl)), "#4f8ff7", "HSL round trip")
        T.eq(C.toHex(C.fromHsl(C.toHsl({ r: 0.5, g: 0.5, b: 0.5 }))), "#808080", "grey round trip")

        const lightBase = "#e9ebef"
        const darkBase = "#1a1d25"
        T.eq(C.readable("#4f8ff7", darkBase), "#4f8ff7", "readable colours stay unchanged")
        T.eq(C.readable("#4F8FF7", darkBase), "#4f8ff7", "result is normalized")
        const blue = C.readable("#4f8ff7", lightBase)
        T.ok(C.contrast(blue, lightBase) >= 4.5, "blue is darkened to 4.5:1 on light surfaces: " + blue)
        T.ok(C.contrast(blue, lightBase) < 5, "only as far as needed: " + blue)
        const rgb = { r: parseInt(blue.slice(1, 3), 16), g: parseInt(blue.slice(3, 5), 16), b: parseInt(blue.slice(5, 7), 16) }
        T.ok(rgb.b > rgb.g && rgb.g > rgb.r, "hue stays blue: " + blue)
        const lighter = C.readable("#3a2a8a", darkBase)
        T.ok(C.contrast(lighter, darkBase) >= 4.5, "dark colours are lightened on dark surfaces: " + lighter)
        T.ok(C.contrast(C.readable("#50e2cb", lightBase, 3), lightBase) >= 3, "custom ratio")
        T.eq(C.readable("x", lightBase), "", "invalid foreground")
        T.eq(C.readable("#4f8ff7", "x"), "#4f8ff7", "invalid background keeps the colour")

        const accents = ["#4f8ff7", "#8b6cf6", "#d46ad8", "#ef5f67", "#f28b3c", "#e7b43c", "#4fbf73", "#2eb8a8", "#8f97a6", "#50e2cb", "#ffffff", "#000000"]
        T.ok(accents.every(accent => C.contrast(C.readable(accent, lightBase), lightBase) >= 4.5), "every accent reads on light surfaces")
        T.ok(accents.every(accent => C.contrast(C.readable(accent, darkBase), darkBase) >= 4.5), "every accent reads on dark surfaces")
        T.finish("ContrastTest")
    }
}
