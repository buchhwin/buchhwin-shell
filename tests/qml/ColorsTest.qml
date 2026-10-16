import Quickshell
import QtQuick
import qs.services
import qs.theme
import qs.shell.widgets
import "Harness.js" as T
import "../../services/appearance/ContrastLogic.js" as C
import "../../services/appearance/PanelStyleLogic.js" as P

// The palette as the panels get it, in the test's own settings sandbox: the
// panels' inks follow the panel colour rather than the theme (a black panel
// in the light theme was dark ink on black), the light panel's floor and the
// inks measured on it, the accent tint a selected row can be seen by, the
// inks on that tint, the fills of switches and sliders, the labels on accent
// buttons, the swatches, and the media cover's strength. Only Settings and
// the panel style are touched: no service with a side effect (pitfall 82).
ShellRoot {
    id: root
    property int waits: 0
    readonly property var swatches: ["#4f8ff7", "#8b6cf6", "#d46ad8", "#ef5f67", "#f28b3c", "#e7b43c", "#4fbf73", "#50e2cb", "#8f97a6"]
    // A level widget as it is drawn on a panel (no service: WidgetBase
    // alone), for the meter's colour.
    property Item meterWidget: WidgetBase { sizeClass: "medium"; meter: 0.5 }

    // A colour property or a "#rrggbb" string (Colors.flat gives strings) as
    // "#rrggbb", without its alpha.
    function hex(color) { return typeof color === "string" ? color : String(Qt.rgba(color.r, color.g, color.b, 1)) }
    function contrast(first, second) { return C.contrast(hex(first), hex(second)) }
    function set(theme, panelColor, accent) {
        SettingsService.set("appearance.theme", theme)
        SettingsService.set("appearance.panelColor", panelColor)
        SettingsService.set("appearance.accent", accent)
    }
    // Every ink that is drawn on the panels holds on the surfaces it is
    // measured on, whatever the theme and panel colour.
    function inksHold(label) {
        T.ok(contrast(Colors.text, Colors.innerBase) >= 7, label + ": text on an inner card " + contrast(Colors.text, Colors.innerBase))
        T.ok(contrast(Colors.mutedText, Colors.cardBase) >= 4.5 && contrast(Colors.mutedText, Colors.innerBase) >= 4.5,
             label + ": muted text on cards " + hex(Colors.mutedText))
        T.ok(contrast(Colors.subtleText, Colors.innerBase) >= 3, label + ": marks on an inner card")
        T.ok(contrast(Colors.accentForeground, Colors.contrastBase) >= 4.5, label + ": accent text on a card")
        T.ok(contrast(Colors.accentOnSoft, Colors.softBase) >= 4.5, label + ": accent text on the tint " + hex(Colors.accentOnSoft))
        T.ok(contrast(Colors.mutedOnSoft, Colors.softBase) >= 4.5, label + ": muted text on the tint " + hex(Colors.mutedOnSoft))
        T.ok(contrast(Colors.accentLine, Colors.contrastBase) >= 3, label + ": the accent line on a card")
        for (const name of ["success", "warning", "danger"])
            T.ok(contrast(Colors[name], Colors.contrastBase) >= 4.5, label + ": " + name + " on a card")
        const dangerTint = Colors.flat(Colors.dangerSoftHover, Colors.cardBase)
        T.ok(contrast(Colors.dangerOnSoft, dangerTint) >= 4.5, label + ": a danger button's label on its wash " + hex(Colors.dangerOnSoft) + " on " + hex(dangerTint) + " soft " + Colors.dangerSoftHover + " card " + hex(Colors.cardBase))
        T.ok(contrast(Colors.accentText, Colors.accent) >= 4.5, label + ": the label on an accent button")
    }

    Timer {
        id: ready
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            if (!SettingsService.loaded && ++root.waits < 250) return
            stop()
            root.run()
        }
    }

    function run() {
        // ---- the panels' side, not the theme's ---------------------------
        set("dark", "auto", "#4f8ff7")
        T.eq([Colors.dark, Colors.surfaceDark], [true, true], "dark theme, theme panel: dark panels")
        T.eq(hex(Colors.mutedText), "#9ba2ae", "the dark muted grey stays as it was")
        T.eq(hex(Colors.contrastBase), "#1a1d25", "and so does the dark measure")
        T.eq(hex(Colors.accentForeground), "#4f8ff7", "the dark theme keeps the blue")
        inksHold("dark")

        // The buchhwin profile after one tap on Dark mode.
        set("light", "#000000", "#50e2cb")
        T.eq([Colors.dark, Colors.surfaceDark], [false, true], "light theme, black panels: the theme is light, the panels dark")
        T.ok(contrast(Colors.text, "#000000") >= 15, "light text on the black panel")
        T.ok(Colors.surface1.r > 0.5 && Colors.border.r > 0.5, "card steps and lines lighten, as on any dark panel")
        T.eq(hex(Colors.panel), "#000000", "the panel is the colour chosen")
        inksHold("light theme, black panel")

        set("dark", "#ffffff", "#4f8ff7")
        T.eq([Colors.dark, Colors.surfaceDark], [true, false], "dark theme, white panels: light panels")
        T.ok(Colors.text.r < 0.2, "dark text on the white panel")
        inksHold("dark theme, white panel")

        // ---- the light panel's floor -------------------------------------
        set("light", "auto", "#50e2cb")
        SettingsService.set("appearance.panelOpacity", 0.74)
        T.near(P.surfaceOpacity(0.74, true), P.LIGHT_MIN_OPACITY, "a light surface is drawn at its floor")
        T.near(P.surfaceOpacity(0.74, false), 0.74, "a dark one as chosen")
        T.near(P.surfaceOpacity(0.95, true), 0.95, "above the floor, as chosen")
        T.near(P.surfaceOpacity(0.1, false), P.MIN_OPACITY, "and never below the minimum")
        T.near(Colors.panel.a, P.LIGHT_MIN_OPACITY, "the light panel at the 0.74 default is drawn at the floor", 0.005)
        T.near(Colors.panelFor("widgets").a, P.LIGHT_MIN_OPACITY, "every group", 0.005)
        T.near(Colors.pillFor("pillBar").a, P.LIGHT_MIN_OPACITY, "and the pills", 0.005)
        T.near(SettingsService.panelOpacity, 0.74, "the setting keeps what was chosen")
        T.eq(hex(Colors.panelBase), C.over("#f8f9fb", P.LIGHT_MIN_OPACITY, "#000000"), "light inks are measured at the floor over black")
        T.eq(hex(Colors.contrastBase), hex(Colors.cardBase), "on a card there")
        T.eq(hex(Colors.mutedText), "#505662", "the light muted grey for that card")
        inksHold("light")
        // The light panel over a dark teal wallpaper (#036b5c). At 0.74 the
        // muted text was 3.5:1 on a card; at the floor it reads.
        const tealCard = C.over("#000000", 0.05, C.over("#f8f9fb", Colors.panel.a, "#036b5c"))
        T.ok(C.contrast(hex(Colors.mutedText), tealCard) >= 4.5, "muted text on a card over a teal wallpaper: " + C.contrast(hex(Colors.mutedText), tealCard))
        T.ok(C.contrast(hex(Colors.accentForeground), tealCard) >= 4.5, "accent text there too")

        // ---- every swatch, both sides ------------------------------------
        for (const theme of ["light", "dark"]) {
            for (const accent of root.swatches) {
                set(theme, "auto", accent)
                const label = theme + " " + accent
                inksHold(label)
                // A selected row stands off the rows beside it by brightness,
                // not only by hue: it was 1.00:1 with the teal in light.
                T.ok(contrast(Colors.softBase, Colors.cardBase) >= 1.25, label + ": the tint is seen " + contrast(Colors.softBase, Colors.cardBase))
                // A switch that is on and a slider's level stand off the card.
                T.ok(contrast(Colors.accentFill, Colors.cardBase) >= (theme === "light" ? 3 : 1.5), label + ": the accent fill on a card")
                T.ok(contrast(Colors.knob, Colors.accentFill) >= (theme === "light" ? 3 : 1), label + ": the knob on the fill")
                // The fastfetch Saturn: two colours that read on the panel
                // and from each other.
                T.ok(contrast(Colors.saturnPlanet, Colors.contrastBase) >= (theme === "light" ? 4.5 : 3), label + ": the Saturn's planet " + hex(Colors.saturnPlanet))
                T.ok(contrast(Colors.saturnRing, Colors.contrastBase) >= 3, label + ": its ring " + hex(Colors.saturnRing))
                // Apart enough to read as two at the menu's small letters:
                // the teal's half-white ring was 1.25:1 from its planet.
                T.ok(contrast(Colors.saturnPlanet, Colors.saturnRing) >= Colors.saturnSeparation,
                     label + ": planet and ring apart " + contrast(Colors.saturnPlanet, Colors.saturnRing))
                // The overview's labels and outlines on its scrim at its
                // lightest, over a white wallpaper: 2.5-3.2:1 in the light
                // theme before.
                T.ok(contrast(Colors.overviewAccent, Colors.overviewBackdrop) >= 4.5,
                     label + ": an accent label on the overview's scrim " + contrast(Colors.overviewAccent, Colors.overviewBackdrop))
                T.ok(contrast(Colors.scrimText, Colors.overviewBackdrop) >= 4.5, label + ": the overview's text on its scrim")
                const mutedOnScrim = C.over("#ffffff", Colors.scrimMutedText.a, hex(Colors.overviewBackdrop))
                T.ok(C.contrast(mutedOnScrim, hex(Colors.overviewBackdrop)) >= 4.5, label + ": and its grey labels " + C.contrast(mutedOnScrim, hex(Colors.overviewBackdrop)))
            }
        }
        set("dark", "auto", "#50e2cb")
        T.eq(hex(Colors.overviewAccent), "#50e2cb", "the shipped teal on the dark overview scrim stays as it is")
        // A level is drawn in the accent made for a fill (round 12,
        // ui-rest#2): the raw teal was 1.08:1 on a light track.
        T.ok(Qt.colorEqual(root.meterWidget.meterColor, Colors.accentFill), "a dark panel's meter: the accent itself")
        set("light", "auto", "#50e2cb")
        T.ok(Qt.colorEqual(root.meterWidget.meterColor, Colors.accentFill) && !Qt.colorEqual(Colors.accentFill, Colors.accent),
             "a light panel's meter: the 3:1 line, not the raw teal")
        T.ok(contrast(root.meterWidget.meterColor, Colors.cardBase) >= 3, "and it stands off the card")
        set("dark", "auto", "#50e2cb")
        T.ok(Colors.saturnRing.r > Colors.saturnRingMix.r, "the teal's ring takes more white than ff's half")
        // `ff`'s second colour: the accent mixed half with white, which is
        // the shipped logo's pale blue for its sky blue.
        set("dark", "auto", "#5fafff")
        T.eq(hex(Colors.saturnRingMix), "#afd7ff", "ff's ring colour for the logo's own blue")
        T.eq([hex(Colors.saturnPlanet), hex(Colors.saturnRing)], ["#5fafff", "#afd7ff"], "on a dark panel the Saturn is fastfetch's")
        set("light", "auto", "#4f8ff7")
        T.eq(hex(Colors.accentFill), hex(Colors.accentLine), "light switches and sliders fill with the 3:1 line")
        T.near(Colors.accentSoft.a, 0.26, "the light tint is the line at 0.26", 0.005)
        T.eq(hex(Colors.accentText), hex(Colors.onAccentDark), "body labels on the blue are dark: white is 3.2:1")
        T.ok(Colors.segmentBorder.a >= 0.15, "the selected segment has an edge on the light trough")
        set("dark", "auto", "#8b6cf6")
        T.eq(hex(Colors.accentFill), "#8b6cf6", "dark fills keep the accent")
        T.eq(hex(Colors.accentText), hex(Colors.onAccentDark), "the purple too (white was 3.8:1)")
        set("dark", "auto", "#50e2cb")
        T.eq(hex(Colors.accentText), hex(Colors.onAccentDark), "the teal keeps its dark label")
        // Words on any other fill take the same 4.5:1; a mark keeps 3:1.
        T.eq([hex(Colors.labelOn("#ef5f67")), hex(Colors.textOn("#ef5f67"))], [hex(Colors.onAccentDark), "#ffffff"],
             "a label on a picked red is dark, the check mark on the red swatch stays white")
        T.eq(hex(Colors.labelOn("#1b1e25")), "#ffffff", "a dark fill keeps white words")

        // ---- swatches ----------------------------------------------------
        T.ok(Colors.accentChoices.indexOf("#50e2cb") >= 0, "the shipped teal is one of the choices")
        T.eq(Colors.accentSwatches, Colors.accentChoices, "an accent among them adds nothing")
        set("dark", "auto", "#123456")
        T.eq(Colors.accentSwatches.length, Colors.accentChoices.length + 1, "another accent is shown after them")
        T.eq(Colors.accentSwatches[Colors.accentSwatches.length - 1], "#123456", "as the colour in use")

        // ---- the media cover ---------------------------------------------
        for (const theme of ["dark", "light"]) {
            set(theme, "auto", "#50e2cb")
            const cover = Colors.surfaceDark ? "#ffffff" : "#000000"
            const strength = Effects.mediaBackdropOpacity
            T.ok(strength > 0 && strength <= Effects.mediaBackdropMax, theme + ": the cover tints, at most as it was: " + strength)
            T.ok(C.contrast(hex(Colors.mutedText), C.over(cover, strength, hex(Colors.panelBase))) >= 4.5,
                 theme + ": a caption on the worst cover keeps 4.5:1")
        }

        set("dark", "auto", "#4f8ff7")
        SettingsService.set("appearance.panelOpacity", 0.74)
        T.finish("ColorsTest")
    }
}
