import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/time/SunLogic.js" as S

// Sunrise and sunset for the theme's "Sunset to sunrise". Moments are given
// and compared in UTC, so the machine's time zone does not decide the
// answers; the reference times are the almanac's (NOAA's calculator) to the
// minute, and the equation is held to three. Places are big cities rounded
// to two decimals, nobody's home (testing.md pitfall 17).
ShellRoot {
    Component.onCompleted: {
        const minutes = 3 * 60000
        const near = (actual, expected, message) =>
            T.ok(actual instanceof Date && Math.abs(actual.getTime() - expected) <= minutes,
                 message + ": expected ~" + new Date(expected).toISOString() + ", got "
                 + (actual instanceof Date ? actual.toISOString() : String(actual)))

        // ---- one day ------------------------------------------------------------
        // A city at 52.52 N, 13.40 E (Berlin's latitude): long June days,
        // short December ones.
        const june = S.sunTimes(2026, 5, 21, 52.52, 13.40)
        near(june.sunrise, Date.UTC(2026, 5, 21, 2, 43), "midsummer sunrise at 52.5 N")
        near(june.sunset, Date.UTC(2026, 5, 21, 19, 33), "midsummer sunset")
        const december = S.sunTimes(2026, 11, 21, 52.52, 13.40)
        near(december.sunrise, Date.UTC(2026, 11, 21, 7, 16), "midwinter sunrise")
        near(december.sunset, Date.UTC(2026, 11, 21, 14, 54), "midwinter sunset")
        T.eq([june.polar, december.polar], ["", ""], "no polar day there")
        // The equinox: twelve hours and a little (refraction).
        const march = S.sunTimes(2026, 2, 20, 0.00, 0.00)
        T.ok(march.sunset - march.sunrise > 12 * 3600000 && march.sunset - march.sunrise < 12.2 * 3600000,
             "about twelve hours on the equator at the equinox")
        // The south: December is summer there. Sunrise falls on the day before
        // in UTC, and that is right.
        const south = S.sunTimes(2026, 11, 21, -33.87, 151.21)
        near(south.sunrise, Date.UTC(2026, 11, 20, 18, 41), "southern summer sunrise, east of Greenwich")
        near(south.sunset, Date.UTC(2026, 11, 21, 9, 5), "and its sunset")
        // The west.
        const west = S.sunTimes(2026, 5, 21, 40.71, -74.01)
        near(west.sunrise, Date.UTC(2026, 5, 21, 9, 25), "sunrise west of Greenwich")
        near(west.sunset, Date.UTC(2026, 5, 22, 0, 31), "its sunset after midnight UTC")

        // ---- polar days and nights ------------------------------------------------
        T.eq(S.sunTimes(2026, 11, 21, 69.65, 18.96).polar, "night", "midwinter in the far north: no sunrise")
        T.eq(S.sunTimes(2026, 5, 21, 69.65, 18.96).polar, "day", "midsummer there: no sunset")
        T.eq(S.sunTimes(2026, 5, 21, 69.65, 18.96).sunrise, null, "and no times")
        T.eq(S.sunTimes(2026, 5, 21, 95, 0).polar, "", "no place, no answer")
        T.eq(S.sunTimes(2026, 5, 21, NaN, 0).sunrise, null, "nor for NaN")

        // ---- night or day now ---------------------------------------------------------
        const at = (month, day, hours, minutes) => new Date(Date.UTC(2026, month, day, hours, minutes || 0))
        T.eq(S.state(at(11, 21, 12), 52.52, 13.40).night, false, "a winter noon is day")
        T.eq(S.state(at(11, 21, 16), 52.52, 13.40).night, true, "a winter 16:00 UTC (17:00 there) is night")
        T.eq(S.state(at(5, 21, 19), 52.52, 13.40).night, false, "a summer 19:00 UTC (21:00 there) is still day")
        T.eq(S.state(at(5, 21, 1), 52.52, 13.40).night, true, "a summer 01:00 UTC is night")
        T.eq(S.state(at(11, 21, 12), 69.65, 18.96).night, true, "the polar night is night at noon")
        T.eq(S.state(at(5, 21, 0), 69.65, 18.96).night, false, "the polar day is day at midnight")
        T.eq(S.state(at(5, 21, 12), 69.65, 18.96).next, null, "and has no change in the next days")
        T.eq(S.state(at(5, 21, 12), 100, 0), null, "no state for no place")
        T.eq(S.state(new Date(NaN), 52.52, 13.40), null, "nor for no time")

        // The next change, whatever the day: before sunrise it is the sunrise,
        // between them the sunset, after the sunset the next day's sunrise.
        near(S.state(at(11, 21, 5), 52.52, 13.40).next, Date.UTC(2026, 11, 21, 7, 16), "before sunrise: the sunrise")
        near(S.state(at(11, 21, 12), 52.52, 13.40).next, Date.UTC(2026, 11, 21, 14, 54), "by day: the sunset")
        near(S.state(at(11, 21, 20), 52.52, 13.40).next, Date.UTC(2026, 11, 22, 7, 16), "after sunset: tomorrow's sunrise")
        // Far east of the shell's zone: the place's day and the shell's need
        // not be the same one, and the last change decides.
        T.eq(S.state(at(11, 21, 0), -33.87, 151.21).night, false, "11:00 there is day, whatever the zone here")
        T.eq(S.state(at(11, 21, 12), -33.87, 151.21).night, true, "23:00 there is night")

        // ---- waiting --------------------------------------------------------------------
        const now = at(11, 21, 12)
        T.eq(S.wait(now, new Date(now.getTime() + 60000), 3600000), 61000, "a second past the change")
        T.eq(S.wait(now, new Date(now.getTime() + 7200000), 3600000), 3600000, "never longer than the cap")
        T.eq(S.wait(now, null, 3600000), 3600000, "no change: the cap")
        T.eq(S.wait(now, new Date(now.getTime() - 5000), 3600000), 1000, "at least a second")
        T.eq(S.wait(now, null), 12 * 3600000, "twelve hours by default")

        T.finish("SunTest")
    }
}
