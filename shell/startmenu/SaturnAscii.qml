import QtQuick
import qs.theme

// The fastfetch logo as fastfetch draws it, in letters: each run of
// characters (StartMenuLogic.asciiRuns) its own plain Text at its column, so
// no space has to be laid out and nothing in the file can be read as markup
// (the user may change the logo in ~/.config). The cell is the mono font's
// own: its advance and its line height - the logo was drawn for a terminal's
// cell, about 2.2 times as high as wide, which is what a mono font's line is.
Item {
    id: root
    // { rows, columns, runs: [{ row, col, text, tone }] }
    property var logo: ({ rows: 0, columns: 0, runs: [] })
    // fastfetch's `$1` (the planet) and every other colour (the ring).
    property color firstColor: Colors.saturnPlanet
    property color otherColor: Colors.saturnRing
    // The room it has, in cells (0: any): a larger logo of the user's own is
    // drawn smaller to fit, never one smaller than the room larger.
    property int boxColumns: 0
    property int boxRows: 0

    FontMetrics {
        id: metrics
        font.family: Typography.monoFamily
        font.pixelSize: Typography.startAsciiSize
        font.weight: Typography.bold
    }
    readonly property real cell: metrics.advanceWidth("M")
    readonly property real pitch: metrics.height
    readonly property real naturalWidth: logo.columns * cell
    readonly property real naturalHeight: logo.rows * pitch
    readonly property real fit: Math.min(1,
        boxColumns > 0 && logo.columns > boxColumns ? boxColumns / logo.columns : 1,
        boxRows > 0 && logo.rows > boxRows ? boxRows / logo.rows : 1)

    implicitWidth: Math.ceil(naturalWidth * fit)
    implicitHeight: Math.ceil(naturalHeight * fit)

    Item {
        width: root.naturalWidth
        height: root.naturalHeight
        scale: root.fit
        transformOrigin: Item.TopLeft

        Repeater {
            model: root.logo.runs
            Text {
                required property var modelData
                x: modelData.col * root.cell
                y: modelData.row * root.pitch
                text: modelData.text
                color: modelData.tone === 1 ? root.firstColor : root.otherColor
                font: metrics.font
                textFormat: Text.PlainText
                renderType: Typography.renderType
            }
        }
    }
}
