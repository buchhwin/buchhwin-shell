import QtQuick
import Quickshell
import qs.shell.widgets
import qs.theme
import qs.services
import "../../services/launcher/IconLogic.js" as IconLogic
WidgetBase {
    id: root
    // The notch's overview asks for the application rather than the window
    // (`options.show: "app"`): "Brave Web Browser" instead of a tab title that
    // never fits a cell. The title stays everywhere else - it is what this
    // widget is for.
    readonly property bool appOnly: instance !== null && instance.options !== undefined
        && instance.options !== null && instance.options.show === "app"
    // Looked up by id, which no binding follows: DesktopEntries scans after
    // the shell is up, so a binding that ran first kept "no entry" (the raw
    // id's last part) until the window changed. Reading
    // the launcher's revision, counted once per settled scan, runs it again
    // when the entries are there.
    readonly property var appEntry: {
        LauncherService.entriesRevision
        const id = HyprlandService.activeAppId
        if (!id.length) return null
        return (typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(id) : null)
            || DesktopEntries.byId(id) || DesktopEntries.byId(id.toLowerCase()) || null
    }
    readonly property string appName: {
        const id = HyprlandService.activeAppId
        if (!id.length) return ""
        if (appEntry && appEntry.name) return appEntry.name
        // No entry (a reverse-DNS id like com.microsoft.VSCode): its last part.
        const parts = id.split(".")
        return parts.length > 1 ? parts[parts.length - 1] : id
    }
    // The application's own icon, as the dock beside it draws it: the entry's
    // icon, else one named like the window's id - and no generic stand-in
    // (IconLogic falls back to one; here the window glyph is the fallback).
    // On the notch the glyph stays: it is drawn in the notch's inks, and a
    // coloured icon in a cell of white glyphs reads as a stray picture.
    readonly property string appIcon: !onDark && HyprlandService.activeTitle.length
        ? IconLogic.source([appEntry && appEntry.icon ? appEntry.icon : "", HyprlandService.activeAppId],
                           name => name === IconLogic.fallbackName ? "" : Quickshell.iconPath(name, true))
        : ""
    icon: HyprlandService.activeTitle.length ? "󰖯" : ""
    glyph: appIcon.length ? appGlyph : null
    label: appOnly ? appName : HyprlandService.activeTitle
    // A window title is the one value that is never long enough: every step up
    // is more of it before the ellipsis, which is exactly what this widget has
    // to say. At `large` the application goes underneath, because a title
    // alone often does not name it ("Inbox (3)").
    maxLabelWidth: sizeClass === "small" ? 320 : sizeClass === "medium" ? 480 : 640
    // The application's name, worked out above, not its raw id.
    detail: appOnly ? "" : appName
    hasData: HyprlandService.activeTitle.length > 0

    // At the glyph's size, so the pill keeps its height and its rhythm. In
    // an Item: an Image's implicit size is its picture's, and cannot be set.
    Component {
        id: appGlyph
        Item {
            implicitWidth: Typography.titleSize * root.scaleFactor
            implicitHeight: implicitWidth
            Image {
                anchors.fill: parent
                sourceSize.width: parent.implicitWidth * 2
                sourceSize.height: parent.implicitHeight * 2
                source: root.appIcon
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
        }
    }
}
