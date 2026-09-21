import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.dashboard

// Weather pill/widget: the dashboard's weather card (current conditions,
// hourly strip, seven days) in a narrower panel.
PopupPanel {
    id: root
    panelId: "weatherPopup"
    cardWidth: Metrics.popupSplitWidth
    heading: "Weather"
    detail: WeatherService.locationName + (WeatherService.updatedText.length
        ? (WeatherService.status === "stale" ? " · Offline, updated " : " · Updated ") + WeatherService.updatedText : "")
    glyph: WeatherService.current ? WeatherService.current.icon : "󰖐"
    // No footer: this popup is the dashboard's weather card, so "Open
    // dashboard" offered the thing that was already on screen.

    body: WeatherCard {
        showLocation: false
        wide: true
        Component.onCompleted: WeatherService.track()
        Component.onDestruction: WeatherService.untrack()
    }
}
