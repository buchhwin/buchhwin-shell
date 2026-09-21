import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme

// Application menu (DBusMenu) rendered with shell components, with submenus.
ColumnLayout {
    id: root
    property var handle: null
    property string title: ""
    property var stack: []
    signal done()
    signal triggered()
    spacing: Metrics.spaceXxs

    readonly property var currentHandle: stack.length ? stack[stack.length - 1].handle : handle
    onHandleChanged: stack = []

    QsMenuOpener { id: opener; menu: root.currentHandle }

    RowLayout {
        Layout.fillWidth: true
        ShellButton {
            icon: Icons.back; variant: "ghost"; compact: true
            onClicked: root.stack.length ? root.stack = root.stack.slice(0, -1) : root.done()
        }
        ShellText { Layout.fillWidth: true; text: root.stack.length ? root.stack[root.stack.length - 1].text : root.title; role: "title" }
    }

    Repeater {
        model: opener.children
        Item {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: modelData.isSeparator ? Metrics.spaceSm : row.implicitHeight

            Rectangle {
                visible: entry.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Metrics.borderWidth
                color: Colors.border
            }

            ListRow {
                id: row
                visible: !entry.modelData.isSeparator
                width: parent.width
                compact: true
                title: entry.modelData.text.replace(/_(?=\S)/g, "")
                iconSource: entry.modelData.icon || ""
                chevron: entry.modelData.hasChildren
                opacity: entry.modelData.enabled ? 1 : Effects.disabledOpacity
                ShellIcon {
                    visible: entry.modelData.checkState === Qt.Checked
                    glyph: Icons.check; size: Metrics.iconSm; color: Colors.accentForeground
                }
                onClicked: {
                    if (!entry.modelData.enabled) return
                    if (entry.modelData.hasChildren) {
                        root.stack = root.stack.concat([{ handle: entry.modelData, text: entry.modelData.text.replace(/_(?=\S)/g, "") }])
                    } else {
                        entry.modelData.triggered()
                        root.done()
                        root.triggered()
                    }
                }
            }
        }
    }
}
