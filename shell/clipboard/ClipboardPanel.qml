import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Super+V: clipboard history. Type to filter, arrows to move, Enter copies
// the entry back to the clipboard, Delete removes it.
ShellPanel {
    id: root
    keyForward: search
    panelId: "clipboard"
    placement: "top-center"
    cardWidth: Metrics.launcherWidth
    scrimColor: Colors.scrim
    property int currentIndex: 0
    readonly property var filtered: {
        const query = search.text.trim().toLowerCase()
        return query.length ? ClipboardService.entries.filter(entry => entry.text.toLowerCase().includes(query)) : ClipboardService.entries
    }

    function activate(entry) {
        if (!entry) return
        ClipboardService.copy(entry)
        PanelService.close("clipboard")
    }

    onWantedChanged: {
        if (wanted) {
            search.text = ""
            currentIndex = 0
            ClipboardService.refresh()
        }
    }
    onFilteredChanged: currentIndex = Math.min(currentIndex, Math.max(0, filtered.length - 1))

    ColumnLayout {
        width: parent.width
        spacing: Metrics.panelGap

        RowLayout {
            spacing: Metrics.spaceSm
            ShellTextField {
                id: search
                Layout.fillWidth: true
                icon: Icons.search
                placeholder: ClipboardService.enabled ? "Search clipboard …" : "History is turned off in Settings"
                onAccepted: root.activate(root.filtered[root.currentIndex])
                Keys.onUpPressed: root.currentIndex = Math.max(0, root.currentIndex - 1)
                Keys.onDownPressed: root.currentIndex = Math.min(root.filtered.length - 1, root.currentIndex + 1)
                onDeleteOnEmpty: {
                    const entry = root.filtered[root.currentIndex]
                    if (entry) ClipboardService.remove(entry)
                }
            }
            ShellButton {
                icon: Icons.remove; text: "Clear"; variant: "ghost"
                enabledState: ClipboardService.entries.length > 0
                // The whole history and its thumbnails, for good: it asks
                // twice, as "Clear history" in Settings does.
                confirm: true; confirmText: "Clear all?"
                onClicked: ClipboardService.wipe()
            }
        }

        CardSection {
            Layout.fillWidth: true
            visible: root.filtered.length > 0
            padding: Metrics.spaceXs

            ListView {
                id: list
                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, Metrics.launcherHeight - Metrics.controlHeight * 3)
                clip: true
                // Rows (and their decoded images) only while the panel shows.
                model: root.shown ? root.filtered : []
                currentIndex: root.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: Animations.hover
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                ScrollFeel { view: list }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.currentIndex
                    width: list.width
                    implicitHeight: modelData.image ? Metrics.coverSize + Metrics.spaceSm * 2 : Metrics.rowHeight
                    // The same shape and the same card-aware hover as ListRow, which
                    // this row cannot be: its image entries carry a wide thumbnail.
                    radius: Metrics.radiusCard
                    color: selected ? Colors.accentSoft : rowMouse.containsMouse ? Colors.surface1Hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activate(row.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Metrics.spaceMd
                        anchors.rightMargin: Metrics.spaceMd
                        spacing: Metrics.spaceMd

                        ShellIcon {
                            visible: !row.modelData.image
                            Layout.preferredWidth: Metrics.iconLg
                            glyph: "󰦨"
                            size: Metrics.iconMd
                            // On the selected row's tint: the inks measured on
                            // it (accentForeground and mutedText are measured
                            // on cards, and the tint takes contrast away).
                            color: row.selected ? Colors.accentOnSoft : Colors.mutedText
                        }
                        Rectangle {
                            visible: row.modelData.image
                            Layout.preferredWidth: Metrics.clipboardThumbWidth
                            Layout.preferredHeight: Metrics.coverSize
                            radius: Metrics.radiusTiny
                            color: Colors.surface2
                            clip: true
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                // Decoded at the row's size: the "thumb" is the
                                // whole clipboard image, a screenshot 33 MB.
                                sourceSize.width: Math.ceil(Metrics.clipboardThumbWidth * 2)
                                sourceSize.height: Math.ceil(Metrics.coverSize * 2)
                                source: ClipboardService.thumbnail(row.modelData)
                            }
                        }
                        ShellText {
                            Layout.fillWidth: true
                            text: row.modelData.image ? row.modelData.text : row.modelData.text.replace(/\s+/g, " ")
                            muted: row.modelData.image
                            color: !muted ? Colors.text : row.selected ? Colors.mutedOnSoft : Colors.mutedText
                        }
                        // Deleted for good - `cliphist delete` and the
                        // thumbnail - so the trash can (Icons.remove), not the
                        // dismiss cross. One click, as every row's own remove
                        // in the shell takes and as Del on the selected row
                        // does; only "Clear" above, the whole history, asks.
                        ShellButton {
                            toolTip: "Remove from history"
                            icon: Icons.remove; variant: "ghost"; compact: true
                            onClicked: ClipboardService.remove(row.modelData)
                        }
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: root.filtered.length === 0
            icon: ClipboardService.loading ? Icons.busy : "󰦨"
            title: ClipboardService.loading ? "Loading …" : search.text.length ? "No results" : "Nothing copied yet"
        }

        ShellText {
            Layout.fillWidth: true
            text: "Enter copies · Del deletes · Esc closes"
            role: "caption"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
