import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Updates: last check, "Check now", system packages (security
// updates first) and Flatpaks as expandable lists, hand-off to Discover and a
// Flatpak update for the user installation, automatic check settings.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    // Keeps the "last checked" text ticking while the page is open.
    PageActivity {
        onOpened: UpdatesService.track()
        onClosed: UpdatesService.untrack()
    }

    component UpdateRow: RowLayout {
        id: row
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property bool security: false
        property string badge: ""
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.spaceMd
        Layout.rightMargin: Metrics.spaceMd
        spacing: Metrics.spaceMd

        ShellIcon {
            Layout.preferredWidth: Metrics.iconLg
            glyph: row.security ? "󰒃" : row.icon
            size: Metrics.iconSm
            color: row.security ? Colors.warning : Colors.mutedText
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ShellText { Layout.fillWidth: true; text: row.title }
            ShellText { Layout.fillWidth: true; text: row.subtitle; role: "small"; muted: true; visible: text.length > 0 }
        }
        Rectangle {
            visible: row.security
            implicitWidth: badgeText.implicitWidth + Metrics.spaceSm * 2
            implicitHeight: badgeText.implicitHeight + Metrics.spaceXxs * 2
            radius: Metrics.pillRadius(height)
            color: Colors.warningSoft
            ShellText {
                id: badgeText
                anchors.centerIn: parent
                text: row.badge
                role: "caption"
                color: Colors.warning
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Software updates"
        description: "The shell only looks for updates. Installing system packages needs the administrator password and runs in Discover."

        ListRow {
            Layout.fillWidth: true
            icon: UpdatesService.checking ? Icons.refresh : UpdatesService.total > 0 ? "󰚰" : Icons.check
            active: UpdatesService.total > 0
            title: UpdatesService.summary
            subtitle: UpdatesService.checking ? "Checking …" : "Last checked: " + UpdatesService.checkedText
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: UpdatesService.checking ? "Checking …" : "Check now"
                compact: true
                enabledState: !UpdatesService.checking
                onClicked: UpdatesService.check(false)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: UpdatesService.message.length > 0
            text: UpdatesService.message
            role: "caption"
            color: UpdatesService.messageError ? Colors.warning : Colors.mutedText
            wrapMode: Text.Wrap
        }
        ShellText {
            Layout.fillWidth: true
            visible: UpdatesService.preview
            text: "Preview data from the test fixtures."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "The shell"
        description: "buchhwin-shell itself, from the git remote its checkout follows. Updating fast-forwards the checkout, re-runs the installer and restarts the shell - open panels close for a moment."

        ListRow {
            focusOnTab: true
            Layout.fillWidth: true
            icon: "󰊢"
            active: UpdatesService.shellUpdatable
            title: UpdatesService.shellChecking ? "Checking …" : UpdatesService.shellSummary
            subtitle: UpdatesService.shellSubtitle
            onClicked: if (UpdatesService.shell.commits.length) UpdatesService.shellExpanded = !UpdatesService.shellExpanded
            Row {
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    anchors.verticalCenter: parent.verticalCenter
                    visible: UpdatesService.shell.repo === "ok"
                    icon: "󰚰"
                    text: UpdatesService.shellUpdating ? "Updating …" : "Update the shell"
                    compact: true
                    variant: UpdatesService.shellUpdatable ? "accent" : "surface"
                    enabledState: UpdatesService.actionsAllowed && UpdatesService.shellUpdatable && !UpdatesService.shellUpdating
                    toolTip: !UpdatesService.actionsAllowed ? "Only available in the buchhwin-shell session"
                        : UpdatesService.shell.dirty || UpdatesService.shell.ahead > 0 ? "Refused while the checkout has local changes or local commits" : ""
                    onClicked: UpdatesService.updateShell()
                }
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: UpdatesService.shell.commits.length > 0
                    glyph: UpdatesService.shellExpanded ? Icons.collapse : Icons.forward
                    size: Metrics.iconXs
                    color: Colors.mutedText
                }
            }
        }
        Repeater {
            model: UpdatesService.shellExpanded ? UpdatesService.shell.commits : []
            UpdateRow {
                required property var modelData
                icon: "󰜘"
                title: modelData.subject
                subtitle: modelData.hash
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: UpdatesService.shell.repo === "local"
            text: "This checkout follows no remote: it is the development machine, where scripts/deploy.sh moves the session forward."
            role: "caption"
            wrapMode: Text.Wrap
        }
        ShellText {
            Layout.fillWidth: true
            visible: UpdatesService.shell.repo === "ok" && (UpdatesService.shell.dirty || UpdatesService.shell.ahead > 0)
            text: "Updating is refused while the checkout has local changes or commits the remote does not have - nothing of yours is ever merged over. Commit or stash them, or push them, and check again."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "System packages"
        description: "Fedora packages from dnf. Discover asks for the administrator password before installing."

        ListRow {
            focusOnTab: true
            Layout.fillWidth: true
            icon: "󰏗"
            active: UpdatesService.packages.length > 0
            title: !UpdatesService.result.packagesKnown ? "Not checked yet"
                : UpdatesService.packages.length ? UpdatesService.packages.length + (UpdatesService.packages.length === 1 ? " package" : " packages")
                : "No package updates"
            subtitle: UpdatesService.securityCount > 0
                ? UpdatesService.securityCount + (UpdatesService.securityCount === 1 ? " security update" : " security updates")
                : UpdatesService.result.packagesCached ? "Cached data" : ""
            onClicked: if (UpdatesService.packages.length) UpdatesService.packagesExpanded = !UpdatesService.packagesExpanded
            Row {
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰏔"
                    text: "Install in Discover"
                    compact: true
                    variant: UpdatesService.packages.length ? "accent" : "surface"
                    onClicked: UpdatesService.openDiscover()
                }
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: UpdatesService.packages.length > 0
                    glyph: UpdatesService.packagesExpanded ? Icons.collapse : Icons.forward
                    size: Metrics.iconXs
                    color: Colors.mutedText
                }
            }
        }
        Repeater {
            model: UpdatesService.packagesExpanded ? UpdatesService.packages : []
            UpdateRow {
                required property var modelData
                icon: "󰏗"
                title: modelData.name
                subtitle: UpdatesService.packageSubtitle(modelData)
                security: modelData.security
                badge: UpdatesService.severityLabel(modelData)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Flatpaks"
        description: "Apps and runtimes of the system and your user installation."

        ListRow {
            focusOnTab: true
            Layout.fillWidth: true
            icon: "󰏖"
            active: UpdatesService.flatpaks.length > 0
            title: !UpdatesService.result.flatpaksKnown ? "Not checked yet"
                : UpdatesService.flatpaks.length ? UpdatesService.flatpaks.length + (UpdatesService.flatpaks.length === 1 ? " Flatpak" : " Flatpaks")
                : "No Flatpak updates"
            subtitle: UpdatesService.flatpaks.length ? UpdatesService.flatpakInstallations
                : UpdatesService.result.flatpaksCached ? "Cached data" : ""
            onClicked: if (UpdatesService.flatpaks.length) UpdatesService.flatpaksExpanded = !UpdatesService.flatpaksExpanded
            Row {
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    anchors.verticalCenter: parent.verticalCenter
                    visible: UpdatesService.userFlatpakCount > 0
                    icon: "󰆍"
                    text: UpdatesService.flatpakUpdating ? "Updating …" : "Update Flatpaks"
                    compact: true
                    enabledState: UpdatesService.actionsAllowed && !UpdatesService.flatpakUpdating
                    toolTip: UpdatesService.actionsAllowed ? "" : "Only available in the buchhwin-shell session"
                    onClicked: UpdatesService.updateFlatpaks()
                }
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: UpdatesService.flatpaks.length > 0
                    glyph: UpdatesService.flatpaksExpanded ? Icons.collapse : Icons.forward
                    size: Metrics.iconXs
                    color: Colors.mutedText
                }
            }
        }
        Repeater {
            model: UpdatesService.flatpaksExpanded ? UpdatesService.flatpaks : []
            UpdateRow {
                required property var modelData
                icon: modelData.kind === "runtime" ? "󰏖" : "󰀻"
                title: modelData.name
                subtitle: UpdatesService.flatpakSubtitle(modelData)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: UpdatesService.flatpaks.length > 0
            text: UpdatesService.userFlatpakCount > 0
                ? "Update Flatpaks runs flatpak update for your user installation in a terminal window. System Flatpaks update in Discover."
                : "System Flatpaks update in Discover."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Automatic check"
        description: "Looks for updates in the background and installs nothing - unless the shell's own updates are handed to it below."

        SettingRow {
            label: "Check"
            hint: "At most this often"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(UpdatesService.checkHours)
                options: [{ value: "0", label: "Off" }, { value: "6", label: "6 h" }, { value: "12", label: "12 h" }, { value: "24", label: "24 h" }]
                onSelected: value => SettingsService.set("updates.checkHours", parseInt(value))
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Notify about new updates"
            hint: "Once per new set of updates, with a button to open this page"
            ShellToggle {
                focusOnTab: true
                checked: UpdatesService.notifyEnabled
                enabledState: UpdatesService.checkHours > 0
                onToggled: value => SettingsService.set("updates.notify", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Install shell updates automatically"
            hint: "When a check finds the checkout behind its remote and clean, it is fast-forwarded and the shell restarts itself. System packages and Flatpaks are never touched."
            ShellToggle {
                focusOnTab: true
                checked: UpdatesService.shellAuto
                enabledState: UpdatesService.checkHours > 0
                onToggled: value => SettingsService.set("updates.shellAuto", value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: !UpdatesService.realSession
            text: "Automatic checks and notifications only run in the buchhwin-shell session. Test sessions check from the cached package data."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }
}
