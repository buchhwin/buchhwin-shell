import QtQuick
import QtQuick.Layouts
import qs.theme

// Selectable list row with icon, title, subtitle and a trailing item.
// One UI: strongly rounded, a calm fill on hover and a short press dip.
Rectangle {
    id: root
    // The surface the row sits on, so hover and press stay visible on it:
    // 0 = straight on a panel, 1 = on a card, 2 = in a card inside a card.
    // Colors.hover is 0.06 and Colors.surface1 is 0.07, so a level-0 hover on
    // a card would be all but invisible.
    property int level: 0
    // A row in a dense list (menus, the launcher, the editor's pickers).
    property bool compact: false
    property string icon: ""
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property string trailingText: ""
    property bool selected: false
    // The row the keyboard is standing on, which is not the same thing as the
    // one that is chosen: an open list has both at once.
    property bool highlighted: false
    property bool active: false
    property bool chevron: false
    // Opt-in keyboard focus. Most lists in the shell are driven by the arrow
    // keys of the field above them, and those must not gain a tab stop per row.
    property bool focusOnTab: false
    // A row that says something rather than does something (a status, a
    // device, an enrolled finger) sets this to false: no pointer hand, no
    // hover fill, no press dip, no key and no button role. Every row drew
    // all four and twenty-odd of them did nothing when clicked. Its trailing
    // controls stay controls.
    property bool interactive: true
    // NavLogic asks `available` before it stops on a control; a row that is
    // not one is walked through to the controls inside it.
    readonly property bool available: interactive
    default property alias trailing: trailingSlot.data
    signal clicked()
    signal rightClicked()

    function activate() { if (root.interactive) root.clicked() }
    // The row's title names a trailing switch or slider that has no name of
    // its own, as SettingRow's label does: "Microphone" for the microphone's
    // switch rather than an unnamed check box.
    property string namedAs: ""
    function nameTrailing() {
        const kids = trailingSlot.children
        for (let i = 0; i < kids.length; ++i) {
            const kid = kids[i]
            if (kid.accessibleName === undefined) continue
            if (kid.accessibleName === root.title) continue
            if (kid.accessibleName === "" || kid.accessibleName === root.namedAs) kid.accessibleName = root.title
        }
        root.namedAs = root.title
    }
    onTitleChanged: nameTrailing()
    Component.onCompleted: nameTrailing()
    activeFocusOnTab: focusOnTab && interactive
    Keys.onSpacePressed: root.activate()
    Keys.onReturnPressed: root.activate()
    Keys.onEnterPressed: root.activate()
    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.title
    Accessible.description: root.subtitle
    Accessible.onPressAction: root.activate()
    FocusRing { active: root.activeFocus; controlRadius: root.radius }

    readonly property bool down: interactive && rowMouse.pressed && rowMouse.containsMouse
    readonly property color hoverColor: level >= 2 ? Colors.surface2Hover
        : level === 1 ? Colors.surface1Hover : Colors.hover
    readonly property color pressedColor: level >= 2 ? Colors.surface2Pressed
        : level === 1 ? Colors.surface1Pressed : Colors.pressed

    implicitHeight: compact ? Metrics.controlHeight + Metrics.spaceXs : Metrics.rowHeight
    radius: Metrics.radiusCard
    color: selected ? Colors.accentSoft : down ? pressedColor
        : (interactive && rowMouse.containsMouse) || highlighted ? hoverColor : "transparent"
    scale: down ? Effects.pressScaleWide : 1
    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => event.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.compact ? Metrics.spaceMd : Metrics.spaceLg
        anchors.rightMargin: root.compact ? Metrics.spaceMd : Metrics.spaceLg
        spacing: Metrics.spaceMd

        TileContent {
            Layout.fillWidth: true
            icon: root.icon
            iconSource: root.iconSource
            title: root.title
            subtitle: root.subtitle
            iconColor: root.active || root.selected ? Colors.accentForeground : Colors.mutedText
            titleColor: root.active ? Colors.accentForeground : Colors.text
        }
        ShellText {
            visible: root.trailingText.length > 0
            Layout.maximumWidth: Metrics.trailingTextMax
            text: root.trailingText; role: "small"; muted: true
        }
        Item {
            id: trailingSlot
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            visible: children.length > 0
            onChildrenChanged: root.nameTrailing()
        }
        ShellIcon { visible: root.chevron; glyph: Icons.forward; size: Metrics.iconXs; color: Colors.mutedText }
    }
}
