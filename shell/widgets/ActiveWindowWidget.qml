import QtQuick
import Quickshell
import qs.shell.widgets
import qs.services
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
    // id's last part) until the window changed (round 12, perf#3). Reading
    // the launcher's revision, counted once per settled scan, runs it again
    // when the entries are there.
    readonly property string appName: {
        LauncherService.entriesRevision
        const id = HyprlandService.activeAppId
        if (!id.length) return ""
        const entry = (typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(id) : null)
            || DesktopEntries.byId(id) || DesktopEntries.byId(id.toLowerCase())
        if (entry && entry.name) return entry.name
        // No entry (a reverse-DNS id like com.microsoft.VSCode): its last part.
        const parts = id.split(".")
        return parts.length > 1 ? parts[parts.length - 1] : id
    }
    icon: HyprlandService.activeTitle.length ? "󰖯" : ""
    label: appOnly ? appName : HyprlandService.activeTitle
    // A window title is the one value that is never long enough: every step up
    // is more of it before the ellipsis, which is exactly what this widget has
    // to say. At `large` the application goes underneath, because a title
    // alone often does not name it ("Inbox (3)").
    maxLabelWidth: sizeClass === "small" ? 320 : sizeClass === "medium" ? 480 : 640
    // The application's name, worked out above, not its raw id.
    detail: appOnly ? "" : appName
    hasData: HyprlandService.activeTitle.length > 0
}
