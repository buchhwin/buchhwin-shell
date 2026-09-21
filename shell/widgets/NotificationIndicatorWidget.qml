import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
WidgetBase {
    id: root
    icon: NotificationService.dndActive ? "󰂛" : NotificationService.unread > 0 ? "󰂞" : "󰂚"
    iconColor: NotificationService.unread > 0 && !NotificationService.dndActive ? Colors.accentForeground : root.textColor
    label: NotificationService.unread > 0 ? String(NotificationService.unread) : ""
    name: "Notifications"
    detail: NotificationService.dndActive ? NotificationService.dndLabel
        : NotificationService.unread > 0 ? "unread" : "nothing new"
}
