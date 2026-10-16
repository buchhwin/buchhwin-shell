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
    // Only evaluated while the picker is visible, like the launcher's. The
    // panel is built at start, and `search` asks for the list: evaluated
    // then, it read and parsed config/emoji.json (172 KB, a few MB of
    // objects) in every session, picker opened or not.
    readonly property var results: shown ? EmojiService.search(query, query.length ? "" : group) : []
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

    // The group tabs: every group, Recent once something was picked.
    readonly property var groupTabs: EmojiService.groups
        .filter(entry => entry.key !== "recent" || EmojiService.recent.length > 0)
        .map(entry => ({ key: entry.key, label: entry.label, glyph: tabGlyph(entry) }))
    // The white flag (U+1F3F3) is white on the light trough and all but
    // disappeared there; the chequered one reads in both themes.
    function tabGlyph(entry) { return entry.key === "flags" ? "\u{1F3C1}" : entry.icon }
    function chooseGroup(key) {
        if (key === group) return
        group = key
        selected = 0
        grid.positionViewAtBeginning()
    }
    function stepGroup(delta) {
        const keys = groupTabs.map(tab => tab.key)
        if (!keys.length) return
        const at = keys.indexOf(group)
        chooseGroup(keys[Math.max(0, Math.min(keys.length - 1, (at < 0 ? 0 : at) + delta))])
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
        spacing: Metrics.panelGap

        // No icon: no other panel's title has one.
        PanelHeader {
            Layout.fillWidth: true
            title: "Emoji"
            subtitle: EmojiService.loaded ? "" : "Loading …"
        }

        ShellTextField {
            id: search
            Layout.fillWidth: true
            focusOnTab: true
            large: true
            icon: Icons.search
            placeholder: "Search emoji …"
            onTextChanged: { root.query = text; root.selected = 0 }
            onAccepted: root.pick(root.selected)
            onEscapePressed: root.requestClose()
            // The arrows walk the grid; Ctrl with Left or Right the groups,
            // while no search hides them.
            onKeyPressed: event => {
                const groups = (event.modifiers & Qt.ControlModifier) && root.query.length === 0
                if (event.key === Qt.Key_Down) { root.move(root.columns); event.accepted = true }
                else if (event.key === Qt.Key_Up) { root.move(-root.columns); event.accepted = true }
                else if (event.key === Qt.Key_Right) { groups ? root.stepGroup(1) : root.move(1); event.accepted = true }
                else if (event.key === Qt.Key_Left) { groups ? root.stepGroup(-1) : root.move(-1); event.accepted = true }
            }
        }

        // The group tabs: the shell's segmented trough, each group's emoji
        // at an icon's size in a slot of its own, and its name as the
        // tooltip and the accessible name. A SegmentedControl drew the emoji
        // as 13 px labels, beside 28 px ones in the grid. One tab stop
        // (Tab from the search field), Left and Right walk the groups.
        Rectangle {
            id: groupBar
            Layout.fillWidth: true
            visible: root.query.length === 0
            implicitHeight: Metrics.controlHeightLg
            radius: Metrics.pillRadius(height)
            color: Colors.sunken
            border.width: Metrics.borderWidth
            border.color: Colors.border
            activeFocusOnTab: visible
            Keys.onLeftPressed: root.stepGroup(-1)
            Keys.onRightPressed: root.stepGroup(1)
            Accessible.role: Accessible.PageTabList
            Accessible.name: "Emoji groups"
            FocusRing { active: groupBar.activeFocus; controlRadius: groupBar.radius }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Metrics.spaceXs
                spacing: Metrics.spaceXs
                Repeater {
                    model: root.groupTabs
                    Rectangle {
                        id: tab
                        required property var modelData
                        readonly property bool active: modelData.key === root.group
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Metrics.pillRadius(height)
                        color: active ? Colors.segmentSelected : tabMouse.containsMouse ? Colors.hover : "transparent"
                        border.width: active ? Metrics.borderWidth : 0
                        border.color: Colors.segmentBorder
                        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.label
                        Accessible.checkable: true
                        Accessible.checked: active
                        Accessible.onPressAction: root.chooseGroup(modelData.key)

                        Text {
                            anchors.centerIn: parent
                            text: tab.modelData.glyph
                            color: Colors.text
                            textFormat: Text.PlainText
                            font.family: Typography.family
                            font.pixelSize: Typography.emojiTabSize
                            renderType: Typography.renderType
                        }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: tabTip.arm()
                            onExited: tabTip.release()
                            onClicked: {
                                tabTip.release()
                                root.chooseGroup(tab.modelData.key)
                            }
                        }
                        ToolTipHost { id: tabTip; anchorItem: tab; text: tab.modelData.label }
                    }
                }
            }
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
                ScrollFeel { view: grid }

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Metrics.spaceXxs
                        radius: Metrics.radiusInner
                        color: index === root.selected ? Colors.accentSoft
                            : cell.containsMouse ? Colors.surface1Hover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: EmojiService.text(modelData)
                            color: Colors.text
                            textFormat: Text.PlainText
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
                focusOnTab: true
                accessibleName: "Skin tone"
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
