import QtQuick
import QtQuick.Layouts
import qs.theme

// One UI select: a filled capsule showing the current value that expands into
// a filterable list.
ColumnLayout {
    id: root
    property var options: []             // [{ value, label }]
    property string current: ""
    property bool filterable: options.length > 12
    property bool expanded: false
    property string filter: ""
    property real listHeight: 220
    property bool previewFonts: false
    property string placeholder: ""
    property bool focusOnTab: false
    property string accessibleName: ""
    signal selected(string value)
    spacing: Metrics.spaceXs

    // The keys and the ring live on the header, not on this column, and a
    // panel that walks its controls (NavLogic) focuses the column it finds:
    // the focus landed where nothing drew it and nothing read a key. A panel
    // calls focusInput() when a control has one (ShellPanel.navigateKey).
    function focusInput(reason) {
        header.forceActiveFocus(reason === undefined ? Qt.OtherFocusReason : reason)
    }
    // The closed control's height: the line a row's label centres on, while
    // the open list below it grows the select (SettingRow).
    readonly property real firstLineHeight: header.height

    readonly property int currentIndex: options.findIndex(option => option.value === root.current)
    function step(delta) {
        if (!options.length) return
        const next = Math.max(0, Math.min(options.length - 1, (currentIndex < 0 ? 0 : currentIndex) + delta))
        if (options[next].value !== root.current) root.selected(options[next].value)
    }

    // Which row the keyboard is standing on while the list is open. -1 means
    // "wherever the value is", so opening the list starts there. Without this
    // the arrows were swallowed by an open list: the handler ran, did nothing
    // and accepted the key, so the list could be opened and then not walked.
    property int walked: -1
    readonly property int walkIndex: {
        if (!expanded || !visibleOptions.length) return -1
        const here = visibleOptions.findIndex(option => option.value === root.current)
        const start = here >= 0 ? here : 0
        return Math.max(0, Math.min(visibleOptions.length - 1, walked < 0 ? start : walked))
    }
    function walk(delta) {
        if (!visibleOptions.length) return
        walked = Math.max(0, Math.min(visibleOptions.length - 1, walkIndex + delta))
    }
    function takeWalked() {
        const option = visibleOptions[walkIndex]
        if (option && option.value !== root.current) root.selected(option.value)
        root.expanded = false
    }
    onExpandedChanged: walked = -1
    onFilterChanged: walked = -1

    readonly property var currentOption: options.find(option => option.value === current) || null
    readonly property var visibleOptions: filter.length
        ? options.filter(option => option.label.toLowerCase().includes(filter.toLowerCase())) : options

    Rectangle {
        id: header
        // The whole select is one tab stop; the arrows walk its values and
        // Space opens the list, like every other closed dropdown.
        activeFocusOnTab: root.focusOnTab
        // Open, the arrows walk the list and Enter takes the row they are on;
        // closed, they walk the value itself, like every other dropdown.
        Keys.onUpPressed: root.expanded ? root.walk(-1) : root.step(-1)
        Keys.onDownPressed: root.expanded ? root.walk(1) : root.step(1)
        Keys.onReturnPressed: event => { if (root.expanded) root.takeWalked(); else event.accepted = false }
        Keys.onEnterPressed: event => { if (root.expanded) root.takeWalked(); else event.accepted = false }
        Keys.onSpacePressed: { root.expanded = !root.expanded; root.filter = "" }
        Keys.onEscapePressed: event => { if (root.expanded) root.expanded = false; else event.accepted = false }
        FocusRing { active: header.activeFocus; controlRadius: header.radius }
        Accessible.role: Accessible.ComboBox
        Accessible.name: root.accessibleName
        Accessible.description: root.currentOption ? root.currentOption.label : root.current
        Layout.fillWidth: true
        implicitHeight: Metrics.controlHeight
        radius: Metrics.pillRadius(height)
        color: headerMouse.pressed && headerMouse.containsMouse ? Colors.controlFillPressed
            : headerMouse.containsMouse || root.expanded ? Colors.controlFillHover : Colors.controlFill
        border.width: Metrics.borderWidth
        border.color: root.expanded ? Colors.accentBorder : "transparent"
        scale: headerMouse.pressed && headerMouse.containsMouse ? Effects.pressScale : 1
        Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
        Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.spaceLg
            anchors.rightMargin: Metrics.spaceLg
            ShellText {
                Layout.fillWidth: true
                text: root.currentOption ? root.currentOption.label : root.current.length ? root.current : root.placeholder
                color: root.currentOption || root.current.length ? Colors.text : Colors.mutedText
                font.family: root.previewFonts && root.current.length ? root.current : Typography.family
            }
            ShellIcon {
                glyph: Icons.collapse
                size: Metrics.iconSm
                color: Colors.mutedText
                rotation: root.expanded ? -180 : 0
                Behavior on rotation { NumberAnimation { duration: Animations.move(Animations.control); easing.type: Animations.easing } }
            }
        }
        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.expanded = !root.expanded; root.filter = "" }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.expanded
        implicitHeight: listColumn.implicitHeight + Metrics.spaceSm * 2
        radius: Metrics.radiusCard
        color: Colors.solidSurface
        border.width: Metrics.borderWidth
        border.color: Colors.border

        ColumnLayout {
            id: listColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceSm
            spacing: Metrics.spaceXxs

            Rectangle {
                Layout.fillWidth: true
                visible: root.filterable
                implicitHeight: Metrics.controlHeightSm + Metrics.spaceXs
                radius: Metrics.pillRadius(height)
                color: Colors.controlFill
                TextInput {
                    id: filterInput
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.spaceMd
                    anchors.rightMargin: Metrics.spaceMd
                    verticalAlignment: TextInput.AlignVCenter
                    // A long filter scrolls inside the capsule instead of
                    // running out of it.
                    clip: true
                    color: Colors.text
                    font.family: Typography.family
                    font.pixelSize: Typography.smallSize
                    onTextChanged: root.filter = text
                    Accessible.name: "Filter"
                    // Read like text (4.5:1); subtleText is for marks, not words.
                    ShellText { visible: parent.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Filter …"; role: "small"; color: Colors.mutedText }
                }
            }

            // Created only while expanded: long option lists (fonts) would
            // otherwise build delegates for every page load.
            Loader {
                Layout.fillWidth: true
                active: root.expanded
                sourceComponent: ListView {
                    id: list
                    implicitHeight: Math.min(contentHeight, root.listHeight)
                    clip: true
                    model: root.visibleOptions
                    boundsBehavior: Flickable.StopAtBounds
                    // So a walk past the fold brings the row into view.
                    currentIndex: root.walkIndex
                    highlightFollowsCurrentItem: true
                    preferredHighlightBegin: 0
                    preferredHighlightEnd: height
                    highlightRangeMode: ListView.ApplyRange
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        width: list.width
                        implicitHeight: Metrics.controlHeight
                        title: modelData.label
                        selected: modelData.value === root.current
                        highlighted: index === root.walkIndex
                        onClicked: { root.selected(modelData.value); root.expanded = false }
                    }
                }
            }
        }
    }
}
