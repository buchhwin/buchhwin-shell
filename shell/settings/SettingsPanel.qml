import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "pages"
import "../../services/settings/SettingsNavLogic.js" as Nav

// Settings app (Super+I): sidebar with search, content pages on the right.
ShellPanel {
    id: root
    keyForward: searchInput
    panelId: "settings"
    placement: "center"
    cardWidth: Metrics.settingsWidth
    cardHeight: Metrics.settingsHeight
    scrimColor: Colors.scrim
    // Dragged by the strip along the top of the card - the "Settings" title on
    // the left and the page title on the right, neither of which is a control.
    // A double click on it puts the window back in the middle.
    movable: true
    savedMoveX: SettingsService.value("desktop.settingsMoveX")
    savedMoveY: SettingsService.value("desktop.settingsMoveY")
    onMoved: (x, y) => SettingsService.setAll({ "desktop.settingsMoveX": Math.round(x),
                                                "desktop.settingsMoveY": Math.round(y) })
    property string page: "appearance"
    property string search: ""
    // Once a page has been shown it stays: see the page Loader below.
    property bool pageKept: false
    onShownChanged: if (shown) pageKept = true
    // Sidebar rows (group headings and pages) filtered by the search.
    readonly property var rows: Nav.rows(search)
    readonly property var visiblePageIds: Nav.pageIds(rows)
    readonly property var current: Nav.pageById(page) || Nav.PAGES[0]

    onWantedChanged: if (wanted) {
        page = PanelService.args.page || page
        Qt.callLater(revealPage)
    }
    onPageChanged: {
        contentFlick.contentY = 0
        Qt.callLater(revealPage)
    }

    // The first page the search leaves visible becomes the page.
    function selectFirstMatch() {
        selectTimer.stop()
        if (visiblePageIds.length) page = visiblePageIds[0]
    }
    // A selection the timer has not made yet, made now.
    function settleSearch() {
        if (selectTimer.running) selectFirstMatch()
    }

    // Scroll the sidebar so the selected page row is visible.
    function revealPage() {
        const index = rows.findIndex(item => item.kind === "page" && item.id === page)
        const row = index >= 0 ? sidebarRepeater.itemAt(index) : null
        // Before the panel is laid out the list has no height yet.
        if (!row || sidebarFlick.height <= 0) return
        const maxY = Math.max(0, sidebarFlick.contentHeight - sidebarFlick.height)
        // The first page of a group brings its heading into view too.
        const heading = index > 0 && rows[index - 1].kind === "heading" ? sidebarRepeater.itemAt(index - 1) : null
        const top = heading ? heading.y : row.y
        if (top < sidebarFlick.contentY) sidebarFlick.contentY = top
        else if (row.y + row.height > sidebarFlick.contentY + sidebarFlick.height)
            sidebarFlick.contentY = Math.min(maxY, row.y + row.height - sidebarFlick.height)
    }
    Connections {
        target: PanelService
        function onArgsChanged() { if (root.wanted && PanelService.args.page) root.page = PanelService.args.page }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Metrics.spaceXl

        ColumnLayout {
            Layout.preferredWidth: Metrics.settingsSidebarWidth
            Layout.maximumWidth: Metrics.settingsSidebarWidth
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Metrics.spaceSm

            RowLayout {
                spacing: Metrics.spaceSm
                Layout.bottomMargin: Metrics.spaceXs
                ShellIcon { glyph: Icons.settings; size: Metrics.iconMd; color: Colors.accentForeground }
                ShellText { text: "Settings"; role: "title" }
            }

            ShellTextField {
                id: searchInput
                Layout.fillWidth: true
                icon: Icons.search
                placeholder: "Search settings …"
                // The list filters on every keystroke; the page follows after
                // a pause. Selecting on each character replaced the page each
                // time, and a page is destroyed and built again when it is
                // replaced - its radios flickered and its scans (Bluetooth,
                // Wi-Fi) started over per letter typed.
                onTextChanged: {
                    root.search = text
                    selectTimer.restart()
                }
                onAccepted: root.selectFirstMatch()
                // Up/Down walk the visible pages; headings are skipped. A
                // selection still waiting on the timer lands first, so the
                // step starts from the match and not from the page before.
                Keys.onUpPressed: { root.settleSearch(); root.page = Nav.step(root.rows, root.page, -1) || root.page }
                Keys.onDownPressed: { root.settleSearch(); root.page = Nav.step(root.rows, root.page, 1) || root.page }
                Timer { id: selectTimer; interval: 200; onTriggered: root.selectFirstMatch() }
            }

            // The page list scrolls when it is taller than the panel (small or
            // scaled screens); title and search stay in place.
            Flickable {
                id: sidebarFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: sidebarColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onHeightChanged: root.revealPage()

                ColumnLayout {
                    id: sidebarColumn
                    width: sidebarFlick.width
                    spacing: Metrics.spaceSm

                    Repeater {
                        id: sidebarRepeater
                        model: root.rows
                        Item {
                            id: sidebarRow
                            required property var modelData
                            required property int index
                            readonly property bool heading: modelData.kind === "heading"
                            Layout.fillWidth: true
                            // Headings get space above them, less for the first.
                            implicitHeight: heading ? headingLabel.implicitHeight + (index > 0 ? Metrics.spaceMd : Metrics.spaceXs)
                                : Metrics.controlHeight + Metrics.spaceXs

                            // One card behind each group, the same surface the
                            // page's own sections use on the right, so the two
                            // halves of the panel read as the same material.
                            Rectangle {
                                visible: !sidebarRow.heading
                                anchors.fill: parent
                                anchors.topMargin: sidebarRow.modelData.first ? 0 : -sidebarColumn.spacing
                                color: Colors.surface1
                                topLeftRadius: sidebarRow.modelData.first ? Metrics.radiusCard : 0
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: sidebarRow.modelData.last ? Metrics.radiusCard : 0
                                bottomRightRadius: bottomLeftRadius
                            }

                            SectionLabel {
                                id: headingLabel
                                visible: sidebarRow.heading
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: Metrics.spaceMd
                                text: sidebarRow.heading ? sidebarRow.modelData.title : ""
                            }
                            ListRow {
                                visible: !sidebarRow.heading
                                level: 1
                                anchors.fill: parent
                                icon: sidebarRow.heading ? "" : sidebarRow.modelData.icon
                                title: sidebarRow.heading ? "" : sidebarRow.modelData.title
                                selected: !sidebarRow.heading && sidebarRow.modelData.id === root.page
                                onClicked: root.page = sidebarRow.modelData.id
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: Metrics.borderWidth; color: Colors.border }

        // The page and, under it, whatever the page wants to keep in view.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Flickable {
                id: contentFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: pageColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: pageColumn
                    width: contentFlick.width
                    spacing: Metrics.spaceLg

                    PanelHeader {
                        Layout.fillWidth: true
                        role: "pageTitle"
                        title: root.current.title
                        subtitle: root.current.subtitle || ""
                    }

                    // Panels hide instead of closing, and the page stays with the
                    // panel: unloaded on every close, each open paid the first
                    // layout and first render of a 400-600 item page again (a
                    // 101 ms worst frame in the real session, against 17 ms for
                    // the dashboard, which keeps its content). What a page
                    // starts - scans, discovery, trackers, previews - it stops
                    // through PageActivity, which follows the window rather
                    // than the page's lifetime.
                    Loader {
                        id: pageLoader
                        Layout.fillWidth: true
                        active: root.pageKept
                        source: "pages/" + root.page.charAt(0).toUpperCase() + root.page.slice(1) + "Page.qml"
                    }
                }
            }

            // A page may keep an action bar in view by declaring
            // `property Component footer`. Everything on a settings page
            // scrolls, down to the page title - which is right for a title and
            // wrong for an Apply button: on Displays you changed a resolution
            // near the top and then had to scroll to the very end to apply it.
            //
            // It sits outside the Flickable, so it never covers the content;
            // the scroll area is simply shorter while a footer is there.
            Loader {
                Layout.fillWidth: true
                Layout.topMargin: sourceComponent ? Metrics.spaceLg : 0
                readonly property var page: pageLoader.item
                sourceComponent: page && page.footer ? page.footer : null
            }
        }
    }
}
