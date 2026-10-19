import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/profile/ProfileLogic.js" as Profile
import "../../../services/settings/ScopeLogic.js" as Scope

// The two levels, as one page. A profile is a card; its five modes are a
// compact row **inside** the card rather than five rows under it, because five
// rows per profile turns the page into a wall by the second one.
ColumnLayout {
    id: page
    spacing: Metrics.pageGap

    // What a mode does as it ships (its template's description), under the
    // pointer on its segment: "Gaming" said nothing about turning Do Not
    // Disturb on until it had.
    function modeDescription(name) {
        const template = LayoutService.templates[name]
        return template && typeof template.description === "string" ? template.description : ""
    }
    readonly property var modeOptions: LayoutService.modeNames.map(name => ({
        value: name,
        label: Profile.label(name, LayoutService.templates),
        icon: Profile.icon(name),
        toolTip: page.modeDescription(name)
    }))
    readonly property string activeModeDescription: page.modeDescription(LayoutService.activeMode)

    SettingsSection {
        Layout.fillWidth: true
        title: "Profiles"
        // What a built-in profile does the first time, said once for all of
        // them rather than on every built-in card, where it pushed the
        // card's own buttons down. The shipped setup is the layouts, the
        // notch, the settings, the default apps and fastfetch.
        description: "A profile keeps everything - its five modes' layouts, the notch, panels, colors and all other settings - and switching brings them back. A built-in profile starts from its shipped setup the first time (after a backup) and keeps your changes; Restore settings brings the shipped one back."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: AdaptiveService.hasInternal
            label: "Choose the mode automatically"
            hint: "Laptop without, Desk with an external display. It switches the mode inside the profile you are in; it never changes the profile."
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
                        // The label is edited where it is shown. A dialog for
                        // one word is a dialog too many. Escape never leaves
                        // it blank: an emptied field gets the label back
                        // (StoredTextField). The guard that was meant to do
                        // that here never ran - Keys.onEscapePressed in the
                        // field takes the key before Keys.onPressed sees it.
                        StoredTextField {
                            id: nameField
                            Layout.fillWidth: true
                            focusOnTab: true
                            storedText: LayoutService.profileLabelOf(card.modelData)
                            onCommit: value => LayoutService.renameProfile(card.modelData, value)
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
                            icon: Icons.copy; text: "Duplicate"; compact: true
                            toolTip: "A copy of this profile as it stands, settings included"
                            onClicked: LayoutService.duplicateProfile(card.modelData,
                                                                     LayoutService.profileLabelOf(card.modelData) + " copy")
                        }
                        // Named by what it takes back, so the two buttons of a
                        // built-in profile differ before the pointer rests on
                        // them: Reset all is the modes and the settings,
                        // Restore settings the settings alone.
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.reset; text: card.builtin.length ? "Reset all" : "Reset modes"; compact: true
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
                            toolTip: card.active ? "The shipped settings, notch, lock screen, default apps and fastfetch, after a backup; the modes stay as they are"
                                                 : "Forgets your changes to its settings; using it next brings the shipped setup again. The modes stay as they are"
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
            ShellButton { focusOnTab: true; icon: Icons.arrange; text: "Widgets"; compact: true; onClicked: PanelService.open("settings", { page: "widgets" }) }
            ShellButton { focusOnTab: true; icon: "󰘔"; text: "Bar & notch"; compact: true; onClicked: PanelService.open("settings", { page: "bar" }) }
        }
        // What the mode does as it ships, Do Not Disturb included: a mode
        // switch is the only place that turns it on by itself.
        ShellText {
            Layout.fillWidth: true
            visible: page.activeModeDescription.length > 0
            // The description is written to stand alone ("The notch only,
            // …"); after the colon its first word goes small, unless it is
            // a name in capitals.
            text: Profile.label(LayoutService.activeMode, LayoutService.templates) + " as it ships: "
                + (/^[A-Z](?![A-Z])/.test(page.activeModeDescription)
                   ? page.activeModeDescription.charAt(0).toLowerCase() + page.activeModeDescription.slice(1)
                   : page.activeModeDescription)
            role: "small"; muted: true; wrapMode: Text.Wrap
        }

        // The settings a mode owns, named rather than implied: a user who
        // changes the blur in Docked and finds Laptop unchanged should be able
        // to read why here, and a control that has a scope has to say it.
        ShellText {
            Layout.fillWidth: true
            text: "Blur, panel opacity, animation mode and speed, corner radius, window borders and gaps are the mode's own - each mode keeps its own. Everything else belongs to the profile, except " + Scope.machineSettings() + ", which stay the same in every profile."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }
        // A page of this panel: the forward chevron, after the word, where
        // it reads as going on.
        ShellButton {
            focusOnTab: true
            trailingIcon: Icons.forward; text: "Appearance"; compact: true
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
