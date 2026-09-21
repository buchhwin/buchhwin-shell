import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/emoji/EmojiLogic.js" as Logic

// Super+. emoji picker: search, groups, and a grid. Enter or a click copies
// the emoji and closes the panel, the way the calculator and the clipboard
// history hand things over - the shell never types into another window.
ShellPanel {
    id: root
    panelId: "emoji"
    placement: "center"
    cardWidth: Metrics.emojiWidth
    cardHeight: Metrics.emojiHeight
    keyForward: search

    property string query: ""
    property string group: "recent"
    property int selected: 0
    readonly property var results: EmojiService.search(query, query.length ? "" : group)
    readonly property int columns: Math.max(1, Math.floor((cardTargetWidth - Metrics.panelPadding * 2)
        / Metrics.emojiCell))

    onWantedChanged: {
        if (!wanted) return
        EmojiService.load()
        query = ""
        group = EmojiService.recent.length > 0 ? "recent" : "smileys"
        selected = 0
        search.text = ""
    }

    function move(step) {
        if (!results.length) return
        selected = Math.max(0, Math.min(results.length - 1, selected + step))
        grid.positionViewAtIndex(selected, GridView.Contain)
    }

    function pick(index) {
        const entry = results[index]
        if (!entry) return
        EmojiService.pick(entry)
        PanelService.close("emoji")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.spaceMd

        PanelHeader {
            Layout.fillWidth: true
            icon: "󰞅"
            title: "Emoji"
            subtitle: EmojiService.loaded ? "" : "Loading …"
        }

        ShellTextField {
            id: search
            Layout.fillWidth: true
            focusOnTab: true
            large: true
            icon: Icons.search
            placeholder: "Search emoji"
            onTextChanged: { root.query = text; root.selected = 0 }
            onAccepted: root.pick(root.selected)
            onEscapePressed: root.requestClose()
            onKeyPressed: event => {
                if (event.key === Qt.Key_Down) { root.move(root.columns); event.accepted = true }
                else if (event.key === Qt.Key_Up) { root.move(-root.columns); event.accepted = true }
                else if (event.key === Qt.Key_Right) { root.move(1); event.accepted = true }
                else if (event.key === Qt.Key_Left) { root.move(-1); event.accepted = true }
            }
        }

        SegmentedControl {
            Layout.fillWidth: true
            visible: root.query.length === 0
            compact: true
            options: EmojiService.groups
                .filter(entry => entry.key !== "recent" || EmojiService.recent.length > 0)
                .map(entry => ({ value: entry.key, label: entry.icon }))
            current: root.group
            onSelected: value => { root.group = value; root.selected = 0; grid.positionViewAtBeginning() }
        }

        // A ShellCard rather than a CardSection: the card's column is anchored
        // to the top, so nothing inside it can fill the free height.
        ShellCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                width: parent.width - Metrics.spaceLg * 2
                visible: root.results.length === 0
                icon: "󰞅"
                title: EmojiService.loaded ? "No emoji found" : "Loading the emoji list …"
            }

            GridView {
                id: grid
                anchors.fill: parent
                anchors.margins: Metrics.spaceXs
                visible: root.results.length > 0
                clip: true
                model: root.results
                cellWidth: Math.floor(width / root.columns)
                cellHeight: Metrics.emojiCell
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Metrics.spaceXxs
                        radius: Metrics.radiusInner
                        color: index === root.selected ? Colors.selection
                            : cell.containsMouse ? Colors.hover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: EmojiService.text(modelData)
                            color: Colors.text
                            font.family: Typography.family
                            font.pixelSize: Typography.emojiSize
                            renderType: Typography.renderType
                        }
                    }

                    MouseArea {
                        id: cell
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selected = index
                        onClicked: root.pick(index)
                    }
                }
            }
        }

        // The footer names what is selected and carries the skin tone: the
        // group chips need the whole width, and the header has the title.
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            ShellText {
                Layout.fillWidth: true
                text: root.results.length && root.results[root.selected]
                    ? root.results[root.selected].n + " · Enter copies"
                    : "Enter copies · Esc closes"
                role: "small"
                muted: true
                elide: Text.ElideRight
            }

            // The skin tone the picker applies wherever Unicode allows one.
            ShellSelect {
                Layout.preferredWidth: Metrics.toneSelectWidth
                Layout.maximumWidth: Metrics.toneSelectWidth
                options: EmojiService.toneLabels.map((label, index) => ({ value: String(index), label: label }))
                current: String(EmojiService.tone)
                listHeight: Metrics.popupListHeight
                onSelected: value => EmojiService.setTone(Number(value))
            }
        }
    }
}
