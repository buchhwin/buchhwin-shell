import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/updates/UpdatesLogic.js" as Updates
import "../../../services/settings/LoginLogic.js" as LoginLogic

ColumnLayout {
    id: root
    spacing: Metrics.pageGap
    // Read once per session and kept by the service: the page is built
    // again on every visit, the versions and the hardware are not.
    readonly property var info: SystemInfoService.info
    Component.onCompleted: SystemInfoService.load()

    // The shell's own version and its newest changes: one `git log` of the
    // checkout it runs from, each time the page is shown (a deploy moves it
    // under a page kept open). Health runs its checks at most once a minute.
    property var commits: []
    readonly property string version: Updates.versionLine(commits, Date.now())
    PageActivity {
        onOpened: {
            if (!logProc.running) logProc.running = true
            HealthService.check(false)
        }
    }
    Process {
        id: logProc
        command: Updates.logCommand(Paths.shellFile("").replace(/\/$/, ""))
        stdout: StdioCollector { onStreamFinished: root.commits = Updates.parseLog(text) }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "buchhwin-shell"
        hint: "A desktop shell on Hyprland and Quickshell, for Fedora, openSUSE Leap and Arch Linux."

        SettingRow {
            Layout.fillWidth: true
            visible: root.version.length > 0
            label: "Version"
            ShellText { Layout.fillWidth: true; text: root.version; muted: true; wrapMode: Text.Wrap }
        }

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Show the tour again"
            hint: "The six keys this desktop is built on"
            // The chevron after the word, where it reads as going on.
            ShellButton {
                trailingIcon: Icons.forward
                text: "Start"
                variant: "surface"
                compact: true
                focusOnTab: true
                onClicked: PanelService.open("welcome")
            }
        }

        Repeater {
            model: [
                { key: "os", label: "System" }, { key: "hyprland", label: "Hyprland" }, { key: "quickshell", label: "Quickshell" },
                { key: "kernel", label: "Kernel" }, { key: "cpu", label: "Processor" }, { key: "gpu", label: "Graphics" },
                { key: "ram", label: "Memory" }, { key: "host", label: "Device name" }, { key: "session", label: "Session" }
            ]
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                label: modelData.label
                ShellText { Layout.fillWidth: true; text: root.info[modelData.key] || " …"; muted: true; wrapMode: Text.Wrap }
            }
        }
    }

    // What the session still needs (HealthService): the read-only checks of
    // session-check.sh and doctor.sh, and the shell's own, each with its fix.
    SettingsSection {
        Layout.fillWidth: true
        title: "Health"
        hint: "What this session and its packages still need. Steps with sudo are yours to run in a terminal; nothing here changes the system."

        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: HealthService.running ? Icons.busy : HealthService.healthy ? Icons.check : Icons.warning
            active: HealthService.healthy
            title: HealthService.summary
            subtitle: HealthService.running && HealthService.lastRun > 0 ? "Checking again …" : ""
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: HealthService.running ? "Checking …" : "Check again"
                compact: true
                enabledState: !HealthService.running
                onClicked: HealthService.check(true)
            }
        }

        // Keyed by the finding's id (pitfall 76): a run again keeps the rows
        // that are still there.
        Repeater {
            model: ScriptModel { values: HealthService.items.map(item => item.id) }
            ColumnLayout {
                id: findingItem
                required property string modelData
                readonly property var finding: HealthService.items.find(item => item.id === modelData) || null
                Layout.fillWidth: true
                spacing: Metrics.spaceXxs

                // The row of a finding: its glyph in the level's own ink (an
                // error and a warning shared one muted triangle), the text over
                // up to three lines (one elided line lost the reason), the
                // level and where it is under it, and its button.
                readonly property string level: finding ? finding.level : "note"
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Metrics.spaceLg
                    Layout.rightMargin: Metrics.spaceLg
                    Layout.topMargin: Metrics.spaceXs
                    spacing: Metrics.spaceMd
                    ShellIcon {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Metrics.iconLg
                        glyph: findingItem.level === "note" ? Icons.info : Icons.warning
                        size: Metrics.iconMd
                        color: findingItem.level === "error" ? Colors.danger : findingItem.level === "warn" ? Colors.warning : Colors.mutedText
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ShellText {
                            Layout.fillWidth: true
                            text: findingItem.finding ? findingItem.finding.text : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        ShellText {
                            Layout.fillWidth: true
                            text: findingItem.finding
                                ? HealthService.levelLabel(findingItem.level) + (findingItem.finding.section.length ? " · " + findingItem.finding.section : "")
                                : ""
                            role: "small"
                            muted: true
                            elide: Text.ElideRight
                        }
                    }
                    ShellButton {
                        Layout.alignment: Qt.AlignTop
                        focusOnTab: true
                        visible: !!findingItem.finding && findingItem.finding.action.length > 0
                        text: findingItem.finding ? HealthService.actionLabel(findingItem.finding.action) : ""
                        compact: true
                        onClicked: if (findingItem.finding) HealthService.act(findingItem.finding.action)
                    }
                }
                // The command is what the finding is for: in the text's ink and
                // under the text, breaking at a path's folders as the Login
                // screen's does (LoginLogic.shown), the copy button at its top.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Metrics.spaceLg + Metrics.iconLg + Metrics.spaceMd
                    Layout.rightMargin: Metrics.spaceLg
                    Layout.bottomMargin: Metrics.spaceXs
                    visible: !!findingItem.finding && findingItem.finding.command.length > 0
                    spacing: Metrics.spaceSm
                    ShellText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: findingItem.finding ? LoginLogic.shown(findingItem.finding.command) : ""
                        role: "small"
                        font.family: Typography.monoFamily
                        wrapMode: Text.Wrap
                    }
                    ShellButton {
                        Layout.alignment: Qt.AlignTop
                        focusOnTab: true
                        icon: Icons.copy
                        compact: true
                        variant: "ghost"
                        toolTip: "Copy command"
                        onClicked: if (findingItem.finding) Quickshell.clipboardText = findingItem.finding.command
                    }
                }
            }
        }
    }

    // The newest commits of the checkout the shell runs from - their subjects
    // are written as sentences about what changed.
    SettingsSection {
        Layout.fillWidth: true
        visible: root.commits.length > 0
        title: "Recent changes"
        hint: "The newest changes of the checkout this shell runs from."

        Repeater {
            model: ScriptModel { values: root.commits.map(commit => commit.hash) }
            ListRow {
                id: commitRow
                required property string modelData
                readonly property var commit: root.commits.find(item => item.hash === modelData) || null
                Layout.fillWidth: true
                interactive: false
                icon: "󰜘"
                title: commitRow.commit ? commitRow.commit.subject : ""
                subtitle: commitRow.commit ? commitRow.commit.hash + " · " + Updates.shortDate(commitRow.commit.date, Date.now()) : ""
            }
        }
    }
}
