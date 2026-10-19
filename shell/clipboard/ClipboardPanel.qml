import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/clipboard/PinLogic.js" as Pin

// Super+V: clipboard history. Type to filter, arrows to move, Enter copies
// the entry back to the clipboard, Delete removes it. Pinned entries come
// first: Ctrl+P (or a right click) pins the selected entry and unpins a
// pinned one, and neither "Clear" nor the history's limit touches them.
ShellPanel {
    id: root
    keyForward: search
    panelId: "clipboard"
    placement: "top-center"
    cardWidth: Metrics.launcherWidth
    scrimColor: Colors.scrim
    property int currentIndex: 0
    // The pins, then the history. Without pins (most of the time) and
    // without a query this is the service's own list, as it always was.
    readonly property var filtered: {
        const query = search.text.trim().toLowerCase()
        const history = query.length ? ClipboardService.entries.filter(entry => entry.text.toLowerCase().includes(query)) : ClipboardService.entries
        const pins = Pin.matching(ClipboardService.pinRows, query)
        return pins.length ? pins.concat(history) : history
    }

    function activate(entry) {
        if (!entry) return
        if (ClipboardService.isPinned(entry)) ClipboardService.copyPin(entry)
        else ClipboardService.copy(entry)
        PanelService.close("clipboard")
    }

    function forget(entry) {
        if (!entry) return
        if (ClipboardService.isPinned(entry)) ClipboardService.unpin(entry)
        else ClipboardService.remove(entry)
    }

    // A pin refused because the list is full says so on the row for a
    // moment, as the launcher's refused pins do.
    property string refusedId: ""
    Timer { id: refusedTimer; interval: Metrics.osdTimeout; onTriggered: root.refusedId = "" }
    Connections {
        target: ClipboardService
        function onPinRefused() { refusedTimer.restart() }
    }
    function togglePin(entry) {
        if (!entry) return
        root.refusedId = ClipboardService.isPinned(entry) || !ClipboardService.pinsFull ? "" : entry.id
        ClipboardService.togglePin(entry)
    }

    onWantedChanged: {
        if (wanted) {
            search.text = ""
            currentIndex = 0
            ClipboardService.refresh()
            ClipboardService.loadPins()
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
                onDeleteOnEmpty: root.forget(root.filtered[root.currentIndex])
                onKeyPressed: event => {
                    if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                        event.accepted = true
                        root.togglePin(root.filtered[root.currentIndex])
                    } else {
                        event.accepted = false
                    }
                }
            }
            ShellButton {
                icon: Icons.remove; text: "Clear"; variant: "ghost"
                enabledState: ClipboardService.entries.length > 0
                // The whole history and its thumbnails, for good: it asks
                // twice, as "Clear history" in Settings does. The pins stay,
                // which is what they are for, and the question says so.
                toolTip: ClipboardService.pins.length ? "Pinned entries stay" : ""
                confirm: true; confirmText: "Clear history?"
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
                    readonly property bool pinned: ClipboardService.isPinned(modelData)
                    // The last pin, with history under it: a line between
                    // the two lists, or a pinned entry and its copy in the
                    // history read as one list with a duplicate.
                    readonly property bool lastPin: pinned && index + 1 < root.filtered.length
                        && !ClipboardService.isPinned(root.filtered[index + 1])
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
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Right-click pins, as it pins an app in the launcher.
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) root.togglePin(row.modelData)
                            else root.activate(row.modelData)
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Metrics.spaceMd
                        anchors.rightMargin: Metrics.spaceMd
                        spacing: Metrics.spaceMd

                        ShellIcon {
                            visible: !row.modelData.image
                            Layout.preferredWidth: Metrics.iconLg
                            glyph: row.pinned ? Icons.pin : "󰦨"
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
                        // A pinned picture has no glyph to say so; the mark
                        // goes beside its text instead.
                        ShellIcon {
                            visible: row.pinned && row.modelData.image
                            glyph: Icons.pin
                            size: Metrics.iconSm
                            color: row.selected ? Colors.accentOnSoft : Colors.mutedText
                        }
                        ShellText {
                            visible: root.refusedId.length > 0 && root.refusedId === row.modelData.id && !row.pinned
                            text: "At most " + ClipboardService.pinLimit + " pinned"
                            role: "small"
                            color: row.selected ? Colors.mutedOnSoft : Colors.mutedText
                        }
                        // Deleted for good - `cliphist delete` and the
                        // thumbnail - so the trash can (Icons.remove), not the
                        // dismiss cross. One click, as every row's own remove
                        // in the shell takes and as Del on the selected row
                        // does; only "Clear" above, the whole history, asks.
                        // A pinned row unpins instead: its copy goes, the
                        // history keeps what it has.
                        ShellButton {
                            toolTip: row.pinned ? "Unpin" : "Remove from history"
                            icon: row.pinned ? Icons.unpin : Icons.remove; variant: "ghost"; compact: true
                            onClicked: root.forget(row.modelData)
                        }
                    }
                    Rectangle {
                        visible: row.lastPin
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Metrics.spaceMd
                        anchors.rightMargin: Metrics.spaceMd
                        height: Metrics.borderWidth
                        color: Colors.border
                    }
                }
            }
        }

        // With the history off, "Nothing copied yet" promised that copying
        // would fill it; the panel says what is the matter instead and leads
        // to the switch (Settings > Desktop extras). Two states rather than
        // one with a hidden button: a hidden action still takes its row.
        // Pins are kept with the history off too, and the notice goes under
        // them rather than away.
        readonly property bool historyOff: ClipboardService.entries.length === 0 && !ClipboardService.loading
            && !search.text.length && !ClipboardService.enabled
        EmptyState {
            Layout.fillWidth: true
            visible: root.filtered.length === 0 && !parent.historyOff
            icon: ClipboardService.loading ? Icons.busy : "󰦨"
            title: ClipboardService.loading ? "Loading …" : search.text.length ? "No results" : "Nothing copied yet"
        }
        EmptyState {
            Layout.fillWidth: true
            visible: parent.historyOff
            icon: "󰦨"
            title: "Clipboard history is off"
            description: "Nothing you copy is kept while it is off"
            ShellButton {
                focusOnTab: true
                icon: Icons.settings
                text: "Clipboard settings"
                compact: true
                onClicked: PanelService.open("settings", { page: "desktop", section: "Clipboard" })
            }
        }

        ShellText {
            Layout.fillWidth: true
            text: "Enter copies · Ctrl+P pins · Del deletes · Esc closes"
            role: "caption"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
