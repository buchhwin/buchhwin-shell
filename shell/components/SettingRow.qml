import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs.theme

// Label on the left, control on the right, in the two shapes the shell uses:
//   labelFills false - the label keeps a fixed column so the controls of a
//     section line up under each other (segmented controls, selects, sliders).
//   labelFills true  - the control keeps its own width at the right edge and
//     the label takes the rest (toggles, single buttons).
// When the control needs more room than the row has left (a wide interface
// font, a narrow card), the control moves below the label instead of squeezing
// the two together, and the label never runs under the control.
GridLayout {
    id: root
    property string label: ""
    // The explanation, offered by a small "i" after the name. It used to be a
    // line of small print under the label, shown while the *label* was
    // hovered, and that was wrong twice: nothing said which labels had
    // anything to say, so finding out meant sweeping the pointer along the
    // column; and the line was part of the layout, so every row below jumped
    // down as it appeared and back up as it went. The bubble is drawn on the
    // overlay and moves nothing. (`hintOnHover` used to switch the first
    // behaviour off and was never set anywhere, so it is gone.)
    property string hint: ""
    property real labelWidth: 150
    // And the other half of it: the bubble opens under the pointer, which
    // meant fifty-nine explanations no keyboard could ever reach. The answer
    // is not to put the mark in the tab order - that is fifty-nine new stops
    // on the way to anything, and `InfoTip` argues at length why it is not a
    // button. It is to show the explanation when the row's *control* takes
    // the focus: you tab onto the thing you do not understand and it tells
    // you. Nothing is added to the tab order and nothing moves.
    //
    // Walked from `Window.activeFocusItem` rather than read off `slot`,
    // because `activeFocus` on a plain Item is true only for the item that
    // holds it, and the control is a grandchild. A `FocusScope` around the
    // slot would answer it directly and would also insert itself into the tab
    // order and the layout, which is a bigger change than the question.
    readonly property bool controlFocused: {
        let item = Window.activeFocusItem
        while (item) {
            if (item === slot) return true
            item = item.parent
        }
        return false
    }
    // `arm`, not `show`: it waits as long as the pointer does, or tabbing
    // through a page would flash a bubble on every row on the way past.
    onControlFocusedChanged: if (hint.length) controlFocused ? mark.arm() : mark.hide()
    property bool labelFills: false
    readonly property bool stacked: width > 0
        && slot.implicitWidth + root.labelWidth + Metrics.spaceMd > width
    default property alias control: slot.data

    columns: stacked ? 1 : 2
    columnSpacing: Metrics.spaceMd
    rowSpacing: Metrics.spaceXs

    ShellText {
        id: name
        readonly property real lineHeight: lineCount > 0 ? contentHeight / lineCount : implicitHeight
        Layout.fillWidth: root.stacked || root.labelFills
        Layout.preferredWidth: root.stacked ? root.width : root.labelWidth
        text: root.label
        wrapMode: Text.Wrap

        // The mark belongs to the name, so it is placed *inside* it, after the
        // words rather than at the end of the column: a Text that fills its
        // column is as wide as the column whatever its words do, so a sibling
        // placed after it lands beside the control instead of beside the name.
        //
        // Positioned rather than laid out, and deliberately. Making it a
        // sibling in a RowLayout and capping the name's `Layout.maximumWidth`
        // against the row's width does put it in the right place and is a
        // recursive rearrange: the cap depends on the width the row computes
        // from the children the cap constrains. Qt says so and gives up after
        // two iterations. Reading `contentWidth` and `width` to place
        // something feeds nothing back into the layout, so there is no cycle.
        InfoTip {
            id: mark
            text: root.hint
            // After the last of the words, and never past the column - a mark
            // that has run out of room sits at the edge rather than under the
            // control next to it.
            x: Math.max(0, Math.min(name.contentWidth + Metrics.spaceXs, name.width - implicitWidth))
            // Centred on the *first* line of a name that wraps, measured from
            // the name itself rather than from a font metric, so it follows
            // the interface font scale without a second copy of the
            // arithmetic. A mark that drifts down the column is a mark you
            // stop looking for.
            y: Math.max(0, Math.round((name.lineHeight - implicitHeight) / 2))
        }
    }
    RowLayout {
        id: slot
        Layout.fillWidth: !root.labelFills
        Layout.alignment: root.labelFills ? Qt.AlignRight | Qt.AlignVCenter : Qt.AlignVCenter
        spacing: Metrics.spaceSm
    }
}
