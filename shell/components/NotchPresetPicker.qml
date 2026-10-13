import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// Notch presets: the built-in ones and the user's own, each a whole notch -
// both lists and how it opens. Applying one is a single undo step; the
// current notch can be saved as a new one, and saved ones renamed or deleted.
// The same list in the layout editor and on the Bar & Notch page.
ColumnLayout {
    id: root
    spacing: Metrics.spaceSm

    property string renaming: ""
    // A layout file that could not be read is never written (LayoutService),
    // so applying or saving would do nothing; say so instead of pretending.
    readonly property bool writable: !LayoutService.readOnly

    // What a preset's strip carries, as the glyphs the editor's catalogue uses:
    // enough to tell two presets apart without a picture of each.
    function glyphs(preset) {
        return (preset.layout.collapsed || []).map(pill => NotchService.entry(pill.items[0].type).icon)
            .filter(icon => icon.length).join("  ")
    }

    Repeater {
        model: LayoutService.notchPresets
        ShellCard {
            id: card
            required property var modelData
            Layout.fillWidth: true
            interactive: root.writable
            hovered: cardMouse.containsMouse
            pressed: cardMouse.pressed && cardMouse.containsMouse
            implicitHeight: cardBody.implicitHeight + Metrics.spaceSm * 2
            // One tab stop per preset; Return or Space applies it.
            activeFocusOnTab: root.writable
            Keys.onReturnPressed: apply()
            Keys.onSpacePressed: apply()
            function apply() { if (root.writable && root.renaming !== card.modelData.id) LayoutService.applyNotchPreset(card.modelData.id) }
            FocusRing { active: card.activeFocus; controlRadius: card.radius }

            // Under the buttons, so rename and delete stay their own clicks.
            MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.writable
                onClicked: card.apply()
            }

            RowLayout {
                id: cardBody
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                spacing: Metrics.spaceSm
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ShellText {
                        Layout.fillWidth: true
                        visible: root.renaming !== card.modelData.id
                        text: card.modelData.label
                        elide: Text.ElideRight
                    }
                    ShellTextField {
                        id: renameField
                        Layout.fillWidth: true
                        visible: root.renaming === card.modelData.id
                        text: card.modelData.label
                        onAccepted: { LayoutService.renameNotchPreset(card.modelData.id, text); root.renaming = "" }
                        onEscapePressed: root.renaming = ""
                        // Fresh text and the cursor in it each time it opens:
                        // an edit dropped with Escape is not the next start.
                        onVisibleChanged: if (visible) { text = card.modelData.label; focusInput() }
                    }
                    ShellText {
                        Layout.fillWidth: true
                        text: card.modelData.description.length ? card.modelData.description : root.glyphs(card.modelData)
                        role: "small"; muted: true; wrapMode: Text.Wrap
                    }
                }
                ShellButton {
                    focusOnTab: true
                    visible: !card.modelData.builtin && root.writable
                    icon: Icons.edit; variant: "ghost"; compact: true; toolTip: "Rename"
                    onClicked: root.renaming = root.renaming === card.modelData.id ? "" : card.modelData.id
                }
                ShellButton {
                    focusOnTab: true
                    visible: !card.modelData.builtin && root.writable
                    icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Delete"
                    confirm: true; confirmText: "Delete?"
                    onClicked: LayoutService.removeNotchPreset(card.modelData.id)
                }
            }
        }
    }

    ShellText {
        Layout.fillWidth: true
        visible: !root.writable
        text: "The layout file could not be read, so presets cannot be applied or saved"
            + (LayoutService.readOnlyReason.length ? ": " + LayoutService.readOnlyReason : "")
        role: "small"; color: Colors.warning; wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.writable
        spacing: Metrics.spaceSm
        ShellTextField {
            id: nameField
            focusOnTab: true
            Layout.fillWidth: true
            placeholder: "Name for the current notch"
            onAccepted: save()
            function save() {
                if (!text.trim().length) return
                if (LayoutService.saveNotchPreset(text).length) text = ""
            }
        }
        ShellButton {
            focusOnTab: true
            icon: Icons.add; text: "Save as preset"; compact: true
            enabledState: nameField.text.trim().length > 0
            onClicked: nameField.save()
        }
    }
}
