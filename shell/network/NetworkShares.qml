import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Network drives in the VPN popup: the shares this machine mounts on first
// use (systemd automounts) and those it has mounted, and whether they can be
// reached now. Everything comes from /proc/self/mountinfo (NetworkService,
// ShareLogic); a drive's path is never touched from here while no VPN is up,
// and "Open" - the file manager, which mounts it - is offered only with one.
// Gone where there are no such drives.
ColumnLayout {
    id: root
    spacing: Metrics.spaceXxs
    visible: NetworkService.shares.length > 0
    Component.onCompleted: NetworkService.watchShares(true)
    Component.onDestruction: NetworkService.watchShares(false)

    ScrollList {
        Layout.fillWidth: true
        title: "Network drives"
        maxHeight: Metrics.popupListHeight / 2 + Metrics.rowHeight
        Repeater {
            // Rows keyed by path: a re-read hands a new list.
            model: ScriptModel { values: NetworkService.shares.map(share => share.point) }
            ListRow {
                id: shareRow
                required property string modelData
                readonly property var share: NetworkService.shares.find(item => item.point === modelData) || null
                width: parent.width
                level: 1
                icon: "󰉌"
                title: share ? share.name : ""
                subtitle: NetworkService.shareStatus(share)
                active: share !== null && share.mounted
                interactive: false
                ShellButton {
                    focusOnTab: true
                    visible: NetworkService.shareOpenable(shareRow.share)
                    compact: true
                    text: "Open"
                    onClicked: NetworkService.openShare(shareRow.share)
                }
            }
        }
    }

    // Which drives need the VPN, or - mounted while no tunnel is up - the
    // hang to expect (the file manager waits on a server it cannot reach).
    ShellText {
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.spaceSm
        Layout.rightMargin: Metrics.spaceSm
        readonly property var summary: NetworkService.sharesSummary
        visible: text.length > 0
        text: summary.warning.length ? summary.warning : summary.line
        role: "caption"
        color: summary.warning.length ? Colors.warning : Colors.mutedText
        wrapMode: Text.Wrap
    }
}
