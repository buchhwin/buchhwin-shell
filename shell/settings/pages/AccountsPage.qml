import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Accounts: the KDE PIM (Akonadi) resources that stand for an
// account, grouped by what they hold. Adding an account opens KDE's own
// wizard; the shell never asks for a password and keeps no tokens. Refreshes
// every 10 s while the page is shown.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    PageActivity {
        onOpened: AccountsService.track()
        onClosed: AccountsService.untrack()
    }

    function toneColor(tone) {
        return tone === "error" ? Colors.danger : tone === "busy" ? Colors.accentForeground
            : tone === "ok" ? Colors.success : Colors.mutedText
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "KDE PIM"
        description: AccountsService.summary

        ListRow {
            Layout.fillWidth: true
            icon: Icons.settings
            active: AccountsService.serverRunning
            title: AccountsService.serverRunning ? "KDE PIM is running"
                : AccountsService.known ? "KDE PIM (Akonadi) is not running" : "Checking …"
            subtitle: AccountsService.serverRunning
                ? "Calendars, contacts and mail are stored and synchronized by KDE PIM"
                : "Accounts appear once KDE PIM starts; opening a KDE app starts it"
        }
        ShellText {
            Layout.fillWidth: true
            text: "Accounts are added with KDE's own wizards. buchhwin-shell only shows them, synchronizes them and opens their settings; it never asks for a password and keeps no tokens."
            role: "caption"
            wrapMode: Text.Wrap
        }
        Flow {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            Repeater {
                model: AccountsService.addOptions
                ShellButton {
                    focusOnTab: true
                    required property var modelData
                    icon: Icons.add
                    text: modelData.label
                    compact: true
                    variant: "accent"
                    toolTip: modelData.hint
                    onClicked: AccountsService.addAccount(modelData)
                }
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: AccountsService.loading ? "Refreshing …" : "Refresh"
                compact: true
                onClicked: AccountsService.refresh()
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: AccountsService.addOptions.length === 0
            row: true
            icon: "󰀉"
            title: "No account wizard found"
            description: "KDE's own wizards add the accounts; none of them is installed on this machine"
        }
        EmptyState {
            Layout.fillWidth: true
            visible: AccountsService.known && AccountsService.serverRunning && AccountsService.accounts.length === 0
            row: true
            icon: "󰀉"
            title: "No accounts yet"
            description: "Add a Google, Nextcloud, CalDAV, CardDAV, IMAP or iCal account with one of the buttons above; calendars and contacts then show up in the dashboard"
        }
        ShellText {
            Layout.fillWidth: true
            visible: AccountsService.message.length > 0
            text: AccountsService.message
            role: "caption"
            color: AccountsService.messageError ? Colors.danger : Colors.mutedText
            wrapMode: Text.Wrap
        }
        ShellText {
            Layout.fillWidth: true
            visible: AccountsService.previewCommand.length > 0
            text: AccountsService.previewCommand
            role: "small"
            muted: true
            wrapMode: Text.Wrap
        }
    }

    Repeater {
        model: AccountsService.groups
        SettingsSection {
            id: groupSection
            required property var modelData
            Layout.fillWidth: true
            title: groupSection.modelData.title

            Repeater {
                model: groupSection.modelData.accounts
                ColumnLayout {
                    id: accountItem
                    required property var modelData
                    readonly property bool busy: AccountsService.isBusy(accountItem.modelData)
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXxs

                    ListRow {
                        Layout.fillWidth: true
                        icon: AccountsService.icon(accountItem.modelData)
                        // The accent marks activity, not simply being online.
                        active: AccountsService.statusTone(accountItem.modelData) === "busy"
                        title: accountItem.modelData.name
                        subtitle: AccountsService.subtitle(accountItem.modelData)
                        ShellText {
                            text: AccountsService.statusText(accountItem.modelData)
                            role: "small"
                            color: root.toneColor(AccountsService.statusTone(accountItem.modelData))
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: Metrics.spaceMd + Metrics.iconLg + Metrics.spaceMd
                        spacing: Metrics.spaceSm
                        ShellButton {
                            focusOnTab: true
                            icon: "󰚰"
                            text: "Sync now"
                            compact: true
                            enabledState: !accountItem.busy
                            onClicked: AccountsService.sync(accountItem.modelData)
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.settings
                            text: "Settings …"
                            compact: true
                            enabledState: !accountItem.busy
                            onClicked: AccountsService.configure(accountItem.modelData)
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.remove
                            text: "Remove"
                            compact: true
                            // The button asks twice, like every destructive
                            // one; the service's own second-click guard is
                            // satisfied up front so the confirmed click acts.
                            confirm: true
                            confirmText: "Click again to remove"
                            enabledState: !accountItem.busy
                            toolTip: "Takes the account out of KDE PIM; the account itself stays with its provider"
                            onClicked: {
                                AccountsService.confirmRemoveId = accountItem.modelData.id
                                AccountsService.remove(accountItem.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
