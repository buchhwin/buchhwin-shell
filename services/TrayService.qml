pragma Singleton
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import "tray/TrayLogic.js" as Logic

Singleton {
    id: root
    // StatusNotifier ids the shell does not show. nm-applet's icon repeats the
    // shell's own network widget; the applet keeps running all the same, as
    // the session's only NetworkManager secret agent - the one that asks for
    // Wi-Fi and VPN passwords - which is why scripts/lib/autostart-skip.sh
    // leaves it alone.
    readonly property var hiddenIds: ["nm-applet"]
    readonly property var items: SystemTray.items.values.filter(item => hiddenIds.indexOf(item.id) < 0)
    // What a tray widget shows: every item that is not passive - the item's
    // own way of saying it has nothing to show right now (TrayLogic). The
    // control center's page keeps listing them all.
    readonly property var shownItems: items.filter(item => item.status !== Status.Passive)
    readonly property int attentionCount: items.filter(item => item.status === Status.NeedsAttention).length

    // The item whose menu the tray menu popup shows (shell/popups/
    // TrayMenuPopup.qml), opened out of a tray widget's icon. Gone with the
    // item: a reference to a destroyed object reads null.
    property var menuItem: null

    // A second right click on the same icon puts its menu away again.
    function openMenu(item, args) {
        if (!item || !item.hasMenu) return false
        if (menuItem === item && PanelService.isOpen("trayMenu")) {
            PanelService.close("trayMenu")
            return true
        }
        menuItem = item
        PanelService.open("trayMenu", args || {})
        return true
    }

    // For `widgets tray` over IPC: counts and flags, never an app's name.
    function status() {
        return { items: items.length, shown: shownItems.length, attention: attentionCount,
                 menuOpen: PanelService.isOpen("trayMenu") }
    }

    // A click on an icon: "left", "middle" or "right" (TrayLogic.clickAction).
    // The menu needs a place to open from, which only the widget knows, so it
    // hands `menuArgs` along.
    function click(item, button, menuArgs) {
        if (!item) return
        const action = Logic.clickAction(button, item.onlyMenu, item.hasMenu)
        if (action === "menu") openMenu(item, menuArgs)
        else if (action === "secondary") item.secondaryActivate()
        else if (action === "activate") item.activate()
    }
}
