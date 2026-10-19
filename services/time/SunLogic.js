.pragma library

// When the sun rises and sets at a place, for the theme's "Sunset to sunrise"
// (Settings > Appearance, SunService). "Automatic" was a fixed 19:00 to
// 07:00, which in December is two hours after dark and in June two hours
// before it, while Night Light already followed the sun at the weather place
// - through gammastep, which does its own sums and tells nobody.
//
// The sunrise equation as NOAA and most almanacs write it: the day's solar
// transit at the place's longitude, the sun's declination that day, and the
// hour angle at which its centre is 0.833° below the horizon (refraction and
// the sun's radius, the official sunrise). Good to about a minute at the
// latitudes people live at, which is more than a theme needs.
//
// Times are moments (Date), not clock readings: the shell's time zone and
// the place's need not be the same one - a laptop carried abroad keeps its
// zone until someone changes it - so whether it is night is decided by the
// last sunrise or sunset before now, not by "today's" two times.

var J1970 = 2440587.5
var J2000 = 2451545.0
var DAY_MS = 86400000
var RAD = Math.PI / 180
// The sun's centre at sunrise and sunset, in degrees above the horizon.
var HORIZON = -0.833
// The tilt of the Earth's axis, in degrees.
var OBLIQUITY = 23.4397

function validPlace(lat, lon) {
    return typeof lat === "number" && typeof lon === "number" && isFinite(lat) && isFinite(lon)
        && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
}

function fromJulian(julian) {
    return new Date(Math.round((julian - J1970) * DAY_MS))
}

// Sunrise and sunset on one calendar day (year, month 0-11, day): the day's
// transit is the one nearest noon UTC of that date shifted by the longitude,
// so it falls on that date in the place's own solar time.
// { sunrise, sunset } as Dates, or both null with `polar` "day" (the sun
// stays up) or "night" (it does not come up).
function sunTimes(year, month, day, lat, lon) {
    if (!validPlace(lat, lon)) return { sunrise: null, sunset: null, polar: "" }
    const days = Math.round(Date.UTC(year, month, day, 12) / DAY_MS + J1970 - J2000)
    // Mean solar time at the place (east positive), its mean anomaly, the
    // equation of the centre and the ecliptic longitude.
    const mean = days - lon / 360
    const anomaly = ((357.5291 + 0.98560028 * mean) % 360 + 360) % 360
    const m = anomaly * RAD
    const centre = 1.9148 * Math.sin(m) + 0.02 * Math.sin(2 * m) + 0.0003 * Math.sin(3 * m)
    const ecliptic = ((anomaly + centre + 180 + 102.9372) % 360) * RAD
    const transit = J2000 + mean + 0.0053 * Math.sin(m) - 0.0069 * Math.sin(2 * ecliptic)
    const declination = Math.asin(Math.sin(ecliptic) * Math.sin(OBLIQUITY * RAD))
    const phi = lat * RAD
    const cosHour = (Math.sin(HORIZON * RAD) - Math.sin(phi) * Math.sin(declination))
        / (Math.cos(phi) * Math.cos(declination))
    if (cosHour < -1) return { sunrise: null, sunset: null, polar: "day" }
    if (cosHour > 1) return { sunrise: null, sunset: null, polar: "night" }
    const half = Math.acos(cosHour) / (2 * Math.PI)
    return { sunrise: fromJulian(transit - half), sunset: fromJulian(transit + half), polar: "" }
}

// Every sunrise and sunset from two days before `now`'s date to two days
// after, in order: { at: Date, kind: "rise" | "set" }. Five days are enough
// for any time zone the shell can be in against any place on Earth.
function events(now, lat, lon) {
    const list = []
    for (let offset = -2; offset <= 2; ++offset) {
        const times = sunTimes(now.getFullYear(), now.getMonth(), now.getDate() + offset, lat, lon)
        if (times.sunrise) list.push({ at: times.sunrise, kind: "rise" })
        if (times.sunset) list.push({ at: times.sunset, kind: "set" })
    }
    return list.sort((a, b) => a.at - b.at)
}

// Where the sun is at `now`: { night, next, sunrise, sunset }.
// - night: after the last sunset and before the next sunrise; in a polar day
//   or night (no sunrise or sunset nearby at all) what that day is;
// - next: the next sunrise or sunset, null when there is none in the next
//   two days (the caller looks again later);
// - sunrise, sunset: the ones of `now`'s calendar day, for Settings to show
//   (null on a polar day or night).
// null for a place that is no place.
function state(now, lat, lon) {
    if (!(now instanceof Date) || isNaN(now.getTime()) || !validPlace(lat, lon)) return null
    const list = events(now, lat, lon)
    let last = null
    let next = null
    for (const event of list) {
        if (event.at <= now) last = event
        else if (!next) next = event
    }
    const today = sunTimes(now.getFullYear(), now.getMonth(), now.getDate(), lat, lon)
    const night = last ? last.kind === "set" : today.polar === "night"
    return { night: night, next: next ? next.at : null, sunrise: today.sunrise, sunset: today.sunset,
             polar: today.polar }
}

// How long to wait before looking again: until the next sunrise or sunset,
// a second past it (a timer can end a frame early - testing.md pitfall 133 -
// and the look after it must find the change done), and never longer than
// `cap` ms, so a polar season, a changed time zone or a moved place is
// noticed within that. At least a second.
function wait(now, next, cap) {
    const limit = Math.max(1000, Number(cap) || 12 * 3600 * 1000)
    if (!(next instanceof Date) || !(now instanceof Date)) return limit
    return Math.max(1000, Math.min(limit, next.getTime() - now.getTime() + 1000))
}
