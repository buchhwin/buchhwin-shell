import QtQuick
import QtQuick.Layouts
import QtQuick.Window
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
    property real listHeight: Metrics.selectListHeight
    property bool previewFonts: false
    property string placeholder: ""
    property bool focusOnTab: false
    property string accessibleName: ""
    // Dimmed, and then it neither opens nor steps, by key, click or screen
    // reader - the pattern of ShellButton's and ShellToggle's `enabledState`.
    property bool enabledState: true
    signal selected(string value)
    spacing: Metrics.spaceXs
    opacity: enabledState ? 1 : Effects.disabledOpacity

    // Opening and closing, from the header, the filter and the rows alike.
    //
    // A list with a filter hands the focus to the filter as it opens, so
    // typing filters at once. Space used to open the font list and leave the
    // focus on the header, where "jet" walked nothing and filtered nothing.
    // Opened by a click, the filter takes the focus quietly - no ring, the way
    // a panel's search field takes it as the panel opens (ShellTextField): the
    // open list already marks the control. Closing hands the focus back to
    // where it came from: the header for the keyboard, whatever held it before
    // for the mouse, so a click on a row does not leave a ring on the header
    // nobody tabbed to, nor the focus nowhere.
    property Item returnFocus: null
    property bool quietFilter: false
    function openList(fromKeyboard) {
        if (!root.enabledState || root.expanded) return
        filterInput.text = ""
        root.filter = ""
        root.returnFocus = fromKeyboard ? header : Window.activeFocusItem
        root.expanded = true
        if (!root.filterable) return
        root.quietFilter = !fromKeyboard
        filterInput.forceActiveFocus(fromKeyboard ? Qt.TabFocusReason : Qt.MouseFocusReason)
    }
    function closeList() {
        if (!root.expanded) return
        // Read before the list goes: hiding the filter takes its focus away.
        const back = filterInput.activeFocus ? root.returnFocus : null
        root.expanded = false
        root.returnFocus = null
        if (back && back.visible) back.forceActiveFocus(Qt.OtherFocusReason)
    }
    function toggleList(fromKeyboard) {
        if (root.expanded) root.closeList()
        else root.openList(fromKeyboard)
    }
    onEnabledStateChanged: if (!enabledState) root.closeList()

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
        if (!root.enabledState || !options.length) return
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
        root.closeList()
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
        activeFocusOnTab: root.focusOnTab && root.enabledState
        // Open, the arrows walk the list and Enter takes the row they are on;
        // closed, they walk the value itself, like every other dropdown.
        // Disabled, the arrows go on to the panel: a select dimmed while it
        // held the focus must not trap the walk between controls.
        Keys.onUpPressed: event => {
            if (!root.enabledState) event.accepted = false
            else if (root.expanded) root.walk(-1)
            else root.step(-1)
        }
        Keys.onDownPressed: event => {
            if (!root.enabledState) event.accepted = false
            else if (root.expanded) root.walk(1)
            else root.step(1)
        }
        Keys.onReturnPressed: event => { if (root.expanded) root.takeWalked(); else event.accepted = false }
        Keys.onEnterPressed: event => { if (root.expanded) root.takeWalked(); else event.accepted = false }
        Keys.onSpacePressed: root.toggleList(true)
        Keys.onEscapePressed: event => { if (root.expanded) root.closeList(); else event.accepted = false }
        FocusRing { active: header.activeFocus; controlRadius: header.radius }
        Accessible.role: Accessible.ComboBox
        Accessible.name: root.accessibleName
        Accessible.description: root.currentOption ? root.currentOption.label : root.current
        Layout.fillWidth: true
        implicitHeight: Metrics.controlHeight
        radius: Metrics.pillRadius(height)
        // A dimmed select does not light up under the pointer either.
        readonly property bool hovered: headerMouse.containsMouse && root.enabledState
        readonly property bool down: headerMouse.pressed && hovered
        color: down ? Colors.controlFillPressed
            : hovered || root.expanded ? Colors.controlFillHover : Colors.controlFill
        border.width: Metrics.borderWidth
        border.color: root.expanded ? Colors.accentBorder : "transparent"
        scale: down ? Effects.pressScale : 1
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
            enabled: root.enabledState
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleList(false)
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
                id: filterBox
                Layout.fillWidth: true
                visible: root.filterable
                implicitHeight: Metrics.controlHeightSm + Metrics.spaceXs
                radius: Metrics.pillRadius(height)
                color: Colors.controlFill
                // The ring every other field shows, once the focus is in here
                // from the keyboard (quiet after a click, see openList).
                FocusRing { active: filterInput.activeFocus && !root.quietFilter; controlRadius: filterBox.radius }
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
                    onActiveFocusChanged: if (!activeFocus) root.quietFilter = false
                    // The header's keys, from where the typing is: the arrows
                    // walk what is left, Enter takes it, Escape closes the list
                    // and hands the focus back (to the header, when the list
                    // was opened from it). Enter with nothing left keeps the
                    // list open, so the filter can be corrected.
                    Keys.onUpPressed: root.walk(-1)
                    Keys.onDownPressed: root.walk(1)
                    Keys.onReturnPressed: if (root.visibleOptions.length) root.takeWalked()
                    Keys.onEnterPressed: if (root.visibleOptions.length) root.takeWalked()
                    Keys.onEscapePressed: root.closeList()
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Filter"
                    // Read like text (4.5:1); subtleText is for marks, not words.
                    ShellText { visible: parent.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Filter …"; role: "small"; color: Colors.mutedText }
                }
            }

            // A filter nothing matches says so, instead of an empty box under
            // the field that reads as a list still loading.
            ShellText {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.spaceMd
                Layout.preferredHeight: Metrics.controlHeight
                visible: root.filter.length > 0 && root.visibleOptions.length === 0
                verticalAlignment: Text.AlignVCenter
                text: "No matches"
                role: "small"
                muted: true
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
                        onClicked: { root.selected(modelData.value); root.closeList() }
                    }
                }
            }
        }
    }
}
