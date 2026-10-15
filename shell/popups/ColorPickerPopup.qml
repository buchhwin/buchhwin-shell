import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// The colour picker's own window: what has been picked, and the way to pick
// again. A click on a swatch copies it back to the clipboard - the history is
// there to be used, not only to be looked at.
PopupPanel {
    id: root
    panelId: "colorPicker"
    heading: "Colors"
    detail: ColorPickerService.history.length
        ? ColorPickerService.history.length + " picked · " + ShortcutService.keyHint("SUPER + SHIFT + C", true) + " picks another"
        : ShortcutService.keyHint("SUPER + SHIFT + C", true) + " picks one off the screen"
    glyph: "󰈊"
    glyphActive: ColorPickerService.history.length > 0
    footerText: "Clear the list"
    footerGlyph: Icons.remove
    onFooterClicked: ColorPickerService.clearHistory()

    body: ColumnLayout {
        spacing: Metrics.spaceMd

        ShellButton {
            focusOnTab: true
            Layout.fillWidth: true
            icon: "󰈊"
            text: "Pick a color"
            variant: "accent"
            onClicked: {
                // The overlay covers the screen, so this panel goes first -
                // two full-screen surfaces both wanting the keyboard is the
                // one arrangement neither of them survives.
                PanelService.close("colorPicker")
                ColorPickerService.open()
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: ColorPickerService.history.length === 0
            icon: "󰈊"
            title: "Nothing picked yet"
            description: "Pick a color off the screen and it lands here and in the clipboard"
        }

        Flow {
            Layout.fillWidth: true
            visible: ColorPickerService.history.length > 0
            spacing: Metrics.spaceSm

            Repeater {
                model: ColorPickerService.history
                // A chip rather than a square: it carries its own hex, so the
                // row can be read without hovering anything, and it is as wide
                // as that number needs - a square with the number written
                // across it spills into its neighbours.
                Rectangle {
                    id: swatch
                    required property string modelData
                    implicitWidth: hex.implicitWidth + Metrics.spaceMd * 2
                    implicitHeight: Metrics.colorSwatch
                    radius: Metrics.radiusInner
                    color: swatch.modelData
                    border.width: swatchMouse.containsMouse ? Metrics.focusBorderWidth : Metrics.borderWidth
                    border.color: swatchMouse.containsMouse ? Colors.accentLine : Colors.border

                    // A stop for the panel's keys (NavLogic) like every other
                    // control here, and Return or Space copies as a click does.
                    property bool focusOnTab: true
                    activeFocusOnTab: focusOnTab
                    Keys.onReturnPressed: ColorPickerService.copy(swatch.modelData)
                    Keys.onEnterPressed: ColorPickerService.copy(swatch.modelData)
                    Keys.onSpacePressed: ColorPickerService.copy(swatch.modelData)
                    Accessible.role: Accessible.Button
                    Accessible.name: "Copy " + swatch.modelData.toUpperCase()
                    Accessible.onPressAction: ColorPickerService.copy(swatch.modelData)
                    FocusRing { active: swatch.activeFocus; controlRadius: swatch.radius }

                    // In whichever ink reads on it: a fixed one disappears
                    // into half the colours anybody picks. `overviewText`
                    // never existed, so every dark swatch had no ink at all,
                    // and the theme's text was the wrong one on light ones in
                    // the dark theme.
                    ShellText {
                        id: hex
                        anchors.centerIn: parent
                        text: swatch.modelData.slice(1).toUpperCase()
                        role: "small"
                        font.features: { "tnum": 1 }
                        color: Colors.textOn(swatch.modelData)
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ColorPickerService.copy(swatch.modelData)
                    }
                }
            }
        }
    }
}
