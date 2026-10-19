import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/NotificationLogic.js" as N

ShellRoot {
    Component.onCompleted: {
        const free = { suppressed: false, dndMode: "off" }
        const timed = { suppressed: true, dndMode: "1h" }
        const manual = { suppressed: true, dndMode: "manual" }
        const auto = { suppressed: true, dndMode: "off" }

        T.eq(N.shouldPopup(free, false), true, "nothing suppressed: a normal notification pops up")
        T.eq(N.shouldPopup(free, true), true, "nothing suppressed: a critical notification pops up")
        T.eq(N.shouldPopup(timed, false), false, "timed DND hides a normal notification")
        T.eq(N.shouldPopup(timed, true), true, "timed DND still shows a critical one")
        T.eq(N.shouldPopup(manual, true), false, "manual DND silences even a critical one")
        T.eq(N.shouldPopup(auto, false), false, "fullscreen or game suppression hides a normal one")
        T.eq(N.shouldPopup(auto, true), true, "fullscreen or game suppression lets a critical one through")

        // Per-app rules decide before the suppression state does.
        T.eq(N.shouldPopup(free, false, "mute"), false, "a muted app never pops up")
        T.eq(N.shouldPopup(free, true, "mute"), false, "not even when the sender marks it critical")
        T.eq(N.shouldPopup(timed, false, "critical"), true, "an always-urgent app gets through timed DND")
        T.eq(N.shouldPopup(manual, false, "critical"), false, "manual DND still silences everything")
        T.eq(N.shouldPopup(auto, false, "critical"), true, "and through fullscreen or game suppression")
        T.eq(N.shouldPopup(free, false, "default"), true, "no rule behaves as before")

        // A mode's (or Focus's) own manual Do Not Disturb is not the user's
        // "silence everything": "Battery very low" and "Timer done" still
        // come through it, as they do through a timed one.
        const gaming = { suppressed: true, dndMode: "manual", dndBy: "gaming" }
        T.eq(N.shouldPopup(gaming, true), true, "gaming's Do Not Disturb lets a critical one through")
        T.eq(N.shouldPopup(gaming, false), false, "and still hides a normal one")
        T.eq(N.shouldPopup(gaming, false, "critical"), true, "an always-urgent app gets through it too")
        T.eq(N.shouldPopup(gaming, true, "mute"), false, "a muted app stays muted")
        T.eq(N.shouldPopup({ suppressed: true, dndMode: "manual", dndBy: "" }, true), false,
             "the user's own manual one still silences a critical one")

        T.eq(N.appKey({ appName: "  Signal " }), "signal", "an app key is the trimmed lower-case name")
        T.eq(N.appKey({}), "__system", "a notification without an app is the system")
        T.eq(N.ruleFor({ signal: "mute" }, { appName: "Signal" }), "mute", "a rule is found by app key")
        T.eq(N.ruleFor({ signal: "nonsense" }, { appName: "Signal" }), "default", "an unknown rule falls back")
        T.eq(N.ruleFor(null, { appName: "Signal" }), "default", "no rules at all falls back")

        const history = [{ appName: "Signal", summary: "Anna", body: "see you at six" },
                         { appName: "Updates", summary: "12 packages", body: "" }]
        T.eq(N.search(history, "").length, 2, "an empty query keeps everything")
        T.eq(N.search(history, "  ").length, 2, "so does a blank one")
        T.eq(N.search(history, "signal").map(item => item.summary), ["Anna"], "the app name matches")
        T.eq(N.search(history, "PACK").map(item => item.summary), ["12 packages"], "the summary matches, ignoring case")
        T.eq(N.search(history, "at six").map(item => item.summary), ["Anna"], "the body matches")
        T.eq(N.search(history, "nothing").length, 0, "no match is no rows")

        T.eq(N.withPopup([], "a", 3), ["a"], "the first popup enters an empty queue")
        T.eq(N.withPopup(["a", "b"], "c", 3), ["a", "b", "c"], "newest popup goes last")
        T.eq(N.withPopup(["a", "b", "c"], "d", 3), ["b", "c", "d"], "the oldest popup drops out at the limit")
        T.eq(N.withPopup(["a"], "b", 0), ["b"], "a broken limit still keeps the newest")

        // The notch shows the newest of the queue, which withPopup puts last.
        T.eq(N.notchPick(["a", "b", "c"]), "c", "the notch shows the newest popup")
        T.eq([N.notchPick([]), N.notchPick(null)], [null, null], "and nothing without one")
        // A critical one first (no timer), then a normal one: the normal one
        // is shown for its time, and the critical one comes back after it.
        let notchQueue = N.withPopup([], "critical", 3)
        notchQueue = N.withPopup(notchQueue, "normal", 3)
        T.eq(N.notchPick(notchQueue), "normal", "a later notification is shown over a critical one")
        T.eq(N.notchPick(notchQueue.filter(item => item !== "normal")), "critical",
             "and when it has gone the critical one is back")

        // A notification its sender replaced in place.
        const queued = ["a", "b"]
        T.ok(N.requeue(queued, "b", true, 3) === queued, "replaced while still up: the same queue, left alone")
        T.eq(N.requeue(queued, "c", true, 3), ["a", "b", "c"], "replaced after its popup went: back as the newest")
        T.ok(N.requeue(queued, "c", false, 3) === queued, "but not when it may not pop up now")
        T.eq(N.requeue(["a", "b", "c"], "d", true, 3), ["b", "c", "d"], "within the limit")
        T.ok(N.requeue(queued, null, true, 3) === queued, "nothing replaced, nothing changed")

        T.eq(N.livePopups(["a", "b"], ["b", "c"]), ["b"], "a dismissed notification leaves the queue")
        T.eq(N.livePopups(["a"], ["a"]), ["a"], "a tracked notification stays")
        T.eq(N.livePopups(["a"], []), [], "an empty server list clears the queue")
        T.eq(N.livePopups([], ["a"]), [], "an empty queue stays empty")

        // The same queue is not assigned again: the popup stack keeps its
        // cards by identity, and the notification objects are the server's
        // own, so identity is the comparison.
        const anna = { id: 1 }
        const bob = { id: 2 }
        T.eq(N.sameSequence([anna, bob], [anna, bob]), true, "the same notifications in the same order are the same queue")
        T.eq(N.sameSequence([anna, bob], [bob, anna]), false, "the same notifications in another order are not")
        T.eq(N.sameSequence([anna, bob], [anna]), false, "nor is a queue with one fewer")
        T.eq(N.sameSequence([anna], [anna, bob]), false, "nor one with one more")
        T.eq(N.sameSequence([anna], [{ id: 1 }]), false, "a look-alike is another notification")
        T.eq(N.sameSequence([], []), true, "two empty queues are the same")
        T.eq(N.sameSequence(null, []), true, "and so is no queue at all")
        T.eq(N.sameSequence([anna, bob], N.livePopups([anna, bob], [bob, anna])), true,
             "what livePopups keeps whole is the same queue")
        T.eq(N.sameSequence([anna, bob], N.livePopups([anna, bob], [bob])), false,
             "and what it shortens is not")

        // What the notch shows for the newest popup, from the notification
        // itself: the picture by the card's route, else a bell.
        const icons = name => "/icons/" + name + ".png"
        T.eq(N.notchContent({ image: "/tmp/shot.png", appIcon: "signal", summary: "Anna", appName: "Signal", body: "six" }, icons),
             { kind: "notification", icon: "", iconSource: "/tmp/shot.png", title: "Anna", subtitle: "six", critical: false },
             "the image the notification brought comes first")
        T.eq(N.notchContent({ appIcon: "signal", summary: "Anna", appName: "Signal" }, icons).iconSource,
             "/icons/signal.png", "else the app icon, resolved by the caller")
        T.eq(N.notchContent({ appName: "Updates", body: "12 packages" }, icons),
             { kind: "notification", icon: "󰂚", iconSource: "", title: "Updates", subtitle: "12 packages", critical: false },
             "else a bell, and the app name stands in for a missing summary")
        T.eq(N.notchContent({ appIcon: "nonsense" }, name => "").icon, "󰂚",
             "an app icon that resolves to nothing is a bell too, like on the card")
        T.eq(N.notchContent(null, icons).title, "Notification", "no notification at all does not throw")
        // A critical one says so, for the notch's warning ink, and without a
        // picture it wears the card's warning sign rather than the bell.
        T.eq(N.notchContent({ appIcon: "battery-caution", summary: "Battery very low" }, icons, true).critical, true,
             "the notch is told a critical one is critical")
        T.eq(N.notchContent({ summary: "Timer done" }, name => "", true).icon, "\u{f0026}",
             "and one without a picture has the warning sign")
        T.eq(N.notchContent({ summary: "Timer done" }, name => "", false).icon, "󰂚", "a normal one keeps the bell")
        T.eq(N.picture({ image: "https://cdn.example/a.jpg", appIcon: "signal" }, icons), "/icons/signal.png",
             "a remote image is never handed to Qt: the app icon instead")
        T.eq(N.picture({ image: "HTTP://cdn.example/a.jpg" }, icons), "", "and with no app icon, nothing")
        T.eq(N.picture({ image: "file:///tmp/a.png" }, icons), "file:///tmp/a.png", "a local image stays")
        // App icons as the specification and the senders give them.
        T.eq(N.picture({ appIcon: "file:///usr/share/icons/a.png" }, icons), "file:///usr/share/icons/a.png",
             "a file:// app icon is taken as it came, not looked up as a name")
        T.eq(N.picture({ appIcon: "/opt/a #1/icon?.png" }, icons), "file:///opt/a%20%231/icon%3F.png", "an icon path is encoded")
        T.eq(N.picture({ appIcon: "/usr/share/icons/a.png" }, icons), "file:///usr/share/icons/a.png",
             "an absolute path becomes a file:// URI")
        T.eq(N.picture({ appIcon: "https://cdn.example/icon.png" }, icons), "", "a remote app icon is never fetched")
        T.eq([N.iconSource("signal", icons), N.iconSource("", icons), N.iconSource(undefined, icons)],
             ["/icons/signal.png", "", ""], "a name goes to the theme lookup, nothing stays nothing")
        T.eq(N.iconSource("FILE:///a.png", icons), "FILE:///a.png", "the scheme in any case")

        // The history's cap: the ones older than the newest `limit` go, and
        // never a popup that is on screen.
        const aged = [1, 2, 3, 4, 5, 6].map(id => ({ id: id }))
        const ids = list => list.map(item => item.id)
        T.eq(N.overflow(aged, 6, []), [], "at the cap nothing goes")
        T.eq(N.overflow(aged, 10, []), [], "under it neither")
        T.eq(ids(N.overflow(aged, 4, [])), [1, 2], "over it, the oldest, as many as it is over")
        T.eq(ids(N.overflow(aged, 4, [aged[0], aged[5]])), [2], "a popup on screen stays")
        T.eq(ids(N.overflow(aged, 4, aged.slice(0, 2))), [],
             "and nothing of the newest takes its place, the new arrival least of all")
        T.eq(ids(N.overflow(aged, 0, [])), [1, 2, 3, 4, 5, 6], "a cap of none lets every one go")
        T.eq(N.overflow(null, 4, null), [], "no history at all does not throw")
        T.eq(N.overflow(aged, 5, [{ id: 1 }]).map(item => item === aged[0]), [true],
             "the popups are told apart by identity, like the queue")

        // A second cap for the ones that hold their pixels (image data, which
        // Quickshell serves as image://qsimage/...): beyond the newest few of
        // them the older ones go too, text and files untouched.
        const pixels = id => ({ id: id, image: "image://qsimage/" + id + "/1" })
        const mixed = [pixels(1), { id: 2 }, pixels(3), { id: 4, image: "file:///tmp/a.png" }, pixels(5), pixels(6)]
        T.eq([N.carriesPixels(pixels(1)), N.carriesPixels({ image: "file:///tmp/a.png" }), N.carriesPixels({}), N.carriesPixels(null)],
             [true, false, false, false], "only image data counts as carrying pixels")
        T.eq(ids(N.overflow(mixed, 100, [], 2)), [1, 3], "beyond the newest two pictures the older ones go")
        T.eq(ids(N.overflow(mixed, 100, [], 4)), [], "within the picture cap nothing goes")
        T.eq(ids(N.overflow(mixed, 100, [mixed[0]], 2)), [3], "a popup on screen stays, picture or not")
        T.eq(ids(N.overflow(mixed, 4, [], 2)), [1, 2, 3], "both caps at once, in arrival order")
        T.eq(ids(N.overflow(mixed, 100, [], 0)), [1, 3, 5, 6], "a picture cap of none lets every picture go")
        T.eq(ids(N.overflow(mixed, 100, [])), [], "without a picture cap only the count decides, as before")

        // The unread count, from the history and the marks of what came while
        // the centre was closed: a notification closed by its ×, its action
        // or its sender takes its mark with it.
        const first = { id: 1 }
        const second = { id: 2 }
        T.eq(N.unreadCount([first, second], { 1: true, 2: true }), 2, "two came, two are unread")
        T.eq(N.unreadCount([second], { 1: true, 2: true }), 1, "one closed: one unread")
        T.eq(N.unreadCount([], { 1: true }), 0, "an empty history has nothing unread")
        T.eq(N.unreadCount([first, second], {}), 0, "nothing marked, nothing unread")
        T.eq([N.unreadCount(null, null), N.unreadCount([null], { 1: true })], [0, 0], "nothing at all does not throw")
        const marks = { 1: true, 2: true }
        T.eq(N.forHistory(marks, [second]), { 2: true }, "the marks of the ones gone are let go")
        T.ok(N.forHistory(marks, [first, second]) === marks, "and the same table when nothing went")
        T.eq(N.forHistory(null, [first]), {}, "no table at all does not throw")

        // When a card in the centre says it came.
        const noon = new Date(2026, 9, 19, 12, 0).getTime()
        T.eq(N.ageLabel(noon - 20000, noon, false), "now", "under a minute: now")
        T.eq(N.ageLabel(noon - 5 * 60000, noon, false), "5 min", "minutes under the hour")
        T.eq(N.ageLabel(new Date(2026, 9, 19, 9, 5).getTime(), noon, false), "09:05", "earlier today: the time")
        T.eq(N.ageLabel(new Date(2026, 9, 19, 9, 5).getTime(), noon, true), "9:05 AM", "on the 12-hour clock")
        T.eq(N.ageLabel(new Date(2026, 9, 18, 22, 0).getTime(), noon, false), "Yesterday", "the day before")
        T.eq(N.ageLabel(new Date(2026, 9, 18, 23, 50).getTime(), new Date(2026, 9, 19, 0, 10).getTime(), false), "20 min",
             "twenty minutes across midnight are twenty minutes")
        T.eq(N.ageLabel(new Date(2026, 9, 16, 8, 0).getTime(), noon, false), "3 days", "older ones count the days")
        T.eq([N.ageLabel(0, noon, false), N.ageLabel(undefined, noon, false)], ["", ""],
             "one carried over a restart says nothing")

        // Do Not Disturb against the wall clock. "Until 07:00 tomorrow" set at
        // 22:00 and slept through to 07:30 has run out at 07:30, whatever the
        // monotonic expiry timer still believes.
        const evening = new Date(2026, 9, 16, 22, 0).getTime()
        const seven = new Date(2026, 9, 17, 7, 0).getTime()
        const halfPast = new Date(2026, 9, 17, 7, 30).getTime()
        T.eq([N.dndActive("tomorrow", seven, evening), N.dndActive("tomorrow", seven, halfPast)], [true, false],
             "a timed mode is on until its end and off after it")
        T.eq([N.dndAfter("tomorrow", seven, evening), N.dndAfter("tomorrow", seven, halfPast)], ["tomorrow", "off"],
             "and the mode is set off once the clock says so")
        T.eq(N.dndAfter("1h", evening + 3600000, evening + 3600000), "off", "the end itself is off")
        T.eq([N.dndActive("manual", 0, halfPast), N.dndAfter("manual", 0, halfPast)], [true, "manual"],
             "manual has no end")
        T.eq([N.dndActive("off", seven, evening), N.dndAfter("off", seven, evening)], [false, "off"], "off stays off")
        T.eq(N.dndActive("bogus", seven, evening), false, "an unknown mode is not on")

        // Whose it is: a mode's name while it is on (gaming turned it on and
        // turns it off when left), "" for the user's own.
        T.eq(N.dndOwner("manual", "gaming"), "gaming", "a mode's own Do Not Disturb names the mode")
        T.eq(N.dndOwner("off", "gaming"), "", "one that is off has no owner")
        T.eq([N.dndOwner("manual", undefined), N.dndOwner("manual", "")], ["", ""], "a change without one is the user's")
        T.eq([N.dndOwner("manual", 3), N.dndOwner("manual", "Gaming!"), N.dndOwner("manual", "x".repeat(33))], ["", "", ""],
             "only a plain mode name is read back from state.json")
        T.eq([N.dndOwnerTitle("gaming"), N.dndOwnerTitle("")], ["Gaming", ""], "the label names the mode as its template does")

        // "Until tomorrow morning" ends at the next `hour` o'clock: set after
        // midnight that is this morning, not the morning after next.
        const at = (day, hour, minute) => new Date(2026, 9, day, hour, minute).getTime()
        T.eq(N.tomorrowEnd(at(19, 23, 0), 6), at(20, 6, 0), "set at 23:00: six tomorrow")
        T.eq(N.tomorrowEnd(at(20, 0, 30), 6), at(20, 6, 0), "set at 00:30: six this morning, not 29.5 hours")
        T.eq(N.tomorrowEnd(at(20, 5, 59), 6), at(20, 6, 0), "set at 05:59: still this morning")
        T.eq(N.tomorrowEnd(at(20, 6, 0), 6), at(21, 6, 0), "set at six itself: the next morning")
        T.eq(N.tomorrowEnd(at(19, 23, 0), undefined), at(20, 6, 0), "a missing hour is the setting's six")
        T.eq(N.tomorrowEnd(at(19, 23, 0), 8), at(20, 8, 0), "another hour is that hour")

        // What it says it does.
        const eleven = at(19, 23, 0)
        T.eq(N.dndLabel("off", 0, "", eleven, false), "Off", "off")
        T.eq(N.dndLabel("manual", 0, "", eleven, false), "Until turned off", "the user's own")
        T.eq(N.dndLabel("manual", 0, "gaming", eleven, false), "Until you leave Gaming", "a mode's")
        T.eq(N.dndLabel("tomorrow", at(20, 6, 0), "", eleven, false), "Until 06:00 (tomorrow)", "until tomorrow, set the evening before")
        T.eq(N.dndLabel("tomorrow", at(20, 6, 0), "", at(20, 0, 30), false), "Until 06:00",
             "after midnight the same end is today's")
        T.eq(N.dndLabel("tomorrow", at(20, 6, 0), "", eleven, true), "Until 6:00 AM (tomorrow)", "on the 12-hour clock")
        T.eq(N.dndLabel("1h", at(19, 23, 30), "", eleven, false), "Until 23:30", "an hour")
        T.eq(N.dndLabel("1h", at(19, 22, 0), "", eleven, false), "Off", "one that has run out is off")

        // What a start reads back from state.json: a reboot ends a manual
        // one; a mode's is named so the mode in use can take it back.
        T.eq(N.dndAtBoot("manual", "gaming", "boot-a", "boot-a"), { mode: "manual", by: "gaming", ended: "" },
             "a shell restart keeps a mode's own")
        T.eq(N.dndAtBoot("manual", "gaming", "boot-a", "boot-b"), { mode: "off", by: "", ended: "gaming" },
             "a reboot ends it and says whose it was")
        T.eq(N.dndAtBoot("manual", "", "boot-a", "boot-b"), { mode: "off", by: "", ended: "" },
             "a reboot ends the user's own for good")
        T.eq(N.dndAtBoot("tomorrow", "", "boot-a", "boot-b"), { mode: "tomorrow", by: "", ended: "" },
             "a timed one keeps its clock time")
        T.eq(N.dndAtBoot("bogus", "gaming", "boot-a", "boot-a"), { mode: "off", by: "", ended: "" }, "an unknown mode is off")
        T.eq(N.dndAtBoot("manual", "Gaming!", undefined, "boot-b"), { mode: "off", by: "", ended: "" },
             "only a plain mode name is taken back")

        T.finish("NotificationPopupTest")
    }
}
