import QtQuick
import QtQuick.Layouts
import qs.theme

// One UI tabs: a soft trough with a solid capsule that slides to the selected
// segment. style "underline" (control-center tabs) slides an accent line
// instead. "pill" is the settings choice control.
//
// A segment that draws only its icon (compact) still has its label: it is the
// segment's name for a screen reader and the tooltip under the pointer.
Item {
    id: root
    property var options: []          // [{ value, label, icon, badge }]
    property string current: options.length ? options[0].value : ""
    property string style: "pill"
    // Compact: only the active segment shows its label, the others their icon.
    property bool compact: false
    // Background corner radius; embedded controls match their container.
    property real backgroundRadius: Metrics.pillRadius(implicitHeight)
    property bool focusOnTab: false
    // Dimmed, and then no segment lights up or answers - not the mouse, not
    // the arrows, not a screen reader - like ShellButton's `enabledState`.
    property bool enabledState: true
    signal selected(string value)

    readonly property int currentIndex: options.findIndex(option => option.value === root.current)
    function step(delta) {
        if (!root.enabledState || !options.length) return
        const next = Math.max(0, Math.min(options.length - 1, (currentIndex < 0 ? 0 : currentIndex) + delta))
        if (options[next].value !== root.current) root.selected(options[next].value)
    }
    function choose(value) {
        if (root.enabledState) root.selected(value)
    }

    activeFocusOnTab: focusOnTab && enabledState
    opacity: enabledState ? 1 : Effects.disabledOpacity
    // One tab stop for the whole control; Left and Right move inside it. Up
    // and Down are left to the panel, as on the slider: a panel that walks
    // its controls with the arrows (NavLogic) stepped into the control and
    // the next Down switched the desktop mode or the power profile.
    Keys.onLeftPressed: root.step(-1)
    Keys.onRightPressed: root.step(1)
    Keys.onUpPressed: event => event.accepted = false
    Keys.onDownPressed: event => event.accepted = false
    FocusRing { active: root.activeFocus; controlRadius: root.backgroundRadius }

    // Named by its row (SettingRow) or the caller; the chosen segment is the
    // description.
    property string accessibleName: ""
    Accessible.role: root.style === "underline" ? Accessible.PageTabList : Accessible.ComboBox
    Accessible.name: root.accessibleName
    Accessible.description: root.currentIndex >= 0 ? (root.options[root.currentIndex].label || "") : ""

    // Geometry of the active segment, kept for the sliding indicator.
    property real activeX: 0
    property real activeWidth: 0
    property bool indicatorReady: false
    function syncIndicator(segment) {
        activeX = segment.x + row.x
        activeWidth = segment.width
        indicatorReady = activeWidth > 0
    }

    implicitHeight: style === "underline" ? Metrics.controlHeight + Metrics.spaceXs : Metrics.controlHeightLg
    implicitWidth: row.implicitWidth

    Rectangle {
        anchors.fill: parent
        visible: root.style === "pill"
        radius: root.backgroundRadius
        color: Colors.sunken
        border.width: Metrics.borderWidth
        border.color: Colors.border
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Metrics.borderWidth
        visible: root.style === "underline"
        color: Colors.border
    }

    // Sliding selection: a capsule for "pill", a line for "underline".
    Rectangle {
        id: indicator
        // Nothing selected, nothing drawn. `indicatorReady` only says the
        // capsule has been given a width at some point; it stays true when
        // `current` later matches no option, and the capsule then sits empty
        // wherever it last was - which is what a profile that is not the
        // active one looked like on the Profiles page: a blank grey pill
        // floating between two glyphs.
        visible: root.indicatorReady && root.currentIndex >= 0
        x: root.activeX + (root.style === "underline" ? Metrics.spaceLg : 0)
        width: Math.max(0, root.activeWidth - (root.style === "underline" ? Metrics.spaceLg * 2 : 0))
        y: root.style === "underline" ? parent.height - height : Metrics.spaceXs
        height: root.style === "underline" ? Metrics.focusBorderWidth : parent.height - Metrics.spaceXs * 2
        radius: root.style === "underline" ? height : Metrics.pillRadius(height)
        // The line is a mark, not a fill: the accent made readable against
        // the surface (3:1), as every other accent line is.
        color: root.style === "underline" ? Colors.accentLine : Colors.segmentSelected
        border.width: root.style === "underline" ? 0 : Metrics.borderWidth
        border.color: Colors.border
        Behavior on x { enabled: Animations.motionEnabled; SpringMotion { kind: "fast" } }
        Behavior on width { enabled: Animations.motionEnabled; SpringMotion { kind: "fast" } }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: root.style === "pill" ? Metrics.spaceXs : 0
        spacing: root.style === "pill" ? Metrics.spaceXs : 0

        Repeater {
            model: root.options
            delegate: Item {
                id: segment
                required property var modelData
                readonly property bool active: modelData.value === root.current
                // Compact and not chosen: the glyph is all that is drawn.
                readonly property bool iconOnly: root.compact && !segment.active
                    && (segment.modelData.icon || "").length > 0
                readonly property bool hovered: segmentMouse.containsMouse && root.enabledState
                Layout.fillWidth: !root.compact
                Layout.fillHeight: true
                implicitWidth: segmentRow.implicitWidth + (root.compact ? Metrics.controlPaddingSm : Metrics.controlPadding) * 2
                // Never shrink below the label: with a wide font the segments
                // used to overlap ("5 min15 min30 min") instead of asking the
                // row for more width.
                Layout.minimumWidth: Math.min(implicitWidth, root.width / Math.max(1, root.options.length))

                onActiveChanged: if (active) root.syncIndicator(segment)
                onXChanged: if (active) root.syncIndicator(segment)
                onWidthChanged: if (active) root.syncIndicator(segment)
                Component.onCompleted: if (active) root.syncIndicator(segment)

                // Named by its label whether the label is drawn or not.
                Accessible.role: root.style === "underline" ? Accessible.PageTab : Accessible.RadioButton
                Accessible.name: segment.modelData.label || ""
                Accessible.checkable: true
                Accessible.checked: segment.active
                Accessible.onPressAction: root.choose(segment.modelData.value)

                // The label a glyph stands for, under a resting pointer; a
                // segment that draws its label has nothing to add.
                ToolTipHost {
                    id: tip
                    anchorItem: segment
                    text: segment.iconOnly && root.enabledState ? (segment.modelData.label || "") : ""
                    onTextChanged: if (!text.length) release()
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: root.style === "pill" ? 0 : Metrics.spaceXs
                    anchors.bottomMargin: root.style === "pill" ? 0 : Metrics.spaceXs
                    radius: Metrics.pillRadius(height)
                    color: segmentMouse.pressed && segment.hovered ? Colors.pressed
                        : segment.hovered && !segment.active ? Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
                }

                RowLayout {
                    id: segmentRow
                    anchors.centerIn: parent
                    // Never wider than the segment: the row narrows and the
                    // label elides. The segment's width is read here and fed
                    // back into nothing - a Layout.maximumWidth on the label
                    // made from segment.width was a recursive rearrange in
                    // compact mode, because the label's cap is part of this
                    // row's implicit width, which is what the segment's own
                    // width comes from when it does not fill.
                    width: Math.min(implicitWidth, Math.max(0, segment.width - (root.compact ? Metrics.controlPaddingSm : Metrics.controlPadding) * 2))
                    spacing: Metrics.spaceSm
                    ShellIcon {
                        visible: (segment.modelData.icon || "").length > 0
                        glyph: segment.modelData.icon || ""
                        size: Metrics.iconSm
                        color: segment.active ? Colors.accentForeground : Colors.mutedText
                    }
                    ShellText {
                        visible: !segment.iconOnly
                        text: segment.modelData.label
                        color: segment.active ? (root.style === "pill" ? Colors.text : Colors.accentForeground) : Colors.mutedText
                        // Cut the label rather than paint it over the
                        // neighbour: the label is what gives way when the
                        // row above is narrower than its content.
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    // Small tag after the label, e.g. "Current".
                    Rectangle {
                        visible: (segment.modelData.badge || "").length > 0 && (!root.compact || segment.active)
                        Layout.preferredWidth: badgeText.implicitWidth + Metrics.spaceSm * 2
                        Layout.preferredHeight: badgeText.implicitHeight + Metrics.spaceXxs * 2
                        radius: Metrics.pillRadius(height)
                        color: segment.active ? Colors.accent : Colors.surface2
                        ShellText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: segment.modelData.badge || ""
                            role: "caption"
                            color: segment.active ? Colors.accentText : Colors.mutedText
                        }
                    }
                }

                MouseArea {
                    id: segmentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.enabledState
                    cursorShape: Qt.PointingHandCursor
                    onEntered: tip.arm()
                    onExited: tip.release()
                    onClicked: {
                        tip.release()
                        root.choose(segment.modelData.value)
                    }
                }
            }
        }
    }
}
