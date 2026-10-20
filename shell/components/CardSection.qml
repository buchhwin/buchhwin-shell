import QtQuick
import QtQuick.Layouts
import qs.theme

// A card with an optional title, an optional description and padded content.
// The one way to put a group of controls on a card: settings sections, control
// center pages, dashboard blocks and popups all use it, so a card looks the
// same wherever it appears. A Rectangle does not clip its children to its
// radius, so the content is inset rather than filling the card.
ShellCard {
    id: root
    property string title: ""
    property string description: ""
    // The section's explanation, behind a small "i" after the title (InfoTip):
    // it shows when the pointer rests on the mark, so a page of sections reads
    // as titles and controls instead of a column of small print under each
    // title. `description` stays for what is a state rather than an
    // explanation - a battery's time left - and is shown as before.
    property string hint: ""
    // Said after the hint in the same bubble, by whoever wraps the card -
    // Settings' sections put where their settings are kept there.
    property string hintNote: ""
    readonly property string hintText: [hint, hintNote].filter(text => text.length > 0).join("\n\n")
    property real padding: Metrics.spaceLg
    property real spacing: Metrics.spaceMd
    // Where the title sits from the card's edges: one inset for every titled
    // card, whatever its content padding. A card of rows pads by spaceSm or
    // less because ListRow brings its own inset, and its title sat at 8/8
    // beside the 16/16 of every other card (the privacy popup). A card padded
    // for plain content keeps the title on that content's edge.
    property real titleInset: padding < Metrics.spaceMd ? Metrics.spaceLg : padding
    default property alias content: body.data
    implicitHeight: column.implicitHeight + root.padding * 2

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: root.spacing

        ColumnLayout {
            spacing: Metrics.spaceXxs
            visible: root.title.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Math.max(0, root.titleInset - root.padding)
            Layout.rightMargin: Math.max(0, root.titleInset - root.padding)
            Layout.topMargin: Math.max(0, root.titleInset - root.padding)
            ShellText {
                id: titleText
                readonly property real lineHeight: lineCount > 0 ? contentHeight / lineCount : implicitHeight
                text: root.title
                role: "title"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                // After the title's last word, as SettingRow places its mark
                // after a label, and centred on the first line.
                InfoTip {
                    text: root.hintText
                    x: Math.max(0, Math.min(titleText.contentWidth + Metrics.spaceXs, titleText.width - implicitWidth))
                    y: Math.max(0, Math.round((titleText.lineHeight - implicitHeight) / 2))
                }
            }
            ShellText { text: root.description; muted: true; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: root.spacing
        }
    }
}
