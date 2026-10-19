import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/SavedLogic.js" as S
import "../../services/notifications/NotificationLogic.js" as N

// The history kept across a shell restart (SavedLogic): what a record keeps
// and what it never does, the file's text both ways, a reload's live
// notifications told from earlier ones, and earlier ones as NotificationLogic
// and a card see them.
ShellRoot {
    Component.onCompleted: {
        const live = { id: 12, appName: "Brave", appIcon: "brave-browser", desktopEntry: "brave-browser",
                       summary: "Anna", body: "Lunch?", urgency: 1, image: "image://qsimage/12/0",
                       actions: [{ identifier: "default" }], hints: { "x-kde-origin-name": "teams.microsoft.com" } }
        const kept = S.record(live, 1760000000000, "teams.microsoft.com")
        T.eq(kept, { id: 12, appName: "Brave", appIcon: "brave-browser", desktopEntry: "brave-browser", summary: "Anna",
                     body: "Lunch?", urgency: 1, time: 1760000000000, origin: "teams.microsoft.com" },
             "app, title, text, when and the site; no picture, no actions")
        T.eq(S.record({ appIcon: "image://qsimage/3/1", summary: "x" }, 0, "").appIcon, "", "sent pixels are not kept")
        T.eq(S.record({ appIcon: "https://example.org/a.png", summary: "x" }, 0, "").appIcon, "", "nor a web url")
        T.eq(S.record({ appIcon: "/usr/share/icons/a.png", summary: "x" }, 0, "").appIcon, "/usr/share/icons/a.png", "a path is")
        const capped = S.record({ summary: "s".repeat(400), body: "b".repeat(3000), urgency: 7 }, -5, "")
        T.eq([capped.summary.length, capped.body.length, capped.urgency, capped.time, capped.origin],
             [300, 2000, 2, 0, undefined], "long words cut, urgency in range, no time, no origin")

        // The file's text.
        const text = S.serialize([kept])
        T.eq(S.parse(text), [kept], "written and read back")
        T.eq([S.parse(""), S.parse("{"), S.parse("[]"), S.parse('{"items": 3}')], [[], [], [], []], "anything unreadable is nothing")
        T.eq(S.parse('{"items": [{"appName": "A", "summary": ""}, {"appName": 3, "summary": "x"}, {"appName": "B", "summary": "ok"}]}')
                 .map(item => item.appName), ["B"], "records without words or with the wrong shape are dropped")
        const many = []
        for (let index = 0; index < 60; ++index) many.push(S.record({ id: index, appName: "A", summary: "n" + index }, index + 1, ""))
        T.eq(S.parse(S.serialize(many)).length, 50, "at most fifty")
        T.eq(S.parse(S.serialize(many))[0].summary, "n10", "the newest fifty")

        // What a write holds.
        const a = S.record({ id: 1, appName: "A", summary: "a" }, 1, "")
        const b = S.record({ id: 2, appName: "B", summary: "b" }, 2, "")
        const c = S.record({ id: 3, appName: "C", summary: "c" }, 3, "")
        T.eq(S.merge([a], [b, c]).map(item => item.summary), ["a", "b", "c"], "earlier first, then the live history")
        T.eq(S.merge(many, [c]).length, 50, "the newest fifty of both")

        // A start: a reload's carried-over notification is no earlier one.
        const parts = S.split([a, b, c], [{ id: 2, summary: "b" }, { id: 3, summary: "another" }])
        T.eq(parts.earlier.map(item => item.summary), ["a", "c"], "the same id and title is the live one")
        T.eq(parts.times, { 2: 2 }, "which gets its arrival back")
        T.eq(S.split([a], []).earlier.length, 1, "after a restart every one is earlier")
        T.eq(S.without([a, b, c], b).map(item => item.summary), ["a", "c"], "a dismissed one leaves")

        // Earlier ones as items.
        const items = S.earlierItems([a, b, kept, S.record({ id: 1, appName: "A", summary: "again" }, 1, "")])
        T.eq(items.map(item => item.id), ["earlier-1-1", "earlier-2-2", "earlier-1760000000000-12", "earlier-1-1-1"],
             "ids that stay, and a second with the same time and id told apart")
        T.eq([items[2].earlier, items[2].actions, items[2].image, items[2].time, items[2].source === kept],
             [true, [], "", 1760000000000, true], "nothing to act on, no picture, its time, and what it came from")
        T.eq(N.appKey(items[2]), "brave:teams", "keyed as the live one was: by its site")
        T.eq(N.search(items, "lunch").map(item => item.summary), ["Anna"], "and searched the same way")

        T.finish("NotificationSavedTest")
    }
}
