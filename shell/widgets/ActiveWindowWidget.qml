import QtQuick
import qs.shell.widgets
import qs.services
WidgetBase {
    icon: HyprlandService.activeTitle.length ? "󰖯" : ""
    label: HyprlandService.activeTitle
    // A window title is the one value that is never long enough: every step up
    // is more of it before the ellipsis, which is exactly what this widget has
    // to say. At `large` the application goes underneath, because a title
    // alone often does not name it ("Inbox (3)").
    maxLabelWidth: sizeClass === "small" ? 320 : sizeClass === "medium" ? 480 : 640
    detail: HyprlandService.activeAppId
    hasData: HyprlandService.activeTitle.length > 0
}
