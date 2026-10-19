import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/LinkLogic.js" as L

// Calendars from a link: which links are taken, what goes to the helper and
// what comes back. Invented links on reserved names (example.com, .test).
ShellRoot {
    Component.onCompleted: {
        // ---- the link ------------------------------------------------------------
        T.eq(L.normalize("  https://calendar.example.com/a/b.ics  "),
             { ok: true, url: "https://calendar.example.com/a/b.ics", error: "" }, "an https link, trimmed")
        T.eq(L.normalize("webcal://calendar.example.com/a.ics").url, "https://calendar.example.com/a.ics", "webcal is https")
        T.eq(L.normalize("webcals://calendar.example.com/a.ics").url, "https://calendar.example.com/a.ics", "webcals too")
        T.eq(L.normalize("HTTPS://Calendar.Example.com/a.ics").url, "https://Calendar.Example.com/a.ics",
             "the scheme in lower case, the rest as given")
        T.eq(L.normalize("http://calendar.example.com/a.ics").ok, false, "plain http is refused")
        T.ok(/https/.test(L.normalize("http://calendar.example.com/a.ics").error), "and says what is taken")
        T.eq(L.normalize("").ok, false, "nothing pasted")
        T.eq(L.normalize("ftp://calendar.example.com/a.ics").ok, false, "another scheme")
        T.eq(L.normalize("https://calendar.example.com/a b.ics").ok, false, "a space")
        T.eq(L.normalize("https:///a.ics").ok, false, "no server")
        T.eq(L.normalize("https://user:secret@calendar.example.com/a.ics").ok, false, "a password in the link")
        T.eq(L.normalize("https://calendar.example.com/" + "a".repeat(5000)).ok, false, "too long")
        T.eq(L.normalize(undefined).ok, false, "no text at all")

        // ---- names ------------------------------------------------------------------
        T.eq(L.hostOf("https://outlook.office365.com/owa/calendar/x/y/calendar.ics"), "outlook.office365.com", "the host")
        T.eq(L.hostOf("https://user@Calendar.Example.com:8443/a"), "calendar.example.com", "without user and port")
        T.eq(L.hostOf("webcal://calendar.example.com/a"), "", "only of an https link")
        T.eq(L.defaultName("https://outlook.office365.com/owa/calendar/x/calendar.ics"), "Outlook", "Outlook's published calendar")
        T.eq(L.defaultName("https://calendar.google.com/calendar/ical/x/basic.ics"), "Google", "Google's secret address")
        T.eq(L.defaultName("https://cal.example.test/a.ics"), "cal.example.test", "any other: its host")
        T.eq(L.nameFor("  Work\nmeetings ", "https://cal.example.test/a.ics"), "Work meetings", "one line")
        T.eq(L.nameFor("", "https://outlook.office365.com/a.ics"), "Outlook", "no name: the default")
        T.eq(L.nameFor("x".repeat(100), "https://cal.example.test/a.ics").length, 80, "at most 80 characters")

        // ---- the request ------------------------------------------------------------
        T.eq(JSON.parse(L.addRequest("webcal://outlook.office365.com/owa/calendar/a/calendar.ics", "")),
             { url: "https://outlook.office365.com/owa/calendar/a/calendar.ics", name: "Outlook", refreshMinutes: 15 },
             "what the helper is handed on stdin")
        T.eq(L.addRequest("http://cal.example.test/a.ics", "x"), null, "nothing for a refused link")
        T.eq([L.validId("akonadi_ical_resource_3"), L.validId("akonadi_ical_resource_"), L.validId("akonadi_maildir_resource_0"),
              L.validId("akonadi_ical_resource_1; rm"), L.validId(4)], [true, false, false, false, false], "resource ids")

        // ---- the answers --------------------------------------------------------------
        const listed = L.parseAnswer(0, JSON.stringify({ ok: true, calendars: [
            { id: "akonadi_ical_resource_1", name: "Outlook", host: "outlook.office365.com", status: 0, online: true, message: "Ready" },
            { id: "akonadi_ical_resource_2", name: " ", host: "cal.example.test", status: 2, online: true, message: "Could not load the file." },
            { id: "akonadi_ical_resource_3", name: "Away", host: "", status: 1, online: false, message: "" },
            { id: "../etc", name: "bad" }, null] }))
        T.eq(listed.ok, true, "a list")
        T.eq(listed.calendars.map(row => row.id), ["akonadi_ical_resource_1", "akonadi_ical_resource_2", "akonadi_ical_resource_3"],
             "rows with a resource id only")
        T.eq(listed.calendars[0].subtitle, "outlook.office365.com · Read-only · updated every 15 minutes", "an idle one")
        T.eq(listed.calendars[1].name, "Calendar", "a blank name")
        T.eq(listed.calendars[1].subtitle, "cal.example.test · Could not load the file.", "a broken one says why")
        T.eq(listed.calendars[2].subtitle, "Offline", "an offline one")
        T.eq(L.parseAnswer(1, JSON.stringify({ ok: false, reason: "notRunning" })).message.indexOf("Akonadi") >= 0, true,
             "a refusal in words")
        T.eq(L.parseAnswer(1, JSON.stringify({ ok: false, error: "Akonadi refused the calendar." })).message,
             "Akonadi refused the calendar.", "the helper's own words win")
        T.eq(L.parseAnswer(0, JSON.stringify({ ok: true, id: "akonadi_ical_resource_7" })).id, "akonadi_ical_resource_7",
             "the new calendar's id")
        T.eq(L.parseAnswer(1, JSON.stringify({ ok: true })).ok, false, "a failed exit is no success")
        T.eq(L.parseAnswer(127, "").message, "python3 is missing.", "no python")
        T.eq(L.parseAnswer(0, "not json").reason, "noAnswer", "no answer")

        T.finish("CalendarLinkTest")
    }
}
