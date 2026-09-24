import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Desktop mode "Notch" inside the layout editor. The notch itself is a fixed
// element at the top center - it cannot be moved - but what it carries can be
// arranged, and that happens on the real notch: while this is open the notch
// holds itself expanded and draws both of its lists at once, the always
// visible strip above its header and the hover overview below it.
// NotchEditOverlay puts the frames, the drop marker and the ghost on top of
// them, because the notch is its own layer surface and this editor covers it.
//
// What is left here is the frame around the notch, the row that adds what is
// not on it yet, and the options it shares with Settings > Bar & Notch.
//
// The options go through LayoutService.changeNotch, so Ctrl+Z in the editor
// reaches them: they live in settings.json rather than in the layout file, and
// an undo step carries their values along. The two lists live in layout.json
// and go through changeNotchLayout, which takes its own undo step.
Item {
    id: root
    required property string screenName
    readonly property var notch: LayoutService.notchRect(screenName)
    // The catalogue minus what is already on the notch. A type sits in one
    // zone or the other, never in both, which is what addNotchItem enforces.
    readonly property var missing: NotchService.catalogue().filter(entry =>
        NotchService.collapsedTypes.indexOf(entry.type) < 0
        && NotchService.expandedTypes.indexOf(entry.type) < 0)
    // The notch reports its collapsed rectangle for the panels to align to and
    // its live size separately; while the editor holds it expanded, the frame
    // and the chips have to follow the expanded one.
    readonly property var state: NotchService.states[screenName] || null
    readonly property real notchWidth: state && state.expanded ? state.width
        : notch ? notch.width : Metrics.notchMinWidth
    readonly property real notchHeight: state && state.expanded ? state.height
        : notch ? notch.height : Metrics.notchHeight

    implicitHeight: hint.y + hint.height

    // The notch shows what it would show, so turning a field off is visible
    // where it happens. It goes back to its own behaviour when the editor
    // closes; `forcedScreen` is the same handle the IPC preview uses.
    // Not `visible` alone: the editor's window is built once and only hidden,
    // so this item is visible from the moment the desktop mode is "notch",
    // whether or not the editor is open. Binding the notch's state to it left
    // the notch collapsed the second time the editor was opened.
    readonly property bool active: visible && LayoutService.editMode
    // One width for the switch, the picker and the options card: three
    // different widths stacked under the notch read as three separate things.
    readonly property real cardWidth: Math.min(root.width - Metrics.spaceLg * 2,
                                               Metrics.editorSidebarWidth * 3)

    function follow() {
        LayoutService.notchEditing = active
        // The strip is arranged on the collapsed notch, the overview on the
        // expanded one, so the editor only holds it open for the second.
        if (active && LayoutService.notchEditZone === "expanded") NotchService.expand(screenName)
        else if (NotchService.forcedScreen === screenName) NotchService.collapse()
    }

    Connections {
        target: LayoutService
        function onNotchEditZoneChanged() { root.follow() }
    }

    onActiveChanged: follow()
    Component.onCompleted: follow()
    Component.onDestruction: {
        LayoutService.notchEditing = false
        if (NotchService.forcedScreen === screenName) NotchService.collapse()
    }

    // Where the notch is, so the controls below it line up. The outline
    // itself is NotchEditOverlay's - it is the thing being dragged.
    Item {
        id: frame
        x: (root.width - width) / 2
        y: root.notch ? root.notch.y : 0
        width: root.notchWidth
        height: root.notchHeight
    }

    // Which of the two shapes is being worked on. They are different sizes and
    // different lists, and only one of them is on screen at a time.
    //
    // Two columns of the same shape under the notch: what it carries on the
    // left, what it is on the right. Both cards are the same width and the
    // same height, so the pair reads as one block rather than as a pile.
    Item {
        id: panels
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: frame.bottom
        anchors.topMargin: Metrics.spaceMd
        width: root.cardWidth
        height: Math.max(fields.implicitHeight, options.implicitHeight)

        readonly property real columnWidth: (width - Metrics.spaceMd) / 2

        EditorPanel {
            id: fields
            width: panels.columnWidth
            height: panels.height
            title: "What it carries"

            SegmentedControl {
                id: zoneSwitch
                Layout.fillWidth: true
                current: LayoutService.notchEditZone
                options: [{ value: "collapsed", label: "Strip" }, { value: "expanded", label: "On hover" }]
                onSelected: value => LayoutService.notchEditZone = value
            }

            Flow {
                id: picker
                Layout.fillWidth: true
                spacing: Metrics.spaceXs

                Repeater {
                    model: root.missing
                    ShellButton {
                        required property var modelData
                        icon: modelData.icon
                        variant: "surface"
                        compact: true
                        toolTip: "Add " + modelData.label
                        onClicked: LayoutService.notchAdd(modelData.type, LayoutService.notchEditZone)
                    }
                }
                // Arranging pushes undo steps like every other editor
                // does, so it offers the way back like every other editor.
                ShellButton {
                    icon: Icons.undo
                    variant: "ghost"
                    compact: true
                    enabledState: LayoutService.undoStack.length > 0
                    toolTip: "Undo"
                    onClicked: LayoutService.undo()
                }
                ShellButton {
                    icon: Icons.reset
                    variant: "ghost"
                    compact: true
                    toolTip: "Back to the default notch"
                    onClicked: LayoutService.notchResetLayout()
                }
            }
        }
    }

    ShellText {
        id: hint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: panels.bottom
        anchors.topMargin: Metrics.spaceSm
        width: root.cardWidth
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: LayoutService.notchEditZone === "collapsed"
            ? "The notch sits at the top center and cannot be moved · drag its right edge to set how wide the strip is · ↓ sends an item to the overview"
            : "Drag a tile to reorder it, its corner to size it · drag the notch's own corner to size the overview · ↑ sends an item to the strip"
        role: "small"
        color: Colors.text
        style: Text.Outline
        styleColor: Colors.scrimStrong
    }

    EditorPanel {
        id: options
        parent: panels
        x: panels.columnWidth + Metrics.spaceMd
        width: panels.columnWidth
        height: panels.height
        title: "Notch"

        ShellText {
            Layout.fillWidth: true
            text: "A fixed element at the top center: the time, and a small overview on hover. Applies to all profiles."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }

        // Every option the Bar & Notch page has, not a subset of it: two places
        // that show different halves of one thing are worse than one place.
        // The size is not among them any more - it is dragged on the notch.
        SettingRow {
            Layout.fillWidth: true
            label: "Shape"
            hint: "A pill is the same notch, let go of the top edge - everything it carries and everything it does stays the same"
            SegmentedControl {
                Layout.fillWidth: true
                current: SettingsService.value("notch.shape")
                options: [{ value: "notch", label: "Notch" }, { value: "pill", label: "Pill" }]
                onSelected: value => LayoutService.changeNotch("notch.shape", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Events"
            hint: "How many appear in the expanded notch"
            SegmentedControl {
                Layout.fillWidth: true
                current: String(SettingsService.value("notch.eventCount"))
                options: [{ value: "1", label: "1" }, { value: "2", label: "2" },
                          { value: "3", label: "3" }, { value: "4", label: "4" }]
                onSelected: value => LayoutService.changeNotch("notch.eventCount", Number(value))
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Expand on hover"
            hint: "Otherwise a click opens the overview"
            ShellToggle {
                checked: SettingsService.value("notch.expandOnHover")
                onToggled: value => LayoutService.changeNotch("notch.expandOnHover", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Reserve space for windows"
            ShellToggle {
                checked: SettingsService.value("notch.reserve")
                onToggled: value => LayoutService.changeNotch("notch.reserve", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "In fullscreen"
            SegmentedControl {
                Layout.fillWidth: true
                current: SettingsService.value("notch.fullscreen")
                options: [{ value: "hide", label: "Hide" }, { value: "show", label: "Always show" }]
                onSelected: value => LayoutService.changeNotch("notch.fullscreen", value)
            }
        }
    }
}
