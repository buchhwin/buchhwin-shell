.pragma library

// Pure helpers for Open-Meteo (https://open-meteo.com, no API key). The
// service owns processes and state; everything here is unit tested.

var forecastEndpoint = "https://api.open-meteo.com/v1/forecast"
var geocodeEndpoint = "https://geocoding-api.open-meteo.com/v1/search"

// Two decimals (~1 km) are plenty for a forecast and keep requests coarse.
function roundCoordinate(value) {
    return Math.round(Number(value) * 100) / 100
}

function validCoordinates(lat, lon) {
    return typeof lat === "number" && typeof lon === "number" && isFinite(lat) && isFinite(lon)
        && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 && !(lat === 0 && lon === 0)
}

function forecastUrl(lat, lon, unit) {
    const params = [
        "latitude=" + roundCoordinate(lat),
        "longitude=" + roundCoordinate(lon),
        "current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day",
        "hourly=temperature_2m,precipitation_probability,weather_code,is_day",
        "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max",
        "timezone=auto",
        "forecast_days=7",
        "wind_speed_unit=kmh",
        "temperature_unit=" + (unit === "fahrenheit" ? "fahrenheit" : "celsius")
    ]
    return forecastEndpoint + "?" + params.join("&")
}

function geocodeUrl(name) {
    return geocodeEndpoint + "?name=" + encodeURIComponent(String(name).trim()) + "&count=8&language=en&format=json"
}

// Open-Meteo returns local wall-clock times ("2026-09-16T20:45") for the
// requested timezone. Parse the parts explicitly instead of relying on engine
// specific Date string parsing.
function parseLocalTime(text) {
    const match = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/.exec(String(text || ""))
    if (!match) return null
    return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]),
                    Number(match[4] || 0), Number(match[5] || 0))
}

// WMO weather interpretation codes -> English label and Nerd Font icon.
var conditions = {
    0: { label: "Clear sky", day: "󰖙", night: "󰖔" },
    1: { label: "Mainly clear", day: "󰖕", night: "󰼱" },
    2: { label: "Partly cloudy", day: "󰖕", night: "󰼱" },
    3: { label: "Overcast", day: "󰖐", night: "󰖐" },
    45: { label: "Fog", day: "󰖑", night: "󰖑" },
    48: { label: "Freezing fog", day: "󰖑", night: "󰖑" },
    51: { label: "Light drizzle", day: "󰖗", night: "󰖗" },
    53: { label: "Drizzle", day: "󰖗", night: "󰖗" },
    55: { label: "Heavy drizzle", day: "󰖗", night: "󰖗" },
    56: { label: "Freezing drizzle", day: "󰙿", night: "󰙿" },
    57: { label: "Freezing drizzle", day: "󰙿", night: "󰙿" },
    61: { label: "Light rain", day: "󰖗", night: "󰖗" },
    63: { label: "Rain", day: "󰖖", night: "󰖖" },
    65: { label: "Heavy rain", day: "󰖖", night: "󰖖" },
    66: { label: "Freezing rain", day: "󰙿", night: "󰙿" },
    67: { label: "Freezing rain", day: "󰙿", night: "󰙿" },
    71: { label: "Light snow", day: "󰖘", night: "󰖘" },
    73: { label: "Snow", day: "󰼶", night: "󰼶" },
    75: { label: "Heavy snow", day: "󰼶", night: "󰼶" },
    77: { label: "Snow grains", day: "󰖘", night: "󰖘" },
    80: { label: "Light rain showers", day: "󰼳", night: "󰖗" },
    81: { label: "Rain showers", day: "󰖖", night: "󰖖" },
    82: { label: "Violent rain showers", day: "󰖖", night: "󰖖" },
    85: { label: "Snow showers", day: "󰼴", night: "󰖘" },
    86: { label: "Heavy snow showers", day: "󰼶", night: "󰼶" },
    95: { label: "Thunderstorm", day: "󰖓", night: "󰖓" },
    96: { label: "Thunderstorm with hail", day: "󰙾", night: "󰙾" },
    99: { label: "Thunderstorm with hail", day: "󰙾", night: "󰙾" }
}

function condition(code, isDay) {
    const entry = conditions[code]
    if (!entry) return { label: "Unknown", icon: "󰖐" }
    return { label: entry.label, icon: isDay === false ? entry.night : entry.day }
}

function numberAt(list, index) {
    const value = list ? list[index] : undefined
    return typeof value === "number" && isFinite(value) ? value : null
}

// Normalised model used by the UI. Throws on anything that is not a usable
// forecast so the service can keep its previous data.
function parseForecast(json, now) {
    const data = typeof json === "string" ? JSON.parse(json) : json
    if (!data || typeof data !== "object") throw new Error("empty forecast")
    if (data.error) throw new Error("provider error")
    const current = data.current
    const hourly = data.hourly
    const daily = data.daily
    if (!current || typeof current.temperature_2m !== "number" || !hourly || !Array.isArray(hourly.time)
            || !daily || !Array.isArray(daily.time))
        throw new Error("incomplete forecast")

    const currentIsDay = current.is_day !== 0
    const currentCondition = condition(current.weather_code, currentIsDay)
    const reference = now instanceof Date ? now : (parseLocalTime(current.time) || new Date())
    const hourStart = new Date(reference.getFullYear(), reference.getMonth(), reference.getDate(), reference.getHours())

    const hours = []
    for (let i = 0; i < hourly.time.length; ++i) {
        const time = parseLocalTime(hourly.time[i])
        if (!time || time < hourStart) continue
        const code = numberAt(hourly.weather_code, i)
        const cond = condition(code, numberAt(hourly.is_day, i) !== 0)
        hours.push({
            time: time,
            temperature: numberAt(hourly.temperature_2m, i),
            precipitation: numberAt(hourly.precipitation_probability, i),
            code: code,
            label: cond.label,
            icon: cond.icon
        })
        if (hours.length >= 48) break
    }

    const days = []
    for (let i = 0; i < daily.time.length; ++i) {
        const date = parseLocalTime(daily.time[i])
        if (!date) continue
        const code = numberAt(daily.weather_code, i)
        const cond = condition(code, true)
        days.push({
            date: date,
            max: numberAt(daily.temperature_2m_max, i),
            min: numberAt(daily.temperature_2m_min, i),
            precipitation: numberAt(daily.precipitation_probability_max, i),
            uv: numberAt(daily.uv_index_max, i),
            sunrise: parseLocalTime(daily.sunrise ? daily.sunrise[i] : null),
            sunset: parseLocalTime(daily.sunset ? daily.sunset[i] : null),
            code: code,
            label: cond.label,
            icon: cond.icon
        })
    }

    const today = days.length ? days[0] : null
    return {
        current: {
            temperature: current.temperature_2m,
            feelsLike: typeof current.apparent_temperature === "number" ? current.apparent_temperature : null,
            humidity: typeof current.relative_humidity_2m === "number" ? current.relative_humidity_2m : null,
            wind: typeof current.wind_speed_10m === "number" ? current.wind_speed_10m : null,
            code: current.weather_code,
            isDay: currentIsDay,
            label: currentCondition.label,
            icon: currentCondition.icon,
            precipitation: hours.length ? hours[0].precipitation : null,
            uv: today ? today.uv : null,
            max: today ? today.max : null,
            min: today ? today.min : null
        },
        hourly: hours,
        daily: days
    }
}

// Every n-th hour for compact strips.
function sampleHours(hours, step, count) {
    const result = []
    for (let i = 0; i < hours.length && result.length < count; i += step) result.push(hours[i])
    return result
}

function parseGeocode(json) {
    const data = typeof json === "string" ? JSON.parse(json) : json
    const results = data && Array.isArray(data.results) ? data.results : []
    return results
        .filter(item => item && typeof item.name === "string" && validCoordinates(item.latitude, item.longitude))
        .map(item => ({
            name: item.name,
            region: [item.admin1, item.country].filter(part => typeof part === "string" && part.length).join(", "),
            lat: roundCoordinate(item.latitude),
            lon: roundCoordinate(item.longitude)
        }))
}

function formatTemperature(value) {
    if (typeof value !== "number" || !isFinite(value)) return "–"
    const rounded = Math.round(value)
    return (rounded === 0 ? 0 : rounded) + "°"
}

// Hours from the start of the current hour on (cached data ages).
function upcomingHours(hours, now) {
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours())
    return (hours || []).filter(hour => hour.time && hour.time >= start)
}

// Serialisable cache (Dates become ISO strings and back). `key` identifies the
// location and unit the forecast belongs to.
function toCache(model, updated, key) {
    return JSON.stringify({ version: 1, key: key, updated: updated.getTime(), model: model })
}

function fromCache(text) {
    const data = JSON.parse(text)
    if (!data || data.version !== 1 || !data.model || typeof data.key !== "string") throw new Error("unknown cache")
    const revive = value => value ? new Date(value) : null
    const model = data.model
    for (const hour of model.hourly || []) hour.time = revive(hour.time)
    for (const day of model.daily || []) {
        day.date = revive(day.date)
        day.sunrise = revive(day.sunrise)
        day.sunset = revive(day.sunset)
    }
    return { key: data.key, updated: new Date(data.updated), model: model }
}
