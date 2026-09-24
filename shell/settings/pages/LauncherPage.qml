import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/launcher/WebSearch.js" as Web
import "../../../services/launcher/ModeOrder.js" as Order
import "../../../services/launcher/Pinned.js" as Pinned

// Settings > Launcher: what the launcher does besides finding apps.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    readonly property string engine: SettingsService.value("launcher.searchEngine")
    readonly property string modeOrder: SettingsService.value("launcher.modeOrder")
    readonly property var modeIds: LauncherService.allModes.map(mode => mode.id)
    readonly property string template: SettingsService.value("launcher.searchUrl")

    SettingsSection {
        Layout.fillWidth: true
        title: "Modes"
        description: "What the switch beside the search field offers, and in which order. Apps leads and does not move: it is the one with no prefix, the mode the launcher opens in."

        Repeater {
            model: LauncherService.modes
            ListRow {
                required property var modelData
                readonly property string id: modelData.id
                Layout.fillWidth: true
                compact: true
                level: 1
                icon: modelData.icon
                title: modelData.label
                subtitle: modelData.prefix.length ? "Type " + modelData.prefix + " to reach it"
                    : "No prefix - the mode it opens in"
                // A `ListRow`'s trailing slot is a plain Item, so two children
                // sit on top of each other. Anything with more than one thing
                // in it brings its own row.
                RowLayout {
                    spacing: Metrics.spaceXxs
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.raise
                        variant: "ghost"
                        compact: true
                        toolTip: "Earlier in the switch"
                        enabledState: Order.canMove(root.modeOrder, root.modeIds, id, -1)
                        onClicked: SettingsService.set("launcher.modeOrder",
                                                       Order.move(root.modeOrder, root.modeIds, id, -1))
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.collapse
                        variant: "ghost"
                        compact: true
                        toolTip: "Later in the switch"
                        enabledState: Order.canMove(root.modeOrder, root.modeIds, id, 1)
                        onClicked: SettingsService.set("launcher.modeOrder",
                                                       Order.move(root.modeOrder, root.modeIds, id, 1))
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Item { Layout.fillWidth: true }
            ShellButton {
                focusOnTab: true
                icon: Icons.reset
                text: "Reset order"
                compact: true
                enabledState: root.modeOrder.length > 0
                onClicked: SettingsService.set("launcher.modeOrder", "")
            }
        }

        // The categories used to be a switch here. Where they are is a layout
        // question now - in the sidebar, in the column as a row of chips, or
        // nowhere at all - and a switch beside the layout that decides the
        // same thing is two answers to one question.
        ShellText {
            Layout.fillWidth: true
            text: "App categories sit in the sidebar, as a row of chips, or not at all. The pencil in the launcher's own header arranges its blocks; Ctrl+Up and Ctrl+Down walk the categories wherever they are."
            role: "small"; muted: true; wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Pinned apps"
        description: "Shown in front of the search field while nothing is typed - the one thing on a search surface that does not compete with the results, because it answers the question you have not asked yet."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show pinned apps"
            hint: "Right-click an app in the launcher to pin it, or Ctrl+P on the selected one. At most " + Pinned.LIMIT + "."
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("launcher.showPinned")
                onToggled: value => SettingsService.set("launcher.showPinned", value)
            }
        }

        Repeater {
            model: LauncherService.pinnedApps
            ListRow {
                required property var modelData
                readonly property string id: modelData.id
                Layout.fillWidth: true
                compact: true
                level: 1
                iconSource: LauncherService.iconSource(modelData.icon)
                title: modelData.name || modelData.id
                RowLayout {
                    spacing: Metrics.spaceXxs
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.raise
                        variant: "ghost"
                        compact: true
                        toolTip: "Earlier in the row"
                        enabledState: LauncherService.pinnedApps.length > 1 && LauncherService.pinnedApps[0].id !== id
                        onClicked: LauncherService.movePinned(id, -1)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.collapse
                        variant: "ghost"
                        compact: true
                        toolTip: "Later in the row"
                        enabledState: LauncherService.pinnedApps.length > 1
                            && LauncherService.pinnedApps[LauncherService.pinnedApps.length - 1].id !== id
                        onClicked: LauncherService.movePinned(id, 1)
                    }
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.remove
                        variant: "ghost"
                        compact: true
                        toolTip: "Unpin"
                        onClicked: LauncherService.togglePin(id)
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: LauncherService.pinnedApps.length === 0
            row: true
            icon: "󰐃"
            title: "Nothing pinned yet"
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Web search"
        description: "Type ? followed by what you are looking for. An address you type is offered as “Open” without a prefix."

        SettingRow {
            Layout.fillWidth: true
            label: "Search with"
            ShellSelect {
                Layout.fillWidth: true
                focusOnTab: true
                options: Web.engines.map(entry => ({ value: entry.value, label: entry.label }))
                current: root.engine
                onSelected: value => SettingsService.set("launcher.searchEngine", value)
            }
        }

        SettingRow {
            Layout.fillWidth: true
            visible: root.engine === "custom"
            label: "Address"
            hint: "Put %s where the search term belongs"
            ShellTextField {
                Layout.fillWidth: true
                focusOnTab: true
                text: root.template
                placeholder: "https://example.org/search?q=%s"
                border.color: Web.customError(text).length ? Colors.danger
                    : inputActiveFocus ? Colors.accentBorder : Colors.border
                onTextChanged: SettingsService.set("launcher.searchUrl", text)
            }
        }

        ShellText {
            Layout.fillWidth: true
            visible: root.engine === "custom" && Web.customError(root.template).length > 0
            text: Web.customError(root.template)
            role: "small"
            color: Colors.danger
            wrapMode: Text.Wrap
        }

        ShellText {
            Layout.fillWidth: true
            visible: Web.searchUrl("example", root.engine, root.template).length > 0
            text: "Example: ?example opens " + Web.searchUrl("example", root.engine, root.template)
            role: "small"
            muted: true
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Files"

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Search files with /"
            hint: "Uses plocate; results open in the default app"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("launcher.fileSearch")
                onToggled: value => SettingsService.set("launcher.fileSearch", value)
            }
        }
    }
}
