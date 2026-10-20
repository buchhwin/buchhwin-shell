import Quickshell
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
    spacing: Metrics.pageGap

    PageActivity {
        onOpened: AccountsService.track()
        onClosed: AccountsService.untrack()
    }

    function toneColor(tone) {
        return tone === "error" ? Colors.danger : tone === "busy" ? Colors.accentForeground
            : tone === "ok" ? Colors.positive : Colors.mutedText
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "KDE PIM"
        description: AccountsService.summary
        hint: "Accounts are added with KDE's own wizards; their calendars and contacts show in the dashboard. This shell never asks for a password and keeps no tokens."

        ListRow {
            interactive: false
            Layout.fillWidth: true
            icon: Icons.settings
            active: AccountsService.serverRunning
            title: AccountsService.serverRunning ? "KDE PIM is running"
                : AccountsService.known ? "KDE PIM (Akonadi) is not running" : "Checking …"
            subtitle: AccountsService.serverRunning
                ? "Keeps calendars, contacts and mail in sync"
                : "Opening a KDE app starts it"
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
            description: "None of KDE's account wizards is installed"
        }
        EmptyState {
            Layout.fillWidth: true
            visible: AccountsService.known && AccountsService.serverRunning && AccountsService.accounts.length === 0
            row: true
            icon: "󰀉"
            title: "No accounts yet"
            description: "Add a Google, Nextcloud, CalDAV, CardDAV, IMAP or iCal account above"
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

    // Kept sections and rows, not rebuilt ones: during a sync the status is
    // read anew every 10 s, `groups` is new each time, and a Repeater over it
    // made every row again - the keyboard focus on Sync now or Remove went,
    // and an armed Remove fell back to its first click. Keyed by plain
    // strings (group key, account id; pitfall 76), and each section and row
    // looks up what it currently says.
    Repeater {
        model: ScriptModel { values: AccountsService.groups.map(group => group.key) }
        SettingsSection {
            id: groupSection
            required property string modelData
            readonly property var group: AccountsService.groups.find(item => item.key === modelData) || null
            readonly property var accounts: group ? group.accounts : []
            Layout.fillWidth: true
            title: group ? group.title : ""

            Repeater {
                model: ScriptModel { values: groupSection.accounts.map(account => account.id) }
                ColumnLayout {
                    id: accountItem
                    required property string modelData
                    // The account under this id as the last read has it; null
                    // for the moment a removed one is still on its way out
                    // (the service's helpers take a null).
                    readonly property var account: groupSection.accounts.find(item => item.id === modelData) || null
                    readonly property bool busy: AccountsService.isBusy(accountItem.account)
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXxs

                    ListRow {
                        interactive: false
                        Layout.fillWidth: true
                        icon: AccountsService.icon(accountItem.account)
                        // The accent marks activity, not simply being online.
                        active: AccountsService.statusTone(accountItem.account) === "busy"
                        title: accountItem.account ? accountItem.account.name : ""
                        subtitle: AccountsService.subtitle(accountItem.account)
                        ShellText {
                            text: AccountsService.statusText(accountItem.account)
                            role: "small"
                            color: root.toneColor(AccountsService.statusTone(accountItem.account))
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
                            onClicked: AccountsService.sync(accountItem.account)
                        }
                        ShellButton {
                            focusOnTab: true
                            icon: Icons.settings
                            text: "Settings …"
                            compact: true
                            enabledState: !accountItem.busy
                            onClicked: AccountsService.configure(accountItem.account)
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
                            confirmText: "Remove?"
                            enabledState: !accountItem.busy
                            toolTip: "Takes the account out of KDE PIM; the account itself stays with its provider"
                            onClicked: {
                                AccountsService.confirmRemoveId = accountItem.modelData
                                AccountsService.remove(accountItem.account)
                            }
                        }
                    }
                }
            }
        }
    }
}
