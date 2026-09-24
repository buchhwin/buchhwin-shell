import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/profile/ProfileLogic.js" as Profile

// `Super+P`: the two levels, small enough to be a key rather than a page. The
// profiles as rows and the five modes of the active one as a row of chips -
// the same shape as the Profiles settings page, which is where anything that
// needs typing (adding, renaming, resetting) lives.
PopupPanel {
    id: root
    panelId: "profilePopup"
    heading: "Profile"
    detail: LayoutService.activeProfileLabel
    glyph: Profile.icon(LayoutService.activeMode)
    glyphActive: true
    footerText: "Profile settings"
    onFooterClicked: PanelService.open("settings", { page: "profiles" })

    body: ColumnLayout {
        spacing: Metrics.panelGap

        CardSection {
            Layout.fillWidth: true
            title: "Mode"
            description: "What the desktop is set to right now"
            SegmentedControl {
                Layout.fillWidth: true
                compact: true
                focusOnTab: true
                current: LayoutService.activeMode
                options: LayoutService.modeNames.map(name => ({
                    value: name,
                    label: Profile.label(name, LayoutService.templates),
                    icon: Profile.icon(name)
                }))
                onSelected: value => LayoutService.setActiveMode(value)
            }
            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                visible: AdaptiveService.hasInternal
                label: "Automatic"
                hint: "Laptop without, Docked with an external display"
                ShellToggle {
                    focusOnTab: true
                    checked: SettingsService.value("desktop.autoProfile")
                    onToggled: value => SettingsService.set("desktop.autoProfile", value)
                }
            }
        }

        ScrollList {
            Layout.fillWidth: true
            title: "Profile"
            // One profile is not a list, it is a fact, and the mode row above
            // already says everything there is to say about it.
            visible: LayoutService.profileNames.length > 1
            Repeater {
                model: LayoutService.profileNames
                ListRow {
                    required property string modelData
                    // A ScrollList is a plain Column, not a layout, so a row
                    // that only fills a layout is a row with no width at all.
                    width: parent.width
                    level: 1
                    focusOnTab: true
                    icon: Profile.profileIcon()
                    title: LayoutService.profileLabelOf(modelData)
                    subtitle: LayoutService.modeSummary(modelData)
                    selected: LayoutService.activeProfile === modelData
                    onClicked: LayoutService.setActiveProfile(modelData)
                }
            }
        }
    }
}
