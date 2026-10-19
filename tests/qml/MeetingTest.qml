import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/MeetingLogic.js" as M

// Join for online meetings: which link in an event's text joins it, when the
// button shows, and what opens it. The links are invented (no real meeting).
ShellRoot {
    Component.onCompleted: {
        // ---- the link ------------------------------------------------------------
        // An Outlook invitation as its published calendar writes it: the join
        // link in angle brackets, a help link and the meeting options around it.
        const outlook = "________________\nMicrosoft Teams Need help?<https://aka.ms/JoinTeamsMeeting?omkt=en-US>\n"
            + "Join the meeting now<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d>\n"
            + "Meeting ID: 123 456\nFor organizers: Meeting options<https://teams.microsoft.com/meetingOptions/?organizerId=x>"
        const teams = M.meeting({ title: "Weekly", description: outlook })
        T.eq(teams && teams.service, "teams", "an Outlook invitation joins Teams")
        T.eq(teams && teams.url, "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d",
             "the join link, without the bracket")
        T.eq(teams && teams.label, "Join Teams", "and says what it joins")
        T.eq(M.meeting({ description: "Options<https://teams.microsoft.com/meetingOptions/?id=1> help https://aka.ms/teams" }), null,
             "the options and the help page join nothing")
        T.eq(M.meeting({ description: "New style: https://teams.microsoft.com/meet/123456789?p=abc." }).url,
             "https://teams.microsoft.com/meet/123456789?p=abc", "the short Teams link, the full stop after it dropped")
        T.eq(M.meeting({ description: "https://teams.live.com/meet/9876" }).service, "teams", "Teams for home")
        T.eq(M.meeting({ description: "Join with Google Meet: https://meet.google.com/abc-defg-hij" }).service, "meet", "Meet")
        T.eq(M.meeting({ description: "https://meet.google.com/landing" }), null, "not a meeting code")
        T.eq(M.meeting({ description: "Zoom: https://example.zoom.us/j/123456789?pwd=abc&amp;from=addon" }).url,
             "https://example.zoom.us/j/123456789?pwd=abc&from=addon", "Zoom, with a rich text's &amp; read")
        T.eq(M.meeting({ description: "https://zoom.us/support" }), null, "Zoom's other pages")
        T.eq(M.meeting({ description: "https://acme.webex.com/acme/j.php?MTID=m1" }).service, "webex", "Webex")
        T.eq(M.meeting({ location: "https://meet.google.com/abc-defg-hij", description: "" }).service, "meet",
             "a link in the location")
        T.eq(M.meeting({ title: "Call https://example.zoom.us/j/1", description: "Agenda" }).service, "zoom", "or in the title")
        T.eq(M.meeting({ description: "http://example.zoom.us/j/1" }), null, "only https")
        T.eq(M.meeting({ description: "https://evil.example/teams.microsoft.com/l/meetup-join/1" }), null,
             "a host is the host, not a path that names one")
        T.eq(M.meeting({ description: "https://teams.microsoft.com.example.com/l/meetup-join/1" }), null, "nor a lookalike")
        T.eq(M.meeting({ description: "Room 2" }), null, "no link")
        T.eq(M.meeting(null), null, "no event")
        T.eq(M.meeting({ description: "https://meet.google.com/abc-defg-hij then https://example.zoom.us/j/1" }).service,
             "meet", "the first link wins")

        // ---- when Join shows -------------------------------------------------------
        const at = (hours, minutes) => new Date(2026, 9, 19, hours, minutes || 0)
        const call = { title: "Call", description: "https://example.zoom.us/j/1", start: at(10), end: at(10, 30), allDay: false }
        T.eq([M.listJoin(call, at(9)), M.listJoin(call, at(10, 15)), M.listJoin(call, at(10, 30))], [true, true, false],
             "in a list: until it ends")
        T.eq(M.listJoin({ title: "Lunch", description: "", start: at(12), end: at(13) }, at(11)), false, "no link, no Join")
        T.eq([M.soonJoin(call, at(9, 54)), M.soonJoin(call, at(9, 55)), M.soonJoin(call, at(10, 29)), M.soonJoin(call, at(10, 30))],
             [false, true, true, false], "soon: five minutes before until the end")
        T.eq(M.soonJoin(call, at(9, 45), 15), true, "with another lead")
        T.eq(M.soonJoin(Object.assign({}, call, { allDay: true }), at(10)), false, "an all-day event is no meeting to join")
        const instant = Object.assign({}, call, { end: at(10) })
        T.eq(M.soonJoin(instant, at(10, 0)), true, "a meeting without a length still gets its minute")
        T.eq(M.nextJoin([{ title: "Lunch", start: at(10), end: at(11), description: "" }, call], at(9, 58)), call,
             "the first that offers Join")
        T.eq(M.nextJoin([call], at(8)), null, "none yet")

        // ---- what opens it -------------------------------------------------------------
        const script = name => "/repo/scripts/" + name
        const pwa = { id: "brave-abc-Default", name: "Microsoft Teams (PWA)",
                      command: ["/opt/brave-bin/brave", "--profile-directory=Default", "--app-id=abc", "%U"] }
        const other = { id: "org.kde.dolphin", name: "Dolphin", command: ["dolphin"] }
        const teamsDesktop = { id: "teams-for-linux", name: "Teams for Linux", command: ["teams-for-linux"] }
        T.eq(M.teamsApp([other, teamsDesktop, pwa]), pwa, "the Teams web app, not an app that runs no browser")
        T.eq(M.teamsApp([{ id: "brave-browser", name: "Brave", command: ["/opt/brave-bin/brave"] }]), null,
             "a browser without an app id is not Teams")
        T.eq(M.teamsApp([]), null, "no entries")
        T.eq(M.joinCommand(teams, pwa, script),
             ["/repo/scripts/launch-brave.sh", "--profile-directory=Default", "--app-id=abc",
              "--app-launch-url-for-shortcuts-menu-item=" + teams.url],
             "Teams in its web app, through the browser's launcher")
        T.eq(M.joinCommand(teams, null, script), ["xdg-open", teams.url], "Teams without the web app: the browser")
        const zoom = M.meeting(call)
        T.eq(M.joinCommand(zoom, pwa, script), ["xdg-open", zoom.url], "anything else through xdg-open")
        T.eq(M.joinCommand(null, pwa, script), null, "no meeting, nothing to run")

        T.finish("MeetingTest")
    }
}
