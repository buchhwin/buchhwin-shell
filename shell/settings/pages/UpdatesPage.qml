import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/appearance/DateFormat.js" as DateFormat

// Settings > Updates: last check, "Check now", system packages (security
// updates first, the shell's own foundation tagged "Shell core") and Flatpaks
// as expandable lists, hand-off to Discover and a Flatpak update for the user
// installation; on Arch the news to read before the upgrade and the .pacnew
// files left after one; automatic check settings and what the shell says
// after an update.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

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
        // "session" or "shell" for a package the shell stands on
        // (UpdatesLogic.coreKind); a security badge says more and wins.
        property string core: ""
        readonly property bool badged: security || core.length > 0
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
            visible: row.badged
            implicitWidth: badgeText.implicitWidth + Metrics.spaceSm * 2
            implicitHeight: badgeText.implicitHeight + Metrics.spaceXxs * 2
            radius: Metrics.pillRadius(height)
            color: row.security ? Colors.warningSoft : Colors.accentSoft
            ShellText {
                id: badgeText
                anchors.centerIn: parent
                text: row.security ? row.badge : "Shell core"
                role: "caption"
                color: row.security ? Colors.warning : Colors.accentOnSoft
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Software updates"
        hint: DistroService.upgradesInTerminal
            ? "The shell only looks for updates. Installing system packages needs the administrator password and runs in a terminal window."
            : "The shell only looks for updates. Installing system packages needs the administrator password and runs in Discover."

        ListRow {
            interactive: false
            Layout.fillWidth: true
            // The check mark only for a check that found nothing: "Not
            // checked yet" beside it read as "up to date". Before any
            // answer the glyph is the one of the button beside it.
            icon: UpdatesService.checking ? Icons.refresh : UpdatesService.total > 0 ? "󰚰"
                : UpdatesService.result.packagesKnown || UpdatesService.result.flatpaksKnown ? Icons.check : Icons.refresh
            active: UpdatesService.total > 0
            title: UpdatesService.summary
            // No "Last checked: Never" under "Not checked yet".
            subtitle: UpdatesService.checking ? "Checking …"
                : UpdatesService.lastCheck ? "Last checked: " + UpdatesService.checkedText : ""
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
        // A development checkout says so in its row ("follows no remote");
        // what moves it forward instead of the button is said here.
        hint: "buchhwin-shell itself, from its checkout's git remote. Updating fast-forwards the checkout, re-runs the installer and restarts the shell."
            + (UpdatesService.shell.repo === "local" ? " Here scripts/deploy.sh moves the session forward instead." : "")

        ListRow {
            focusOnTab: true
            level: 1
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
                    // Not while the upgrade or the Flatpak update below runs
                    // in its terminal: the update restarts the shell.
                    enabledState: UpdatesService.actionsAllowed && UpdatesService.shellUpdatable && !UpdatesService.shellUpdating
                        && !UpdatesService.terminalBusy
                    toolTip: !UpdatesService.actionsAllowed ? "Only available in the buchhwin-shell session"
                        : UpdatesService.shell.dirty || UpdatesService.shell.ahead > 0 ? "Refused while the checkout has local changes or local commits"
                        : UpdatesService.terminalBusy && UpdatesService.shellUpdatable ? "Waits until the update in the terminal window has finished" : ""
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
            visible: UpdatesService.shell.repo === "ok" && (UpdatesService.shell.dirty || UpdatesService.shell.ahead > 0)
            text: "Updating is refused while the checkout has local changes or commits the remote does not have. Commit or stash them, or push them, and check again."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "System packages"
        hint: DistroService.packagesDescription

        // Arch: the news newer than the installed packages, above the
        // button that upgrades them - the ones that ask for a manual step
        // say so before the upgrade, not after it.
        ShellCard {
            Layout.fillWidth: true
            visible: UpdatesService.news.length > 0
            implicitHeight: newsColumn.implicitHeight + Metrics.spaceMd * 2
            ColumnLayout {
                id: newsColumn
                anchors.fill: parent
                anchors.margins: Metrics.spaceMd
                spacing: Metrics.spaceXs
                ShellText {
                    Layout.fillWidth: true
                    text: UpdatesService.news.length === 1 ? "An Arch news item to read before the upgrade"
                        : UpdatesService.news.length + " Arch news items to read before the upgrade"
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: UpdatesService.news
                    ColumnLayout {
                        id: newsItem
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        // The date as the shell writes dates (Settings > Desktop
                        // extras > Clock), not as the feed has it.
                        readonly property var day: /^\d{4}-\d{2}-\d{2}$/.test(String(modelData.date || ""))
                            ? new Date(Number(modelData.date.slice(0, 4)), Number(modelData.date.slice(5, 7)) - 1, Number(modelData.date.slice(8, 10)))
                            : null
                        ShellText {
                            Layout.fillWidth: true
                            text: (newsItem.day ? DateFormat.date(newsItem.day, SettingsService.locale, "short", SettingsService.dateOrder,
                                                                SettingsService.shortDateNumbers) : modelData.date) + " · " + modelData.title
                            role: "small"
                            wrapMode: Text.Wrap
                        }
                        ShellText { Layout.fillWidth: true; visible: text.length > 0; text: modelData.summary; role: "caption"; muted: true; wrapMode: Text.Wrap }
                    }
                }
                ShellButton {
                    focusOnTab: true
                    // It leaves the panel for the browser (not one more page).
                    trailingIcon: Icons.leavesPanel
                    text: "Read on archlinux.org"
                    compact: true
                    onClicked: UpdatesService.openNews()
                }
            }
        }

        ListRow {
            focusOnTab: true
            level: 1
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
                    text: !DistroService.upgradesInTerminal ? "Install in Discover"
                        : UpdatesService.upgrading ? "Upgrading …" : "Upgrade in terminal"
                    compact: true
                    variant: UpdatesService.packages.length ? "accent" : "surface"
                    // The terminal upgrade only runs in the session and once at
                    // a time, like "Update Flatpaks" and "Update the shell";
                    // Discover opens from anywhere.
                    enabledState: !DistroService.upgradesInTerminal
                        || UpdatesService.actionsAllowed && !UpdatesService.upgrading
                    toolTip: !DistroService.upgradesInTerminal || UpdatesService.actionsAllowed
                        ? "" : "Only available in the buchhwin-shell session"
                    onClicked: UpdatesService.installSystem()
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
                core: UpdatesService.coreKind(modelData)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: UpdatesService.coreNote
            role: "caption"
            wrapMode: Text.Wrap
        }

        // Arch: what earlier upgrades left beside the system's own
        // configuration. Merging is the user's, in a terminal.
        ShellCard {
            Layout.fillWidth: true
            visible: UpdatesService.pacnew.length > 0
            implicitHeight: pacnewColumn.implicitHeight + Metrics.spaceMd * 2
            ColumnLayout {
                id: pacnewColumn
                anchors.fill: parent
                anchors.margins: Metrics.spaceMd
                spacing: Metrics.spaceXs
                ShellText {
                    Layout.fillWidth: true
                    text: UpdatesService.pacnewNote
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: UpdatesService.pacnew
                    ShellText {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        role: "caption"
                        muted: true
                        font.family: Typography.monoFamily
                        elide: Text.ElideMiddle
                    }
                }
                ShellText {
                    Layout.fillWidth: true
                    text: UpdatesService.pacdiffCommand
                    font.family: Typography.monoFamily
                    wrapMode: Text.Wrap
                }
                ShellButton {
                    focusOnTab: true
                    icon: Icons.copy
                    text: "Copy command"
                    onClicked: Quickshell.clipboardText = UpdatesService.pacdiffCommand
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Flatpaks"
        // "Update Flatpaks" named only while the button is there: it shows
        // when the user installation has updates.
        hint: "Apps and runtimes of the system and your user installation. "
            + (UpdatesService.userFlatpakCount > 0
                ? "Update Flatpaks runs flatpak update for your user installation in a terminal window; system Flatpaks update in Discover."
                : "System Flatpaks update in Discover.")

        ListRow {
            focusOnTab: true
            level: 1
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
                icon: modelData.kind === "runtime" ? "󰏖" : Icons.apps
                title: modelData.name
                subtitle: UpdatesService.flatpakSubtitle(modelData)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Automatic check"
        scope: "updates"
        hint: "Looks for updates in the background and installs nothing, unless the shell's own updates are handed to it below."
            + (UpdatesService.realSession ? ""
                : " Only in the buchhwin-shell session: a test session checks from the cached package data.")

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
    }

    // What the first start after an update says (scripts/updates-after-start.py,
    // which start-shell.sh runs beside the shell and which reads both settings
    // from settings.json when the shell starts).
    SettingsSection {
        Layout.fillWidth: true
        title: "After an update"
        scope: "updates.coreCheck"
        hint: "The first start after Quickshell or Hyprland changed watches the shell's log and IPC targets for a minute."

        SettingRow {
            // One line in the label column: the wrapped label put the
            // hint's dot right over its second word.
            label: "After a core update"
            hint: "Problems tells only when the minute found some; Always also says that the shell started cleanly"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: UpdatesService.coreCheck
                options: [{ value: "off", label: "Off" }, { value: "problems", label: "Problems" }, { value: "always", label: "Always" }]
                onSelected: value => SettingsService.set("updates.coreCheck", value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Name the shell's changes"
            hint: "One quiet notification with up to ten commit subjects when the shell starts from a newer checkout, with a button to About"
            ShellToggle {
                focusOnTab: true
                checked: UpdatesService.whatsNew
                onToggled: value => SettingsService.set("updates.whatsNew", value)
            }
        }
    }
}
