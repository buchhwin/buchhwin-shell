import QtQuick
import qs.theme
import qs.services
import qs.shell.components

// A background app's menu, opened out of its icon in a tray widget (right
// click): the control center's menu (TrayMenu, the app's DBusMenu drawn with
// the shell's rows, submenus included), in a popup of its own that grows out
// of the icon. Built on its first open (PanelService.lazyPanels); the menu is
// asked of the app only while the popup is shown.
PopupPanel {
    id: root
    panelId: "trayMenu"
    readonly property var item: TrayService.menuItem
    // The menu while it is shown: the body is a component of its own, so
    // its items are not reachable by id from here.
    property Item menu: null

    // Out of a submenu first, as the control center's page steps back.
    escapeHandler: () => {
        if (!root.menu || !root.menu.stack.length) return false
        root.menu.stack = root.menu.stack.slice(0, -1)
        return true
    }

    // An app that quits while its menu is open takes the menu with it.
    onItemChanged: if (!item && wanted) PanelService.close(root.panelId)

    body: TrayMenu {
        id: trayMenu
        // At the top, "Back" is the way out of the popup.
        handle: root.item ? root.item.menu : null
        title: root.item ? (root.item.tooltipTitle || root.item.title || root.item.id) : ""
        onDone: PanelService.close(root.panelId)
        onTriggered: PanelService.close(root.panelId)
        Component.onCompleted: root.menu = trayMenu
        Component.onDestruction: if (root.menu === trayMenu) root.menu = null
    }
}
