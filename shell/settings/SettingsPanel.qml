import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "pages"
import "../../services/settings/SettingsNavLogic.js" as Nav
import "../../services/settings/SettingsFieldLogic.js" as Fields

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
    // Once a page has been shown it stays while the panel comes and goes: see
    // the page Loader below. A minute after it closed for good it is let go,
    // which is the memory a page holds - unless it still has something the
    // user typed and did not hand on (a field with a draft, a display change
    // waiting for its answer), which a reload would throw away. A draft holds
    // it for half an hour at most (SettingsFieldLogic): it used to hold it for
    // the session, and any text did - a search, a test line, a field emptied.
    property bool pageKept: false
    property real closedAt: 0
    onShownChanged: {
        if (shown) { releaseTimer.stop(); pageKept = true }
        else { closedAt = Date.now(); releaseTimer.restart() }
    }
    Timer {
        id: releaseTimer
        interval: Fields.CHECK_MS
        repeat: true
        onTriggered: {
            if (root.shown || !root.pageKept) { stop(); return }
            if (!Fields.releaseNow(Date.now() - root.closedAt, DisplayService.confirming, root.pendingEdits(pageLoader.item))) return
            root.pageKept = false
            stop()
        }
    }
    function pendingEdits(item) {
        if (!item) return false
        if (item.objectName === "shellTextField" && Fields.holdsDraft(item)) return true
        for (const child of item.children) if (pendingEdits(child)) return true
        return false
    }
    // Sidebar rows (group headings and pages) filtered by the search.
    readonly property var rows: Nav.rows(search)
    readonly property var visiblePageIds: Nav.pageIds(rows)
    readonly property var current: Nav.pageById(page) || Nav.PAGES[0]

    // The search starts empty on every open, as in the launcher, the overview
    // and the other searchable panels: a kept one reopened Settings on a
    // filtered sidebar, and Escape (ShellTextField: back to the text at
    // focus) then closed Settings instead of clearing it. The page stays -
    // the selection the cleared text would make is not wanted.
    onWantedChanged: if (wanted) {
        if (searchInput.text.length) {
            searchInput.text = ""
            selectTimer.stop()
        }
        openPage(PanelService.args.page)
        Qt.callLater(revealPage)
    }
    // A page asked for by name (`buchhwin settings open PAGE`, a link from
    // another panel). Only a page Settings has: the name used to go straight
    // into the page Loader's path, so `settings open foo` showed Appearance's
    // title over an empty body, logged a load error, and the bad name stuck
    // for every later open (round 12, security#6).
    function openPage(asked) {
        if (typeof asked === "string" && Nav.pageById(asked)) page = asked
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
        const bottom = row.y + row.height
        // The page comes in with its group's heading above it whenever the
        // two fit together: only the first page of a group used to bring its
        // heading, and scrolled to the row alone, the group's card was cut
        // square under the search field (round 12, D14). A group too long for
        // that brings the row to the edge.
        const headingAt = Nav.headingIndex(rows, page)
        const heading = headingAt >= 0 ? sidebarRepeater.itemAt(headingAt) : null
        const withHeading = heading !== null && bottom - heading.y <= sidebarFlick.height
        const top = withHeading ? heading.y : row.y
        if (top < sidebarFlick.contentY) sidebarFlick.contentY = top
        else if (bottom > sidebarFlick.contentY + sidebarFlick.height)
            sidebarFlick.contentY = Math.min(maxY, withHeading ? top : bottom - sidebarFlick.height)
    }
    // The same for the page: Tab walked to a control below the fold and left
    // it there, focused and out of sight. Whatever takes the focus inside the
    // page is scrolled into view, with a little air around it.
    function revealFocus(item) {
        let inside = false
        for (let walk = item; walk; walk = walk.parent)
            if (walk === contentFlick.contentItem) { inside = true; break }
        if (!inside || contentFlick.height <= 0) return
        const top = item.mapToItem(contentFlick.contentItem, 0, 0).y - Metrics.spaceLg
        const bottom = top + item.height + Metrics.spaceLg * 2
        const maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height)
        if (top < contentFlick.contentY) contentFlick.contentY = Math.max(0, top)
        else if (bottom > contentFlick.contentY + contentFlick.height)
            contentFlick.contentY = Math.min(maxY, bottom - contentFlick.height)
    }
    readonly property Item focusedItem: contentFlick.Window.activeFocusItem
    onFocusedItemChanged: if (focusedItem) revealFocus(focusedItem)
    Connections {
        target: PanelService
        function onArgsChanged() { if (root.wanted) root.openPage(PanelService.args.page) }
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

            // The panels' header at their size, so "Settings" is as large as
            // "Control center". The gear stays: this heads a list of pages,
            // each with its icon, rather than a page.
            PanelHeader {
                Layout.fillWidth: true
                Layout.bottomMargin: Metrics.spaceXs
                icon: Icons.settings
                title: "Settings"
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
            //
            // Its rows fade out at an edge the list goes on past, instead of
            // ending in a straight cut: the groups' cards were cut square
            // right under the search field (round 12, D14). Only while there
            // is more to scroll to, so a list that fits draws as it always
            // did, without a layer.
            Flickable {
                id: sidebarFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: sidebarColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onHeightChanged: root.revealPage()
                ScrollFeel { view: sidebarFlick }
                readonly property bool moreAbove: contentY > 0
                readonly property bool moreBelow: contentY + height < contentHeight - 1
                layer.enabled: root.shown && height > 0 && (moreAbove || moreBelow)
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: sidebarFade
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

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

                    // Where the list would be: an empty sidebar under a search
                    // reads as the panel having broken, not as no match.
                    EmptyState {
                        Layout.fillWidth: true
                        Layout.topMargin: Metrics.spaceLg
                        visible: root.search.length > 0 && root.rows.length === 0
                        icon: Icons.search
                        title: "No settings match"
                    }
                }
            }

            // The sidebar's mask: opaque, with a ramp to nothing along an edge
            // that has more beyond it. Never drawn itself (and so not laid out).
            Rectangle {
                id: sidebarFade
                visible: false
                width: sidebarFlick.width
                height: sidebarFlick.height
                layer.enabled: sidebarFlick.layer.enabled
                readonly property real ramp: height > 0 ? Math.min(0.5, Metrics.listEdgeFade / height) : 0
                gradient: Gradient {
                    GradientStop { position: 0; color: sidebarFlick.moreAbove ? "transparent" : Colors.maskShown }
                    GradientStop { position: sidebarFade.ramp; color: Colors.maskShown }
                    GradientStop { position: 1 - sidebarFade.ramp; color: Colors.maskShown }
                    GradientStop { position: 1; color: sidebarFlick.moreBelow ? "transparent" : Colors.maskShown }
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
                ScrollFeel { view: contentFlick }

                ColumnLayout {
                    id: pageColumn
                    width: contentFlick.width
                    spacing: Metrics.panelGap

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
                        // The page that is shown, never a raw name: `current`
                        // is always one of Nav.PAGES.
                        source: "pages/" + root.current.id.charAt(0).toUpperCase() + root.current.id.slice(1) + "Page.qml"
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
            //
            // Hidden while it holds nothing: a Loader keeps the height of the
            // item it last held, so after Displays (the one page with a
            // footer) every other page ended 64 px short of the panel, over an
            // empty band (round 12, D3).
            Loader {
                Layout.fillWidth: true
                Layout.topMargin: sourceComponent ? Metrics.panelGap : 0
                visible: item !== null
                readonly property var page: pageLoader.item
                sourceComponent: page && page.footer ? page.footer : null
            }
        }
    }
}
