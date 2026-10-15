import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/profile/ProfileLogic.js" as Profile

// The two levels, as one page. A profile is a card; its five modes are a
// compact row **inside** the card rather than five rows under it, because five
// rows per profile turns the page into a wall by the second one.
ColumnLayout {
    id: page
    spacing: Metrics.pageGap

    readonly property var modeOptions: LayoutService.modeNames.map(name => ({
        value: name,
        label: Profile.label(name, LayoutService.templates),
        icon: Profile.icon(name)
    }))

    SettingsSection {
        Layout.fillWidth: true
        title: "Profiles"
        description: "A profile keeps everything: its five modes' layouts, the notch, panels, colors and all other settings. Switching brings them back."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: AdaptiveService.hasInternal
            label: "Choose the mode automatically"
            hint: "Laptop without, Docked with an external display. It switches the mode inside the profile you are in; it never changes the profile."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("desktop.autoProfile")
                onToggled: value => SettingsService.set("desktop.autoProfile", value)
            }
        }

        Repeater {
            model: LayoutService.profileNames
            ShellCard {
                id: card
                required property string modelData
                readonly property bool active: LayoutService.activeProfile === modelData
                // A profile the shell ships (LayoutService.builtinProfileNames):
                // always there, reset to what it shipped with, and its setup
                // applied the first time it is used.
                readonly property string builtin: LayoutService.builtinOf(modelData)
                readonly property bool applying: builtin.length > 0 && LayoutService.builtinApplying === builtin
                Layout.fillWidth: true
                // A card inside a settings section.
                level: 2
                implicitHeight: body.implicitHeight + Metrics.spaceMd * 2

                ColumnLayout {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Metrics.spaceMd
                    spacing: Metrics.spaceSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceSm
                        ShellTextField {
                            id: nameField
                            Layout.fillWidth: true
                            focusOnTab: true
                            // The label is edited where it is shown. A dialog
                            // for one word is a dialog too many.
                            text: LayoutService.profileLabelOf(card.modelData)
                            onAccepted: LayoutService.renameProfile(card.modelData, text)
                            // Escape puts the label back, before the field
                            // clears it: escapePressed only fires for an
                            // empty field, and a blank label is not "back".
                            onKeyPressed: event => {
                                if (event.key !== Qt.Key_Escape) return
                                text = LayoutService.profileLabelOf(card.modelData)
                                event.accepted = true
                            }
                        }
                        // A label, not a chip: a chip is a button, and there is
                        // nothing here to press.
                        ShellText {
                            visible: card.builtin.length > 0
                            text: "Built in"
                            role: "small"
                            muted: true
                        }
                        ShellText {
                            visible: card.active
                            text: "Active"
                            role: "small"
                            color: Colors.accentForeground
                        }
                        ShellButton {
                            visible: !card.active
                            focusOnTab: true
                            text: "Use"
                            variant: "accent"
                            compact: true
                            onClicked: LayoutService.setActiveProfile(card.modelData)
                        }
                    }

                    // The five modes of *this* profile. Choosing one on a
                    // profile that is not active switches to both at once,
                    // which is the only thing that sentence can mean.
                    //
                    // Not `compact`: compact draws the four that are not
                    // chosen as bare glyphs, and stretched across a card this
                    // wide that is five icons floating in an empty trough
                    // rather than a control. With their names they divide the
                    // width evenly, like every other segmented control on a
                    // settings page. The popup keeps `compact`, because a
                    // popup is narrow and five names do not fit.
                    SegmentedControl {
                        Layout.fillWidth: true
                        focusOnTab: true
                        options: page.modeOptions
                        current: card.active ? LayoutService.activeMode : ""
                        onSelected: value => {
                            if (!card.active) LayoutService.setActiveProfile(card.modelData)
                            LayoutService.setActiveMode(value)
                        }
                    }

                    // What activating it does, said before it is done: the
                    // first time it writes more than a switch otherwise does.
                    ShellText {
                        visible: card.builtin.length > 0
                        Layout.fillWidth: true
                        text: "Shipped with the shell: the first time you use it, it brings its setup - layouts, notch, settings, default apps, fastfetch - after a backup; after that it keeps your changes. Restore settings brings the shipped one back."
                        role: "small"; muted: true; wrapMode: Text.Wrap
                    }
                    // Its own error only: one that failed says so on its own
                    // card, not on every built-in one.
                    ShellText {
                        readonly property string error: LayoutService.builtinErrorOf(card.builtin)
                        visible: card.builtin.length > 0 && (card.applying || error.length > 0)
                        Layout.fillWidth: true
                        text: card.applying ? "Applying the shipped setup …" : error
                        role: "small"; wrapMode: Text.Wrap
                        color: card.applying ? Colors.mutedText : Colors.warning
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceSm
                        ShellText {
                            Layout.fillWidth: true
                            text: LayoutService.modeSummary(card.modelData)
                            role: "small"; muted: true; wrapMode: Text.Wrap
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.add; text: "Duplicate"; compact: true
                            toolTip: "A copy of this profile as it stands, settings included"
                            onClicked: LayoutService.duplicateProfile(card.modelData,
                                                                     LayoutService.profileLabelOf(card.modelData) + " copy")
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.reset; text: "Reset"; compact: true
                            confirm: true
                            confirmText: "Reset all five?"
                            toolTip: card.builtin.length ? "Every mode and setting of this profile back to the shipped state"
                                                         : "Every mode of this profile back to the factory state; its settings stay"
                            onClicked: LayoutService.resetProfile(card.modelData, "")
                        }
                        // In Remove's place: a built-in profile cannot be
                        // removed, and what it can do instead is go back to
                        // its shipped state - at once when it is in use,
                        // otherwise the next time it is.
                        ShellButton {
                            visible: card.builtin.length > 0
                            focusOnTab: true
                            icon: Icons.undo; text: "Restore settings"; compact: true
                            confirm: true
                            confirmText: card.active ? "Overwrite settings?" : "Back to shipped?"
                            enabledState: !LayoutService.readOnly && LayoutService.builtinApplying.length === 0
                            toolTip: card.active ? "The shipped settings, notch, lock screen, default apps and fastfetch, after a backup"
                                                 : "Forgets your changes to it; using it next brings the shipped setup again"
                            onClicked: LayoutService.applyBuiltin(card.builtin)
                        }
                        ShellButton {
                            visible: card.builtin.length === 0
                            focusOnTab: true
                            icon: Icons.remove; text: "Remove"; compact: true
                            confirm: true
                            confirmText: "Remove?"
                            // There has to be a profile to be in.
                            enabledState: LayoutService.profileNames.length > 1
                            onClicked: LayoutService.removeProfile(card.modelData)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellTextField {
                id: newField
                Layout.fillWidth: true
                focusOnTab: true
                icon: Icons.add
                placeholder: "New profile"
                onAccepted: if (text.trim().length) { LayoutService.addProfile(text); text = "" }
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.add; text: "Add"; variant: "accent"
                enabledState: newField.text.trim().length > 0
                // A new profile starts from the factory layouts, not from the
                // profile you are in - "Duplicate" is the other case. Its
                // settings are the ones in use when it is first entered.
                toolTip: "Factory layouts; it starts with the settings you have when you first use it"
                onClicked: { LayoutService.addProfile(newField.text); newField.text = "" }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "This mode"
        description: "What the active mode of the active profile is set to"

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                text: "Desktop mode: " + LayoutService.desktopModeLabel
                muted: true; wrapMode: Text.Wrap
            }
            ShellButton { focusOnTab: true; icon: Icons.edit; text: "Widgets"; compact: true; onClicked: PanelService.open("settings", { page: "widgets" }) }
            ShellButton { focusOnTab: true; icon: "󰘔"; text: "Bar & Notch"; compact: true; onClicked: PanelService.open("settings", { page: "bar" }) }
        }

        // The settings a mode owns, named rather than implied: a user who
        // changes the blur in Docked and finds Laptop unchanged should be able
        // to read why here, and a control that has a scope has to say it.
        ShellText {
            Layout.fillWidth: true
            text: "Blur, panel opacity, animation mode and speed, corner radius, window borders and gaps are the mode's own - each mode keeps its own. Everything else belongs to the profile, except the weather place, keyboard layout and displays, which stay the same in every profile."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }
        ShellButton {
            focusOnTab: true
            icon: Icons.forward; text: "Appearance"; compact: true
            onClicked: PanelService.open("settings", { page: "appearance" })
        }
        ShellText {
            visible: LayoutService.readOnly
            Layout.fillWidth: true
            text: "Layout is read-only: " + LayoutService.readOnlyReason
            color: Colors.warning
            wrapMode: Text.Wrap
        }
    }
}
