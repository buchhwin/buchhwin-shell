import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/SourceLogic.js" as S
import "../../services/notifications/NotificationLogic.js" as N

// Where a notification comes from (SourceLogic) and what NotificationLogic
// makes of it: a browser's sites as apps of their own (Teams and Outlook
// apart, not one "Brave"), their names and web app entries, the stored
// rules split once, and the "always" rule beside the others.
ShellRoot {
    Component.onCompleted: {
        const teams = { id: 1, appName: "Brave", desktopEntry: "brave-browser", summary: "Anna", body: "Lunch?",
                        hints: { "x-kde-origin-name": "teams.microsoft.com" } }
        const outlook = { id: 2, appName: "Brave", desktopEntry: "brave-browser", summary: "Mail", body: "",
                          hints: { "x-kde-origin-name": "https://outlook.office.com/mail/" } }
        const github = { id: 3, appName: "Brave", desktopEntry: "brave-browser", summary: "PR", body: "",
                         hints: { "x-kde-origin-name": "github.com" } }
        const plainBrave = { id: 4, appName: "Brave", desktopEntry: "brave-browser", summary: "Download done", hints: {} }
        const feed = { id: 5, appName: "Akregator", summary: "New article", hints: { "x-kde-origin-name": "example.org" } }
        const signal = { id: 6, appName: "Signal", summary: "Bob" }

        // Browsers by their entry or their name.
        T.eq([S.isBrowser(teams), S.isBrowser({ appName: "Google Chrome" }), S.isBrowser({ desktopEntry: "chromium.desktop" }),
              S.isBrowser(feed), S.isBrowser(signal), S.isBrowser(null)],
             [true, true, true, false, false, false], "browsers are known by entry or name")

        // The host an origin names.
        T.eq(S.originHost("teams.microsoft.com"), "teams.microsoft.com", "a bare host")
        T.eq(S.originHost("https://Teams.Microsoft.com/v2/?x=1"), "teams.microsoft.com", "scheme, case and path go")
        T.eq(S.originHost("teams.microsoft.com:443"), "teams.microsoft.com", "a port goes")
        T.eq(S.originHost("www.example.org"), "example.org", "and a leading www.")
        T.eq(S.originHost("localhost:8080"), "localhost", "localhost is a host")
        T.eq([S.originHost("Bitwarden"), S.originHost(""), S.originHost("two words.com"), S.originHost(undefined)],
             ["", "", "", ""], "words, nothing and spaces are no host")

        // The listed web apps on every host they answer on.
        T.eq(S.webApp("teams.cloud.microsoft").id, "teams", "Teams on its new domain")
        T.eq(S.webApp("eu.teams.microsoft.com").id, "teams", "and under its old one")
        T.eq(S.webApp("outlook.office365.com").id, "outlook", "Outlook on office365")
        T.eq([S.webApp("github.com"), S.webApp("notteams.microsoft.com"), S.webApp("")], [null, null, null],
             "anything else is none, a lookalike too")

        // The site part of the key.
        T.eq([S.site(teams), S.site(outlook), S.site(github), S.site(plainBrave), S.site(feed)],
             ["teams", "outlook", "github.com", "", ""], "a browser's sites, by web app or by host")

        // The key the rules and the groups go by.
        T.eq([N.appKey(teams), N.appKey(outlook), N.appKey(github), N.appKey(plainBrave), N.appKey(feed), N.appKey(signal)],
             ["brave:teams", "brave:outlook", "brave:github.com", "brave", "akregator", "signal"],
             "Teams and Outlook are two apps, a site without a hint stays Brave's, other senders keep their name")

        // Names.
        T.eq([S.label(teams, ""), S.label(teams, "Microsoft Teams (PWA)"), S.label(github, ""), S.label(feed, ""),
              S.label(plainBrave, "")],
             ["Microsoft Teams", "Microsoft Teams (PWA)", "github.com", "Akregator", "Brave"],
             "the installed entry's name, else the listed name, else the host; others their own")
        T.eq([S.originNote(feed), S.originNote(teams), S.originNote(signal)], ["example.org", "", ""],
             "another sender's origin is a note beside its name")
        T.eq([S.nameForKey("brave:teams"), S.nameForKey("brave:github.com"), S.nameForKey("signal"), S.nameForKey("__system")],
             ["Microsoft Teams", "github.com", "Signal", "System"], "a key reads as a name without the history")

        // Groups and search with the sites apart.
        const groups = N.group([teams, outlook, github, plainBrave])
        T.eq(groups.map(entry => [entry.key, entry.name]),
             [["brave", "Brave"], ["brave:github.com", "github.com"], ["brave:outlook", "Outlook"], ["brave:teams", "Microsoft Teams"]],
             "four groups, newest first, each named for its site")
        const described = N.group([teams], item => ({ name: "Microsoft Teams (PWA)", icon: "/apps/teams.png" }))
        T.eq([described[0].name, described[0].icon], ["Microsoft Teams (PWA)", "/apps/teams.png"],
             "a describer names a group and gives its icon")
        T.eq(N.search([teams, outlook, signal], "teams").map(item => item.id), [1], "\"teams\" finds Teams' messages")
        T.eq(N.search([teams, outlook, signal], "office.com").map(item => item.id), [2], "and a host finds its site's")

        // Rules: "always" beside the others, the split keys.
        T.eq(N.ruleFor({ "brave:teams": "always", brave: "mute" }, teams), "always", "Teams has a rule of its own")
        T.eq(N.ruleFor({ "brave:teams": "always", brave: "mute" }, outlook), "default", "and Outlook does not share it")
        T.eq(N.ruleFor({ "brave:teams": "always", brave: "mute" }, plainBrave), "mute", "Brave's own still holds for the rest")
        T.eq([N.isRule("always"), N.isRule("critical"), N.isRule("mute"), N.isRule("default"), N.isRule("loud")],
             [true, true, true, false, false], "the rules there are")
        T.eq(N.nextAppRule("always"), "default", "the centre's bell takes an always app back to normal")
        const manualOwn = { suppressed: true, dndMode: "manual", dndBy: "" }
        T.eq([N.shouldPopup(manualOwn, false, "always"), N.shouldPopup(manualOwn, true, "critical"),
              N.shouldPopup({ suppressed: true, dndMode: "off" }, false, "always")],
             [true, false, true], "always gets through the user's own Do Not Disturb and the automatic muting")
        T.eq(N.ruleRows({ "brave:teams": "always" }, [], null).map(row => [row.key, row.name, row.rule]),
             [["brave:teams", "Microsoft Teams", "always"]], "a stored site rule is listed by its web app's name")
        T.eq(N.ruleRows({}, [teams, signal], item => item.appName === "Brave" ? { name: "Microsoft Teams (PWA)" } : null)
                 .map(row => row.name), ["Microsoft Teams (PWA)", "Signal"], "the history's names come from the describer")

        // The one-time split of a stored browser rule.
        const before = { brave: "mute", signal: "critical" }
        const split = S.migrateRules(before, undefined)
        T.eq(split, { rules: { brave: "mute", signal: "critical", "brave:teams": "mute", "brave:outlook": "mute" }, version: 2 },
             "a Brave rule from before goes to Teams and Outlook too")
        T.eq(before, { brave: "mute", signal: "critical" }, "without changing what it was given")
        T.eq(S.migrateRules({ brave: "mute", "brave:teams": "always" }, 1).rules["brave:teams"], "always",
             "a site's own rule is kept")
        const done = { brave: "mute" }
        T.ok(S.migrateRules(done, 2).rules === done, "once migrated, nothing more")
        T.ok(S.migrateRules({ signal: "mute" }, 0).rules.signal === "mute", "no browser rule, nothing to split")
        T.eq(S.migrateRules({ signal: "mute" }, 0).version, 2, "and it is marked done all the same")

        // The installed web app and its window.
        const entries = [
            { id: "org.kde.dolphin", name: "Dolphin", execString: "dolphin %u" },
            { id: "chrome-abc-Default", name: "Outlook (PWA)", execString: "/opt/google/chrome/chrome --app-id=abc" },
            { id: "brave-faol-Default", name: "Outlook (PWA)", execString: "/opt/brave-bin/brave --profile-directory=Default --app-id=faol %U",
              startupClass: "crx_faol", icon: "/icons/outlook.png" },
            { id: "brave-ompi-Default", name: "Microsoft Teams (PWA)", execString: "/opt/brave-bin/brave --app-id=ompi %U",
              startupClass: "crx_ompi" }
        ]
        T.eq(S.findEntry(entries, S.webAppById("outlook"), "brave").id, "brave-faol-Default", "the sending browser's own entry first")
        T.eq(S.findEntry(entries, S.webAppById("outlook"), "vivaldi").id, "chrome-abc-Default", "else any browser's")
        T.eq(S.findEntry(entries, S.webAppById("teams"), "brave").id, "brave-ompi-Default", "Teams by its name")
        T.eq(S.findEntry([entries[0]], S.webAppById("teams"), "brave"), null, "not installed is none")
        T.eq(S.findEntry(entries, null, "brave"), null, "and no web app is none")
        const windows = [{ address: "55aa", appId: "code" }, { address: "0x77BB", appId: "crx_ompi" },
                         { address: "99cc", appId: "brave-faol-Default" }]
        T.eq(S.windowFor(windows, entries[3]), "0x77bb", "an XWayland window by its StartupWMClass")
        T.eq(S.windowFor(windows, entries[2]), "0x99cc", "a Wayland one by the entry's id")
        T.eq(S.windowFor([{ address: "nothex", appId: "crx_ompi" }], entries[3]), "", "a broken address is none")
        T.eq(S.windowFor(windows, null), "", "no entry, no window")

        // What the notch shows while the screen is shared: no words, no
        // sender's picture.
        const avatar = { summary: "Anna", body: "Lunch?", image: "/tmp/avatar.png", appIcon: "brave-browser" }
        const open = N.notchContent(avatar, name => "image://icon/" + name, false, false)
        const hidden = N.notchContent(avatar, name => "image://icon/" + name, false, true)
        T.eq([open.subtitle, open.iconSource], ["Lunch?", "/tmp/avatar.png"], "the notch shows the words and the picture")
        T.eq([hidden.title, hidden.subtitle, hidden.iconSource], ["Anna", "", "image://icon/brave-browser"],
             "concealed: the title and the app's icon only")

        // The shell's own notices stay in the queue when the server's list
        // changes; dismissed notifications still leave.
        const notice = { internal: true, summary: "3 notifications while Do Not Disturb was on" }
        T.eq(N.livePopups([teams, notice, outlook], [outlook]).map(item => item.summary),
             ["3 notifications while Do Not Disturb was on", "Mail"], "a notice is in no server's list and stays")

        T.finish("NotificationSourceTest")
    }
}
