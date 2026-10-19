import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/notifications/NotificationLogic.js" as Logic

// Super+N notification history with Do Not Disturb, and under "Earlier" the
// ones kept from before the shell's last restart (Settings > Notifications
// "Keep notifications across restarts").
ShellPanel {
    id: root
    keyNavigation: true
    // The search field while there is something to search. With an empty
    // history the field is hidden, and the keys went into it all the same:
    // the empty state turned into "No notification matches" for words nobody
    // could see.
    keyForward: NotificationService.listed > 0 ? search : null
    // The first notification while the centre is open brings the field, and
    // the panel's own key holder lets go as it does (ShellPanel hands the
    // focus over only as it opens): the field takes it then, or Escape and
    // the arrow keys reached nothing until the centre was opened again.
    onKeyForwardChanged: if (wanted && keyForward) Qt.callLater(focusEntry)
    panelId: "notifications"
    placement: "top-right"
    // The corner, always. It used to follow the desktop clock like any other
    // hotkey panel, and in notch mode the clock is the notch in the middle of
    // the screen - so a list that belongs in the corner opened dead centre.
    followClock: false
    cardWidth: Metrics.notificationCenterWidth
    // All the room there is below where it starts: down to a bottom bar or
    // the dock (ShellPanel's bottomOffset), or up to the bar or the notch out
    // of the dock's bell. It used to measure to the screen's bottom margin
    // and ran down over the taskbar, its bell, the clock and the tray
    // With nothing in the history it is only as tall as what
    // it says (-1 follows the content): a card the height of the screen stood
    // there for one tile and "No notifications". Asked of the history, not of
    // the search, so a word that matches nothing does not fold the card up
    // under the field while it is typed.
    cardHeight: NotificationService.listed > 0 ? roomBelowTop : -1

    // Group keys the user expanded ("N more").
    property var expanded: ({})
    property string query: ""
    // The clock the cards' "5 min" is read against, while the centre shows.
    property real now: Date.now()
    Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: root.shown
        onTriggered: root.now = Date.now()
    }
    // Searched and grouped while shown, like the list below: hidden, every
    // notification that arrived ran both over the whole history for a panel
    // nobody saw. `shown` turns true in the same turn the window maps
    // (ShellPanel), so the first frame of an open already has the list.
    // Nothing while Clear all lets the history go: the list is emptied once
    // rather than worked out again for each notification it dismisses.
    readonly property var matching: shown && !NotificationService.clearing
        ? Logic.search(NotificationService.history, query) : []
    // Grouped as the cards name them: a browser's site as its web app
    // (NotificationService.describe).
    readonly property var groups: Logic.group(matching, NotificationService.describe)
    // What the list below is keyed by, and how a key finds its group.
    readonly property var groupKeys: groups.map(entry => entry.key)
    readonly property var groupIndex: Logic.groupIndex(groups)
    // The kept ones from before the restart, newest first, searched like the
    // rest; keyed by their ids (strings) as the groups are by their keys.
    readonly property var earlierMatching: shown && !NotificationService.clearing
        ? Logic.search(NotificationService.earlier, query) : []
    readonly property var earlierIds: earlierMatching.map(item => item.id)
    readonly property var earlierIndex: {
        const index = {}
        for (const item of earlierMatching) index[item.id] = item
        return index
    }
    readonly property int matchCount: matching.length + earlierMatching.length

    // The field, not the query: the panel is built once and keeps its field,
    // so clearing only `query` reopened it with the old words still in the
    // field over an unfiltered list, and the next key searched for both.
    // The field drives the query, so clearing it clears both.
    onWantedChanged: if (wanted) { NotificationService.markRead(); search.text = "" }

    ColumnLayout {
        // The whole card while it holds a list; measured while it does not.
        width: parent.width
        height: root.cardHeight > 0 ? parent.height : implicitHeight
        spacing: Metrics.panelGap

        PanelHeader {
            Layout.fillWidth: true
            title: "Notifications"

            ShellButton {
                visible: NotificationService.listed > 0
                text: "Clear all"; compact: true; variant: "ghost"
                // Every notification of every app, with no way back: it asks
                // twice, like every button that destroys something.
                confirm: true; confirmText: "Clear all?"
                onClicked: NotificationService.clearAll()
            }
        }

        ShellTextField {
            id: search
            Layout.fillWidth: true
            visible: NotificationService.listed > 0
            icon: Icons.search
            placeholder: "Search notifications …"
            onTextChanged: root.query = text
        }

        QuickTile {
            Layout.fillWidth: true
            icon: NotificationService.dndActive ? "󰂛" : "󰂚"
            title: "Do Not Disturb"
            subtitle: NotificationService.dndLabel
            checked: NotificationService.dndActive
            onToggled: value => NotificationService.setDnd(value ? "manual" : "off")
            onActivated: PanelService.open("controlCenter", { page: "dnd" })
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The empty state's room, for the measured card.
            implicitHeight: root.matchCount === 0 ? empty.implicitHeight + Metrics.spaceXl * 2 : 0

            EmptyState {
                id: empty
                // A search only while there is something to search: words
                // typed before Clear all stay in the hidden field, and the
                // empty centre said "No notification matches" for them.
                readonly property bool searching: root.query.length > 0 && NotificationService.listed > 0
                anchors.centerIn: parent
                visible: root.matchCount === 0
                icon: searching ? Icons.search : "󰂜"
                title: searching ? "No notification matches" : "No notifications"
            }

            Flickable {
                id: list
                anchors.fill: parent
                visible: root.matchCount > 0
                clip: true
                contentHeight: groupColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollFeel { view: list }

                ColumnLayout {
                    id: groupColumn
                    width: list.width
                    spacing: Metrics.spaceLg

                    // Built while shown: every notification that arrived re-created
                    // every group and card behind the hidden panel. Keyed by the
                    // group keys, strings, which a ScriptModel compares by value
                    // (pitfall 76): a group that is still there keeps its delegate
                    // and its cards, hover and focus included. On the group
                    // objects themselves - new ones on every change - every group
                    // and card was built again for each notification that came or
                    // went, and Clear all of a hundred blocked for over three
                    // seconds.
                    Repeater {
                        model: ScriptModel { values: root.shown ? root.groupKeys : [] }

                        ColumnLayout {
                            id: groupItem
                            required property string modelData
                            // Looked up by its key. For the evaluation in which its
                            // group has just gone the entry is missing, and an
                            // empty one stands in until the delegate goes too.
                            readonly property var group: root.groupIndex[modelData]
                                || ({ key: modelData, name: "", icon: "", items: [] })
                            readonly property bool isExpanded: root.expanded[modelData] === true
                            readonly property var shown: Logic.visibleItems(group, isExpanded)
                            Layout.fillWidth: true
                            spacing: Metrics.spaceSm

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Metrics.spaceXs
                                spacing: Metrics.spaceSm
                                Image {
                                    visible: groupItem.group.icon.length > 0 && status === Image.Ready
                                    Layout.preferredWidth: Metrics.iconSm
                                    Layout.preferredHeight: Metrics.iconSm
                                    // An icon name, an absolute path or a file://
                                    // URI, by the card's own route.
                                    source: Logic.iconSource(groupItem.group.icon, name => Quickshell.iconPath(name, true))
                                    sourceSize.width: Metrics.iconSm * 2
                                }
                                // Elides rather than pushing the buttons out of
                                // the card: grows to its own width and no
                                // further, the spacer after it takes the rest.
                                SectionLabel {
                                    id: appName
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: appName.implicitWidth
                                    text: groupItem.group.name
                                }
                                ShellText { text: String(groupItem.group.items.length); role: "caption" }
                                Item { Layout.fillWidth: true }
                                ShellButton {
                                    visible: groupItem.group.items.length > groupItem.shown.length || groupItem.isExpanded && groupItem.group.items.length > 3
                                    text: groupItem.isExpanded ? "Show less" : (groupItem.group.items.length - groupItem.shown.length) + " more"
                                    compact: true; variant: "ghost"
                                    onClicked: {
                                        const next = Object.assign({}, root.expanded)
                                        next[groupItem.group.key] = !groupItem.isExpanded
                                        root.expanded = next
                                    }
                                }
                                // Normal and Muted, back and forth
                                // (Logic.nextAppRule); "Always urgent" is set
                                // in Settings > Notifications and goes back to
                                // normal here.
                                ShellButton {
                                    readonly property string rule: NotificationService.appRule(groupItem.group.key)
                                    icon: rule === "mute" ? "󰂛" : rule === "critical" ? Icons.warning
                                        : rule === "always" ? "\u{f0d59}" : "󰂚"
                                    compact: true
                                    variant: rule === "default" ? "ghost" : "surface"
                                    toolTip: rule === "mute" ? "Muted · click to unmute"
                                        : rule === "critical" ? "Always urgent · click for normal"
                                        : rule === "always" ? "Never muted · click for normal"
                                        : "Normal · click to mute this app"
                                    onClicked: NotificationService.setAppRule(groupItem.group.key, Logic.nextAppRule(rule))
                                }
                                ShellButton {
                                    icon: Icons.close; compact: true; variant: "ghost"
                                    toolTip: "Dismiss all from this app"
                                    onClicked: groupItem.group.items.slice().forEach(notification => notification.dismiss())
                                }
                            }

                            Repeater {
                                // The notification objects themselves, which the
                                // server keeps for a notification's whole life: a
                                // card that stays is the same card.
                                model: ScriptModel { values: groupItem.shown }
                                NotificationCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    notification: modelData
                                    receivedAt: NotificationService.arrivalOf(modelData)
                                    now: root.now
                                }
                            }
                        }
                    }

                    // From before the shell's last restart: what they said
                    // and when, nothing to act on but a web app to open.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Metrics.spaceXs
                        visible: root.earlierIds.length > 0
                        spacing: Metrics.spaceSm
                        SectionLabel { text: "Earlier" }
                        ShellText { text: String(root.earlierIds.length); role: "caption" }
                        Item { Layout.fillWidth: true }
                    }
                    Repeater {
                        model: ScriptModel { values: root.shown ? root.earlierIds : [] }
                        NotificationCard {
                            required property string modelData
                            Layout.fillWidth: true
                            notification: root.earlierIndex[modelData]
                                || ({ id: modelData, earlier: true, appName: "", summary: "", body: "", actions: [], hints: {} })
                            receivedAt: NotificationService.arrivalOf(notification)
                            now: root.now
                        }
                    }
                }
            }
        }
    }
}
