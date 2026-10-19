import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/sessionapps/PlacementLogic.js" as Placement

// Settings > Apps: where each app opens, the work apps started together, and
// the apps of the last session offered again at the next login
// (services/SessionAppsService.qml).
ColumnLayout {
    id: page
    spacing: Metrics.pageGap

    // The apps of the menus, for the pickers (LauncherService's copy of the
    // desktop entries, read while the page is there).
    readonly property var appOptions: LauncherService.visibleApps()
        .map(app => ({ value: app.id, label: app.name || app.id }))
        .sort((a, b) => a.label.localeCompare(b.label))
    readonly property var workOptions: appOptions.filter(option => SessionAppsService.workApps.indexOf(option.value) < 0)

    // The placement being put together under the list.
    property string placeApp: ""
    property string placeScreen: ""
    property string placeWorkspace: "0"
    property bool placeFloat: false
    property string workAdd: ""
    readonly property bool placeHasScreen: placeScreen.length > 0
    // A screen chosen and gone (unplugged while the page was open) is no
    // choice any more.
    readonly property var screenOptions: [{ value: "", label: "Any screen" }].concat(SessionAppsService.monitors
        .map(monitor => ({ value: monitor.name, label: Placement.screenLabel(monitor) })))
    readonly property var workspaceOptions: [{ value: "0", label: "The one it shows" }]
        .concat([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(number => ({ value: String(number), label: String(number) })))
    readonly property bool placeReady: placeApp.length > 0 && (placeHasScreen || placeFloat)
        && (!placeHasScreen || screenOptions.some(option => option.value === placeScreen))

    // The last session's apps are read for this page only while it is shown.
    PageActivity { onOpened: SessionAppsService.stateAsked = true }

    SettingsSection {
        Layout.fillWidth: true
        title: "Open on"
        // Without workspaces per screen a number is the same workspace
        // wherever it is shown, and the app goes where that one is.
        description: "An app opens on the screen and workspace you give it, or floating. "
            + (HyprlandService.perMonitor ? "Workspaces are counted on each screen, as Super+1 to Super+9 count them."
                                          : "Workspaces are numbered across all screens, as Super+1 to Super+9 number them, and an app goes to its workspace on whichever screen that is.")
            + " While its screen is not connected, an app opens where you are."

        // Keyed by the apps' ids, strings (pitfall 76).
        Repeater {
            model: ScriptModel { values: SessionAppsService.rules.map(rule => rule.app) }
            ListRow {
                required property string modelData
                readonly property var rule: SessionAppsService.ruleFor(modelData)
                readonly property var entry: DesktopEntries.byId(modelData)
                Layout.fillWidth: true
                interactive: false
                iconSource: entry ? LauncherService.iconSource(entry.icon) : ""
                icon: entry ? "" : Icons.window
                title: entry ? (entry.name || modelData) : modelData
                subtitle: rule ? SessionAppsService.ruleText(rule) + (entry ? "" : " · not installed") : ""
                ShellButton {
                    focusOnTab: true
                    icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove"
                    confirm: true; confirmText: "Remove?"
                    onClicked: SessionAppsService.unplace(modelData)
                }
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: SessionAppsService.rules.length === 0
            row: true
            icon: Icons.window
            title: "No app has a place of its own yet"
            description: "Choose one below, or \u201cAlways open here\u201d in an app's dock menu"
        }

        SettingRow {
            Layout.fillWidth: true
            label: "App"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: page.appOptions
                current: page.placeApp
                placeholder: "Choose an app …"
                filterable: true
                onSelected: value => {
                    page.placeApp = value
                    // An app with a place already starts from it.
                    const rule = SessionAppsService.ruleFor(value)
                    const monitor = rule ? Placement.monitorFor(rule, SessionAppsService.monitors) : null
                    page.placeScreen = monitor ? monitor.name : ""
                    page.placeWorkspace = rule && monitor ? String(rule.workspace) : "0"
                    page.placeFloat = rule ? rule.float : false
                }
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Screen"
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                options: page.screenOptions
                current: page.placeScreen
                onSelected: value => {
                    page.placeScreen = value
                    if (!value.length) page.placeWorkspace = "0"
                }
            }
        }
        SettingRow {
            Layout.fillWidth: true
            label: "Workspace"
            hint: HyprlandService.perMonitor ? "One of the screen's own ten, or the one it shows when the app starts."
                                             : "One of the ten, or the one the screen shows when the app starts."
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                enabledState: page.placeHasScreen
                options: page.workspaceOptions
                current: page.placeHasScreen ? page.placeWorkspace : "0"
                onSelected: value => page.placeWorkspace = value
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Floating"
            ShellToggle {
                focusOnTab: true
                checked: page.placeFloat
                onToggled: value => page.placeFloat = value
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellText {
                Layout.fillWidth: true
                // The conf dialect takes a rule's screen and workspace back,
                // not its floating: a floating place removed or changed this
                // session still floats its app until the next reload of
                // Hyprland's configuration.
                visible: SessionAppsService.staleRules > 0
                text: "An app whose floating place you removed or changed floats until Hyprland reloads its configuration."
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            // Why Add waits: an app chosen, but neither a screen nor
            // Floating yet - "Any screen" is no place of its own.
            ShellText {
                Layout.fillWidth: true
                visible: SessionAppsService.staleRules === 0 && page.placeApp.length > 0 && !page.placeReady
                text: "Choose a screen, or Floating"
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            Item { Layout.fillWidth: SessionAppsService.staleRules === 0 && !(page.placeApp.length > 0 && !page.placeReady) }
            ShellButton {
                focusOnTab: true
                Layout.alignment: Qt.AlignTop
                icon: Icons.add
                text: SessionAppsService.ruleFor(page.placeApp) ? "Replace" : "Add"
                enabledState: page.placeReady
                onClicked: {
                    if (SessionAppsService.placeApp(page.placeApp, page.placeScreen, Number(page.placeWorkspace), page.placeFloat))
                        page.placeApp = ""
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Work apps"
        scope: "autostart.workAtLogin"
        description: "Started together, in this order, by Super+Alt+W or the launcher's Start my work apps. An app that is running already is left as it is, and each opens where Open on puts it."

        Repeater {
            model: ScriptModel { values: SessionAppsService.workApps }
            ListRow {
                required property string modelData
                readonly property var entry: DesktopEntries.byId(modelData)
                Layout.fillWidth: true
                interactive: false
                iconSource: entry ? LauncherService.iconSource(entry.icon) : ""
                icon: entry ? "" : Icons.apps
                title: entry ? (entry.name || modelData) : modelData
                subtitle: entry ? (entry.genericName || entry.comment || "") : "No longer installed"
                ShellButton {
                    focusOnTab: true
                    icon: Icons.remove; variant: "ghost"; compact: true; toolTip: "Remove"
                    confirm: true; confirmText: "Remove?"
                    onClicked: SessionAppsService.removeWorkApp(modelData)
                }
            }
        }
        EmptyState {
            Layout.fillWidth: true
            visible: SessionAppsService.workApps.length === 0
            row: true
            icon: Icons.apps
            title: "No work apps yet"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ShellSelect {
                focusOnTab: true
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                options: page.workOptions
                current: page.workAdd
                placeholder: "Choose an app …"
                filterable: true
                onSelected: value => page.workAdd = value
            }
            ShellButton {
                focusOnTab: true
                Layout.alignment: Qt.AlignTop
                icon: Icons.add; text: "Add"
                enabledState: page.workAdd.length > 0
                onClicked: { SessionAppsService.addWorkApp(page.workAdd); page.workAdd = "" }
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Start at login"
            hint: "Once the wallet is open, so a browser among them never starts against a locked one."
            ShellToggle {
                focusOnTab: true
                checked: SessionAppsService.workAtLogin
                onToggled: value => SettingsService.set("autostart.workAtLogin", value)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ShellButton {
                focusOnTab: true
                icon: Icons.play; text: "Start now"
                enabledState: SessionAppsService.workApps.length > 0 && !SessionAppsService.launching
                onClicked: { PanelService.close(); SessionAppsService.startWork() }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Reopen after login"
        scope: "autostart.reopen"
        description: "When you log out, restart or shut down from the shell, it keeps which apps were open and where: the apps and their places, never a window's title, in a file only you can read. At the next login a notification offers to reopen them; nothing starts by itself. Browsers and VS Code bring back their own windows, so they are started once and their windows put back; a Citrix session is put back when Citrix reconnects it."

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Offer to reopen apps"
            ShellToggle {
                focusOnTab: true
                checked: SessionAppsService.reopenOffer
                onToggled: value => SettingsService.set("autostart.reopen", value)
            }
        }
        ListRow {
            Layout.fillWidth: true
            interactive: false
            icon: Icons.window
            title: !SessionAppsService.savedLoaded ? "Reading …"
                : SessionAppsService.savedApps === 1 ? "1 app kept from the last session"
                : SessionAppsService.savedApps > 1 ? SessionAppsService.savedApps + " apps kept from the last session"
                : "No session kept"
            subtitle: SessionAppsService.savedLoaded && SessionAppsService.savedApps > 0 && SessionAppsService.saved.offered
                ? "Offered at a login already" : ""
            ShellButton {
                focusOnTab: true
                compact: true
                icon: Icons.window; text: "Reopen now"
                enabledState: SessionAppsService.savedApps > 0 && !SessionAppsService.placing
                onClicked: { PanelService.close(); SessionAppsService.reopen() }
            }
            ShellButton {
                focusOnTab: true
                compact: true
                icon: Icons.remove; variant: "ghost"; toolTip: "Forget them"
                confirm: true; confirmText: "Forget?"
                enabledState: SessionAppsService.savedApps > 0
                onClicked: SessionAppsService.forget()
            }
        }
    }
}
