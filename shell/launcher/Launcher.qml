import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Super+D launcher with apps, commands (>), files (/), settings (@) and a
// calculator (=). One header row holds the search and the mode switch; app
// categories sit in a sidebar. Keyboard: arrows, PageUp/PageDown, Home/End,
// Tab switches mode, Ctrl+Up/Down switches category, Enter runs, Ctrl+Enter
// alternate action, Esc clears then closes.
ShellPanel {
    id: root
    keyForward: search
    panelId: "launcher"
    placement: "center"
    cardWidth: Metrics.launcherWidth
    cardHeight: Metrics.launcherHeight
    scrimColor: Colors.scrim

    property string query: ""
    property string category: "All"
    property int selectedIndex: 0
    readonly property var mode: LauncherService.modeFor(query)
    // Only evaluated while the launcher is visible.
    readonly property var results: shown ? LauncherService.results(query, category) : []

    onWantedChanged: {
        if (wanted) {
            search.text = ""
            category = "All"
            selectedIndex = 0
        }
    }
    onResultsChanged: selectedIndex = Math.min(selectedIndex, Math.max(0, results.length - 1))

    function run(alternate) {
        const entry = results[selectedIndex]
        if (!entry) return
        PanelService.close("launcher")
        if (alternate && entry.alternate) entry.alternate()
        else entry.run()
    }

    function move(delta) {
        if (!results.length) return
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta))
    }

    function cycleCategory(step) {
        const list = LauncherService.availableCategories
        const index = Math.max(0, list.findIndex(item => item.name === category))
        category = list[(index + step + list.length) % list.length].name
        selectedIndex = 0
    }

    function setMode(prefix) {
        const rest = mode.prefix.length ? query.slice(1) : query
        search.text = prefix + rest
        search.focusInput()
    }

    function cycleMode(step) {
        const modes = LauncherService.modes
        const index = modes.indexOf(mode)
        const next = modes[(index + step + modes.length) % modes.length]
        const rest = mode.prefix.length ? query.slice(1) : query
        search.text = next.prefix + rest
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.spaceMd

        // The search field and the mode switch are two controls, not one: the
        // switch used to sit inside the field, so the focus ring drew a box
        // around both and the field stopped looking like a field.
        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceMd

            ShellTextField {
                id: search
                Layout.fillWidth: true
                large: true
                icon: root.mode.id === "apps" ? Icons.search : root.mode.icon
                placeholder: root.mode.id === "apps" ? "Search …" : root.mode.label + " …"
                onTextChanged: { root.query = text; root.selectedIndex = 0 }
                onKeyPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                    event.accepted = true
                    if (event.key === Qt.Key_Down && ctrl) root.cycleCategory(1)
                    else if (event.key === Qt.Key_Up && ctrl) root.cycleCategory(-1)
                    else if (event.key === Qt.Key_Down) root.move(1)
                    else if (event.key === Qt.Key_Up) root.move(-1)
                    else if (event.key === Qt.Key_PageDown) root.move(8)
                    else if (event.key === Qt.Key_PageUp) root.move(-8)
                    else if (event.key === Qt.Key_Home && ctrl) root.selectedIndex = 0
                    else if (event.key === Qt.Key_End && ctrl) root.selectedIndex = Math.max(0, root.results.length - 1)
                    else if (event.key === Qt.Key_Tab) root.cycleMode(1)
                    else if (event.key === Qt.Key_Backtab) root.cycleMode(-1)
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.run(ctrl)
                    else event.accepted = false
                }
            }

            SegmentedControl {
                id: modeSwitch
                Layout.alignment: Qt.AlignVCenter
                compact: true
                current: root.mode.id
                options: LauncherService.modes.map(item => ({ value: item.id, label: item.label, icon: item.icon }))
                onSelected: value => root.setMode(LauncherService.modes.find(item => item.id === value).prefix)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Metrics.spaceMd

            // The categories and the results sit on the same card surface the
            // settings sections use, so the launcher reads like the rest of
            // the shell instead of loose rows on the panel.
            Rectangle {
                visible: root.mode.id === "apps"
                Layout.preferredWidth: Metrics.launcherSidebarWidth
                Layout.fillHeight: true
                radius: Metrics.radiusCard
                color: Colors.surface1
                border.width: Metrics.borderWidth
                border.color: Colors.border

            Flickable {
                id: categoryFlick
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                contentHeight: categoryColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: categoryColumn
                    width: categoryFlick.width
                    spacing: Metrics.spaceXxs
                    Repeater {
                        model: LauncherService.availableCategories
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            compact: true
                            level: 1
                            icon: modelData.icon
                            title: modelData.name
                            trailingText: String(modelData.count)
                            selected: root.category === modelData.name
                            onClicked: { root.category = modelData.name; root.selectedIndex = 0; search.focusInput() }
                        }
                    }
                }
            }

            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Metrics.radiusCard
                color: Colors.surface1
                border.width: Metrics.borderWidth
                border.color: Colors.border

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                clip: true
                spacing: Metrics.spaceXxs
                model: root.results
                currentIndex: root.selectedIndex
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                boundsBehavior: Flickable.StopAtBounds

                delegate: ListRow {
                    required property var modelData
                    required property int index
                    level: 1
                    width: list.width
                    implicitHeight: modelData.kind === "calculator" ? Metrics.rowHeight + Metrics.spaceLg : Metrics.rowHeight + Metrics.spaceXs
                    selected: index === root.selectedIndex
                    icon: modelData.icon || ""
                    iconSource: modelData.iconSource || ""
                    title: modelData.title
                    subtitle: modelData.subtitle || ""
                    trailingText: index === root.selectedIndex ? "↵" : ""
                    onClicked: { root.selectedIndex = index; root.run(false) }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    icon: root.mode.id === "files" && LauncherService.fileSearchRunning ? Icons.busy : root.mode.icon
                    title: root.mode.id === "files" ? (root.query.length < 3 ? "Type a file name" : LauncherService.fileSearchRunning ? "Searching …" : "No files found")
                        : root.mode.id === "calculator" ? "Type an expression, e.g. = 12 * (3 + 4)"
                        : "No results"
                }
            }
            }
        }
    }
}
