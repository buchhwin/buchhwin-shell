import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/NotificationLogic.js" as N

ShellRoot {
    Component.onCompleted: {
        const history = [
            { appName: "Brave", appIcon: "brave", summary: "1" },
            { appName: "Kitty", appIcon: "", summary: "2" },
            { appName: "brave", appIcon: "", summary: "3" },
            { appName: "", appIcon: "", summary: "4" },
            { appName: "Brave", appIcon: "", summary: "5" },
            { appName: "Brave", appIcon: "", summary: "6" },
            null
        ]
        const groups = N.group(history)
        T.eq(groups.map(g => g.name), ["Brave", "System", "Kitty"], "groups ordered by newest notification, case-insensitive app names")
        T.eq(groups[0].items.map(n => n.summary), ["6", "5", "3", "1"], "newest first inside a group")
        T.eq(groups[0].icon, "brave", "first known icon kept")
        T.eq(N.visibleItems(groups[0], false).map(n => n.summary), ["6", "5"], "collapsed group shows two")
        T.eq(N.visibleItems(groups[0], true).length, 4, "expanded group shows all")
        T.eq(N.visibleItems({ items: [1, 2, 3] }, false).length, 3, "three are shown without collapsing")
        T.eq(N.group([]).length, 0, "empty history")
        T.finish("NotificationGroupTest")
    }
}
