import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.dashboard

// Weather pill/widget: the dashboard's weather card (current conditions,
// hourly strip, seven days) in a narrower panel.
PopupPanel {
    id: root
    panelId: "weatherPopup"
    // Two columns only once there is a place to show the weather for. Weather
    // turned off or no place set is one line and a button, which sat alone in
    // a card 660 px wide. Decided on the place, not on the data, so the card
    // does not widen under the reader when a forecast arrives.
    cardWidth: WeatherService.status === "noLocation" || WeatherService.status === "disabled"
        ? Metrics.popupWidth : Metrics.popupSplitWidth
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
