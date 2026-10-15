import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.widgets
import "Harness.js" as T
import "../../services/appearance/ContrastLogic.js" as C

// What a widget is handed on the notch: the glyph's neutral ink, which a
// state colour still overrides; the notch's own accent and dim ink, readable
// on black; and the room of a cell, which a label ends in "…" inside rather
// than running past. No window here, so the layout is never polished: the
// bounds are read where the label takes them, not off the laid-out widths.
ShellRoot {
    id: root
    readonly property string longText: "A window title far too long for any cell of the notch's overview"

    Item {
        WidgetBase { id: plain; icon: "x"; label: "42%" }
        WidgetBase {
            id: stated
            icon: "x"
            property bool warning: false
            iconColor: warning ? "#ff0000" : glyphInk
        }
        WidgetBase { id: bounded; icon: "x"; label: root.longText; availableWidth: 150 }
        WidgetBase { id: wide; icon: "x"; label: root.longText }
        WidgetBase {
            id: large
            sizeClass: "large"
            icon: "x"
            label: root.longText
            detail: root.longText
            availableWidth: 300
        }
        WidgetBase { id: roomy; sizeClass: "large"; icon: "x"; label: "42%"; detail: "2 h left"; availableWidth: 400 }
        WidgetBase { id: stacked; vertical: true; icon: "x"; label: "42%"; availableWidth: 30 }
    }

    // The label Text of a widget: the one showing its label.
    function labelOf(widget) { return widget.children.find(child => child.text === widget.label) }
    function detailOf(widget) { return widget.children.find(child => child.text === widget.detail && child !== labelOf(widget)) }

    Component.onCompleted: {
        // ---- the glyph's ink -------------------------------------------
        T.ok(Qt.colorEqual(plain.glyphInk, plain.textColor), "the ink is the text's colour by default")
        T.ok(Qt.colorEqual(plain.iconColor, plain.glyphInk), "and the glyph wears it")
        plain.textColor = Colors.notchText
        T.ok(Qt.colorEqual(plain.iconColor, Colors.notchText), "a surface's text colour reaches the glyph")
        plain.glyphInk = Qt.binding(() => Colors.notchAccent)
        T.ok(Qt.colorEqual(plain.iconColor, Colors.notchAccent), "the ink a surface hands over is the glyph's")
        T.ok(Qt.colorEqual(plain.textColor, Colors.notchText), "and leaves the text as it was")

        stated.glyphInk = Colors.notchAccent
        T.ok(Qt.colorEqual(stated.iconColor, Colors.notchAccent), "a widget without a state shows the ink")
        stated.warning = true
        T.ok(Qt.colorEqual(stated.iconColor, "#ff0000"), "a state colour wins over the ink")

        T.ok(Qt.colorEqual(plain.trackColor, Colors.track), "the meter's groove is the theme's by default")

        // ---- the notch's own inks --------------------------------------
        const black = String(Colors.notch)
        T.ok(C.contrast(String(Colors.notchAccent), black) >= 3, "the notch accent keeps 3:1 on black")
        T.eq(String(Colors.notchAccent), C.readable(String(Colors.accent), black, 3), "it is the accent made readable there")
        T.eq(C.readable("#4f8ff7", black, 3), "#4f8ff7", "the calm blue stays as it is")
        T.ok(C.contrast(C.readable("#1a2a6a", black, 3), black) >= 3, "a dark accent is lifted to 3:1")
        // The dim ink is a translucent white; over black that is its grey.
        const subtle = Colors.notchSubtleText
        const grey = C.toHex({ r: subtle.r * subtle.a, g: subtle.g * subtle.a, b: subtle.b * subtle.a })
        T.ok(C.contrast(grey, black) >= 3, "an icon that is off still reads at 3:1 (" + grey + ")")
        const muted = Colors.notchMutedText
        const before = C.toHex({ r: muted.a * 0.4, g: muted.a * 0.4, b: muted.a * 0.4 })
        T.ok(C.contrast(before, black) < 2, "where the dimmed muted ink did not (" + before + ")")

        // ---- the room of a cell ----------------------------------------
        const wideLabel = labelOf(wide)
        T.eq(wide.labelRoom, Infinity, "no room granted: nothing but the cap")
        T.eq(wideLabel.Layout.maximumWidth, 220, "the 220-px cap as before")

        const boundedLabel = labelOf(bounded)
        T.ok(boundedLabel !== undefined && boundedLabel.elide === Text.ElideRight, "the label elides")
        T.ok(boundedLabel.Layout.maximumWidth < 150, "a granted room bounds the label below the cap")
        T.near(boundedLabel.Layout.maximumWidth + bounded.fixedWidth, 150,
               "the glyph and the label fill the room, no more", 0.5)
        bounded.availableWidth = -1
        T.eq(boundedLabel.Layout.maximumWidth, 220, "and letting go of it brings the cap back")

        // Label and detail both too long: the detail keeps a third.
        const largeLabel = labelOf(large)
        const largeDetail = detailOf(large)
        T.ok(largeDetail !== undefined && largeDetail.elide === Text.ElideRight, "the detail elides too")
        T.near(largeDetail.Layout.maximumWidth, large.spareWidth / 3, "a long detail keeps a third of the room", 0.5)
        T.near(largeLabel.Layout.maximumWidth + largeDetail.Layout.maximumWidth, large.spareWidth,
               "and the label the rest", 0.5)
        T.ok(large.fixedWidth + large.spareWidth + large.columnSpacing <= 300.5, "together inside the room")

        // Both short: neither is touched.
        T.ok(labelOf(roomy).Layout.maximumWidth >= labelOf(roomy).implicitWidth, "a short label keeps its length")
        T.ok(detailOf(roomy).Layout.maximumWidth >= detailOf(roomy).implicitWidth, "and so does a short detail")

        T.eq(stacked.labelRoom, 30, "stacked, each line has the whole width")

        T.finish("NotchInkTest")
    }
}
