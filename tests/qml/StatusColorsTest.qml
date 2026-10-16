import Quickshell
import QtQuick
import qs.services
import qs.theme
import qs.shell.widgets
import qs.shell.components
import "Harness.js" as T
import "../../services/appearance/ContrastLogic.js" as C
import "../../services/profile/ProfileLogic.js" as P

// Settings > Power > Status colors (appearance.statusColors): a good state -
// a battery charging, a tunnel up - in the green or in the accent. The
// setting itself (default, the values it takes, a profile's like the accent),
// what Colors decides from it in both themes and on dark, light, black and
// white panels for every swatch and two accents of the user's own, that both
// choices read where they are drawn (4.5:1 as words on a card, 3:1 as glyphs
// on any panel step and on the black notch), that danger and warning do not
// move, and what a widget wears from it: on the notch with the glyphs in the
// accent a charging battery is that very accent, a low one stays red, and
// the bar on the charger is the bar off it; a finished fingerprint
// enrollment (Settings > Lock screen) is a good state too. Only Settings and
// the panel style are touched, and the widgets are plain WidgetBase: no
// service with a side effect (pitfall 82).
ShellRoot {
    id: root
    property int waits: 0
    // The offered swatches, a dark accent of the user's own (lifted on the
    // notch, lightened on dark panels) and a light one (darkened on light).
    readonly property var accents: ["#4f8ff7", "#8b6cf6", "#d46ad8", "#ef5f67", "#f28b3c", "#e7b43c", "#4fbf73", "#50e2cb", "#8f97a6",
                                    "#1a2a6a", "#d8f0ff"]
    readonly property string black: "#000000"

    Item {
        // On a panel (the bar, the desktop).
        WidgetBase { id: panelWidget; icon: "x" }
        // On the notch, with its status glyphs in the accent
        // (notch.accentGlyphs "all"): NotchStrip hands both.
        WidgetBase { id: notchWidget; icon: "x"; onDark: true; glyphInk: Colors.notchAccent }
        // A battery coloured the way BatteryWidget colours it, without
        // PowerService: charging, low or the surface's ink; the level in the
        // state's fill or the accent's.
        WidgetBase {
            id: notchBattery
            property bool charging: false
            property bool low: false
            icon: "x"
            onDark: true
            glyphInk: Colors.notchAccent
            meter: 0.5
            iconColor: charging ? successInk : low ? dangerInk : glyphInk
            meterColor: charging ? successFill : low ? dangerInk : levelFill
        }
        WidgetBase {
            id: panelBattery
            property bool charging: false
            property bool low: false
            icon: "x"
            meter: 0.5
            iconColor: charging ? successInk : low ? dangerInk : glyphInk
            meterColor: charging ? successFill : low ? dangerInk : levelFill
        }
        // The enrollment's check mark, with the colours it brings itself.
        FingerprintGlyph { id: fingerprint; mode: "done" }
    }

    // A colour property or a "#rrggbb" string as "#rrggbb", without alpha.
    function hex(color) { return typeof color === "string" ? color : String(Qt.rgba(color.r, color.g, color.b, 1)) }
    function contrast(first, second) { return C.contrast(hex(first), hex(second)) }
    // Only what differs is written: every write rebuilds the settings.
    function put(path, value) { if (SettingsService.value(path) !== value) SettingsService.set(path, value) }
    function look(theme, panelColor, accent, mode) {
        put("appearance.theme", theme)
        put("appearance.panelColor", panelColor)
        put("appearance.accent", accent)
        put("appearance.statusColors", mode)
    }
    function bad() {
        return [Colors.danger, Colors.dangerOnDark, Colors.warning, Colors.warningOnDark].map(hex)
    }
    // Where a good state is drawn, it reads: as a word on a card, as a glyph
    // on every step of the panel, and on the black notch.
    function reads(label) {
        T.ok(contrast(Colors.positive, Colors.contrastBase) >= 4.5, label + ": a word on a card " + hex(Colors.positive))
        for (const base of [Colors.panelBase, Colors.cardBase, Colors.innerBase])
            T.ok(contrast(Colors.positive, base) >= 3, label + ": a glyph on " + hex(base) + " " + contrast(Colors.positive, base))
        T.ok(contrast(Colors.positiveOnDark, root.black) >= 3, label + ": a glyph on the notch " + hex(Colors.positiveOnDark))
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
        // ---- the setting -------------------------------------------------
        T.eq(SettingsService.defaultOf("appearance.statusColors"), "status", "the default is the green it always was")
        T.eq(SettingsService.value("appearance.statusColors"), "status", "and a fresh file reads it")
        T.eq(Colors.statusInAccent, false, "so the good states are not in the accent")
        T.eq(SettingsService.set("appearance.statusColors", "green"), false, "a value outside the two is refused")
        T.eq(SettingsService.set("appearance.statusColors", 1), false, "and a value of another type")
        T.eq(SettingsService.value("appearance.statusColors"), "status", "the refusals change nothing")
        T.eq(SettingsService.set("appearance.statusColors", "accent"), true, "the accent is taken")
        T.eq(Colors.statusInAccent, true, "and Colors follows it")
        T.eq(SettingsService.set("appearance.statusColors", "status"), true, "and back")
        // A look, kept per profile like the accent: not a mode's, not the
        // machine's.
        T.eq([P.isProfileSetting("appearance.statusColors"), P.isModeScoped("appearance.statusColors"),
              P.isGlobalSetting("appearance.statusColors")], [true, false, false], "a profile keeps it")
        T.eq([P.isProfileSetting("appearance.accent"), P.isModeScoped("appearance.accent"),
              P.isGlobalSetting("appearance.accent")], [true, false, false], "as it keeps the accent")

        // ---- what Colors decides, everywhere -----------------------------
        for (const theme of ["dark", "light"]) {
            for (const panel of ["auto", "#000000", "#ffffff"]) {
                for (const accent of root.accents) {
                    const label = theme + " " + panel + " " + accent
                    const offered = Colors.accentChoices.indexOf(accent) >= 0

                    look(theme, panel, accent, "status")
                    T.eq([hex(Colors.positive), hex(Colors.positiveOnDark), hex(Colors.positiveFill)],
                         [hex(Colors.success), hex(Colors.successOnDark), hex(Colors.success)], label + ": green")
                    reads(label + " green")
                    const badBefore = bad()

                    look(theme, panel, accent, "accent")
                    T.eq([hex(Colors.positive), hex(Colors.positiveOnDark), hex(Colors.positiveFill)],
                         [hex(Colors.accentForeground), hex(Colors.notchAccent), hex(Colors.accentFill)], label + ": the accent")
                    reads(label + " accent")
                    T.eq(bad(), badBefore, label + ": danger and warning stay where they were")
                    // The level fill stands off the card as an accent level
                    // does (ColorsTest holds the offered swatches to it).
                    if (offered)
                        T.ok(contrast(Colors.positiveFill, Colors.cardBase) >= (Colors.surfaceDark ? 1.5 : 3),
                             label + ": the charging level on a card")
                }
            }
        }

        // ---- what a widget wears ------------------------------------------
        for (const theme of ["dark", "light"]) {
            for (const mode of ["status", "accent"]) {
                look(theme, "auto", "#50e2cb", mode)
                const label = theme + " " + mode
                T.ok(Qt.colorEqual(panelWidget.successInk, Colors.positive), label + ": a panel widget's good state")
                T.ok(Qt.colorEqual(panelWidget.successFill, Colors.positiveFill), label + ": and its level")
                T.ok(Qt.colorEqual(panelWidget.levelFill, Colors.accentFill), label + ": the plain level, the accent as a fill")
                T.ok(Qt.colorEqual(panelWidget.dangerInk, Colors.danger), label + ": danger as before")
                T.ok(Qt.colorEqual(notchWidget.successInk, Colors.positiveOnDark), label + ": on the notch, the on-dark good state")
                T.ok(Qt.colorEqual(notchWidget.successFill, Colors.positiveOnDark), label + ": and its level")
                T.ok(Qt.colorEqual(notchWidget.levelFill, Colors.notchAccent), label + ": the plain level, the notch's accent")
                T.ok(Qt.colorEqual(notchWidget.dangerInk, Colors.dangerOnDark) && Qt.colorEqual(notchWidget.warningInk, Colors.warningOnDark),
                     label + ": the on-dark red and amber as before")
                T.ok(Qt.colorEqual(fingerprint.activeColor, Colors.positive), label + ": a finished enrollment's check mark")
                T.ok(Qt.colorEqual(fingerprint.errorColor, Colors.danger), label + ": a failed one stays red")

                notchBattery.charging = true
                panelBattery.charging = true
                const inAccent = mode === "accent"
                // With the notch's glyphs in the accent, a charging battery is
                // that accent in accent mode and the green otherwise.
                T.eq(Qt.colorEqual(notchBattery.iconColor, notchBattery.glyphInk), inAccent,
                     label + ": a charging glyph " + (inAccent ? "is" : "is not") + " the accent glyph ink")
                T.ok(Qt.colorEqual(notchBattery.iconColor, inAccent ? Colors.notchAccent : Colors.successOnDark),
                     label + ": charging on the notch")
                T.ok(Qt.colorEqual(panelBattery.iconColor, inAccent ? Colors.accentForeground : Colors.success),
                     label + ": charging on a panel")
                // The bar on the charger is the bar off it, in accent mode.
                const notchCharging = hex(notchBattery.meterColor)
                const panelCharging = hex(panelBattery.meterColor)
                notchBattery.charging = false
                panelBattery.charging = false
                T.eq(notchCharging === hex(notchBattery.meterColor), inAccent, label + ": the notch's level on and off the charger")
                T.eq(panelCharging === hex(panelBattery.meterColor), inAccent, label + ": a panel's level on and off the charger")

                // Low is red in both, over the accent glyph ink.
                notchBattery.low = true
                panelBattery.low = true
                T.ok(Qt.colorEqual(notchBattery.iconColor, Colors.dangerOnDark), label + ": a low battery on the notch stays red")
                T.ok(Qt.colorEqual(panelBattery.iconColor, Colors.danger), label + ": and on a panel")
                T.ok(Qt.colorEqual(notchBattery.meterColor, Colors.dangerOnDark), label + ": its level too")
                notchBattery.low = false
                panelBattery.low = false
            }
        }

        look("dark", "auto", "#4f8ff7", "status")
        T.finish("StatusColorsTest")
    }
}
