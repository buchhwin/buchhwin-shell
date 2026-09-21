import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/weather/WeatherLogic.js" as W

ShellRoot {
    FileView { id: forecast; path: Qt.resolvedUrl("../fixtures/openmeteo-forecast.json").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        // Requests
        T.eq(W.roundCoordinate(52.51998), 52.52, "coordinates round to two decimals")
        T.eq(W.roundCoordinate(-0.004), -0, "tiny negative rounds to zero")
        const url = W.forecastUrl(52.519, 13.404, "celsius")
        T.ok(url.indexOf("latitude=52.52&longitude=13.4&") > 0, "forecast url uses rounded coordinates")
        T.ok(url.indexOf("temperature_unit=celsius") > 0, "celsius unit")
        T.ok(W.forecastUrl(1, 2, "fahrenheit").indexOf("temperature_unit=fahrenheit") > 0, "fahrenheit unit")
        T.ok(W.forecastUrl(1, 2, "kelvin").indexOf("temperature_unit=celsius") > 0, "unknown unit falls back to celsius")
        T.ok(W.geocodeUrl(" Frankfurt am Main&x=1 ").indexOf("name=Frankfurt%20am%20Main%26x%3D1&") > 0, "geocode query is encoded and trimmed")
        T.ok(W.validCoordinates(52.52, 13.4), "valid coordinates")
        T.ok(!W.validCoordinates(0, 0), "null island means unset")
        T.ok(!W.validCoordinates(91, 0), "latitude range")
        T.ok(!W.validCoordinates("52", 13), "strings are not coordinates")

        // Conditions: every WMO code has an English label and day/night icon.
        const codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        T.ok(codes.every(code => W.condition(code, true).label !== "Unknown" && W.condition(code, false).icon.length > 0), "all WMO codes mapped")
        T.eq(W.condition(0, true).label, "Clear sky", "clear label")
        T.ok(W.condition(0, true).icon !== W.condition(0, false).icon, "clear sky has a night icon")
        T.eq(W.condition(12345, true).label, "Unknown", "unknown code")

        // Parsing
        const now = new Date(2026, 2, 10, 14, 45)
        const model = W.parseForecast(forecast.text(), now)
        T.eq(model.current.temperature, 8.4, "current temperature")
        T.eq(model.current.feelsLike, 5.9, "feels like")
        T.eq(model.current.label, "Overcast", "current condition")
        T.eq(model.current.humidity, 71, "humidity")
        T.eq(model.current.max, 10.2, "today's max from daily")
        T.eq(model.current.uv, 2.4, "today's uv")
        T.eq(model.hourly[0].time.getHours(), 14, "hourly starts at the current hour")
        T.eq(model.current.precipitation, model.hourly[0].precipitation, "current rain chance from current hour")
        T.eq(model.hourly.length, 34, "remaining fixture hours are kept")
        T.eq(model.daily.length, 7, "seven days")
        T.eq(model.daily[1].date.getDate(), 11, "daily dates are local days")
        T.eq(model.daily[0].sunrise.getHours(), 6, "sunrise parsed")
        T.eq(model.daily[6].max, null, "missing values become null")
        T.eq(model.daily[6].label, "Unknown", "unknown daily code")
        T.eq(W.sampleHours(model.hourly, 3, 8).map(hour => hour.time.getHours()), [14, 17, 20, 23, 2, 5, 8, 11], "three-hour samples")
        T.eq(W.upcomingHours(model.hourly, new Date(2026, 2, 10, 20, 10))[0].time.getHours(), 20, "cached hours age out")

        T.throwsError(() => W.parseForecast("{not json"), "broken json")
        T.throwsError(() => W.parseForecast({ error: true, reason: "x" }), "provider error")
        T.throwsError(() => W.parseForecast({ current: {} }), "incomplete forecast")

        // Cache round trip keeps dates and key.
        const cached = W.fromCache(W.toCache(model, now, "52.52/13.4/celsius"))
        T.eq(cached.key, "52.52/13.4/celsius", "cache key")
        T.eq(cached.updated.getTime(), now.getTime(), "cache timestamp")
        T.ok(cached.model.hourly[0].time instanceof Date && cached.model.hourly[0].time.getHours() === 14, "cached hour dates revived")
        T.ok(cached.model.daily[0].sunset instanceof Date, "cached daily dates revived")
        T.throwsError(() => W.fromCache(JSON.stringify({ version: 2 })), "unknown cache version")

        // Geocoding
        const places = W.parseGeocode({ results: [
            { name: "Berlin", admin1: "Land Berlin", country: "Deutschland", latitude: 52.52437, longitude: 13.41053 },
            { name: "Kaputt", latitude: "x", longitude: 1 },
            { name: "Ohne Region", latitude: 1.5, longitude: 2.5 }
        ] })
        T.eq(places.length, 2, "invalid places dropped")
        T.eq(places[0], { name: "Berlin", region: "Land Berlin, Deutschland", lat: 52.52, lon: 13.41 }, "place normalised and rounded")
        T.eq(places[1].region, "", "missing region")
        T.eq(W.parseGeocode({}).length, 0, "no results")

        T.eq(W.formatTemperature(-0.4), "0°", "no negative zero")
        T.eq(W.formatTemperature(17.6), "18°", "rounded temperature")
        T.eq(W.formatTemperature(null), "–", "missing temperature")
        T.finish("WeatherTest")
    }
}
