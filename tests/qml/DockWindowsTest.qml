import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/dock/DockLogic.js" as D
import "../../services/dock/BadgeLogic.js" as B
import "../../services/dock/PreviewLogic.js" as P

// What the dock reads off its windows beyond their class: a Citrix session's
// desktop from its title (DockLogic.citrixEntryFor), a web app's unread count
// from its title and the unread notifications per app (BadgeLogic), the
// streams the wheel turns, and where the strip of an app's windows stands
// (PreviewLogic).
ShellRoot {
    function entry(id, name, startupClass) { return { id: id, name: name || id, startupClass: startupClass || "", icon: id } }

    Component.onCompleted: {
        // ---- a pinned Citrix desktop and its session -----------------------------------------
        const rds = entry("Citrix_subscribed_Store.RDS-Office $S1-2", "RDS-Office", "RDS-Office")
        const test = entry("Citrix_subscribed_Store.RDS-Office-2 $S3-4", "RDS-Office-2", "RDS-Office-2")
        const lab = entry("Citrix_subscribed_Store.LAB $S5-6", "LAB", "LAB")
        const engine = entry("wfica", "Citrix Workspace Engine", "Wfica")
        const citrix = [rds, test, lab]
        T.ok(D.isCitrixEntry(["Application", "Citrix-subscribed"]) && !D.isCitrixEntry(["Network"]) && !D.isCitrixEntry(null),
             "a subscribed desktop by its category")
        T.ok(D.isCitrixSession("Wfica") && D.isCitrixSession("wfica") && !D.isCitrixSession("Wfica2"), "a session by its class")
        T.eq([D.citrixEntryFor("RDS-Office", citrix), D.citrixEntryFor("RDS-Office - Desktop Viewer", citrix),
              D.citrixEntryFor("rds-office-2", citrix), D.citrixEntryFor("LAB", citrix)], [rds.id, rds.id, test.id, lab.id],
             "the desktop the title starts with, in any case")
        T.eq([D.citrixEntryFor("LABRADOR", citrix), D.citrixEntryFor("Citrix Workspace", citrix), D.citrixEntryFor("", citrix),
              D.citrixEntryFor("My RDS-Office", citrix)], ["", "", "", ""], "a whole word at the start, or nothing")
        T.eq([D.citrixEntryFor("RDS-Office-2", [entry("a", "RDS", "RDS")]), D.citrixEntryFor("RDS-Office.x", citrix)], ["", ""],
             "\"RDS\" is not \"RDS-Office-2\": a hyphen or a dot goes on with the name")
        T.eq(D.citrixEntryFor("RDS-Office-2 x", [entry("a", "RDS-Office", "RDS-Office"), test]), test.id, "the one the whole name fits")
        const look = cls => String(cls).toLowerCase() === "wfica" ? engine : null
        const byId = id => citrix.find(item => item.id === id) || null
        const session = { address: "0x1", appClass: "Wfica", seq: 1, workspace: 1, workspaceName: "1", entryHint: rds.id }
        let items = D.build([rds], [session], look, { resolve: D.resolver([rds], look, byId) })
        T.eq(items.map(item => [item.key, item.pinned, item.running]), [["app:" + rds.id, true, true]],
             "the pin lights up for its session, and no second icon")
        T.eq(D.clickTarget(items[0], "", []), { action: "focus", address: "0x1" }, "and a click focuses the session instead of starting another")
        items = D.build([], [session], look, { resolve: D.resolver([], look, byId) })
        T.eq([items[0].key, items[0].name], ["app:" + rds.id, "RDS-Office"], "unpinned, the session is its desktop's app, not the engine")
        items = D.build([], [Object.assign({}, session, { entryHint: "" })], look, { resolve: D.resolver([], look, byId) })
        T.eq(items[0].key, "app:wfica", "a Wfica window that names no desktop is the engine's, as before")
        items = D.build([], [Object.assign({}, session, { entryHint: "gone" })], look, { resolve: D.resolver([], look, byId) })
        T.eq(items[0].key, "app:wfica", "and so is one whose desktop is not there")
        const two = D.build([], [session, Object.assign({}, session, { address: "0x2", seq: 2, entryHint: lab.id })], look,
                            { resolve: D.resolver([], look, byId) })
        T.eq(two.map(item => item.key), ["app:" + rds.id, "app:" + lab.id], "two desktops, two apps - the class alone would be one")
        T.eq(D.resolve("Wfica", [rds], look).key, "app:wfica", "resolve() without a hint is unchanged")

        // ---- unread counts ------------------------------------------------------------------------
        T.ok(B.isWebApp("crx_ompifgpmddkgmclendfeacglnodjjndh"), "a web app under X11")
        T.ok(B.isWebApp("brave-ompifgpmddkgmclendfeacglnodjjndh-Default"), "and under Wayland")
        T.ok(!B.isWebApp("brave-browser") && !B.isWebApp("code") && !B.isWebApp(""), "not the browser, not any app")
        T.eq([B.titleBadge("(3) Chat | Microsoft Teams"), B.titleBadge("(12+) Inbox"), B.titleBadge("(1)"),
              B.titleBadge("Chat | Microsoft Teams"), B.titleBadge("Inbox (3)"), B.titleBadge("(x) a"), B.titleBadge("(3)a")],
             [3, 12, 1, 0, 0, 0, 0], "a count at the start of the title")
        const history = [{ id: 1, desktopEntry: "org.kde.kdeconnect.app.desktop", appName: "KDE Connect" },
                         { id: 2, desktopEntry: "", appName: "Microsoft Teams" },
                         { id: 3, desktopEntry: "", appName: "Microsoft Teams" },
                         { id: 4, desktopEntry: "", appName: "Microsoft Teams" }]
        const counts = B.unseenByApp(history, { 1: true, 2: true, 3: true })
        T.eq(counts, { "org.kde.kdeconnect.app": 1, "kde connect": 1, "microsoft teams": 2 },
             "the unread ones per app, by entry and by name - a read one does not count")
        const teams = { entryId: "brave-ompifgpmddkgmclendfeacglnodjjndh-Default", name: "Microsoft Teams (PWA)",
                        windows: [{ appClass: "crx_ompifgpmddkgmclendfeacglnodjjndh", badge: 0 }] }
        T.eq(B.notificationBadge(teams, counts), 2, "a web app's notifications by its name without \"(PWA)\"")
        T.eq(B.notificationBadge({ entryId: "org.kde.kdeconnect.app", name: "KDE Connect", windows: [] }, counts), 1,
             "one counted under its entry and its name is one")
        T.eq(B.itemBadge(Object.assign({}, teams, { windows: [{ badge: 5 }, { badge: 3 }] }), counts), 5,
             "the title's count first, the largest of its windows'")
        T.eq(B.itemBadge(teams, counts), 2, "else its notifications")
        T.eq(B.itemBadge({ entryId: "x", name: "X", windows: [] }, counts), 0, "else none")
        T.eq([B.badgeText(0), B.badgeText(7), B.badgeText(99), B.badgeText(150), B.badgeText(undefined)], ["", "7", "99", "99+", ""],
             "what the badge says")

        // ---- the wheel: an app's streams ----------------------------------------------------------
        const spotify = { entryId: "spotify", name: "Spotify", windows: [{ appClass: "Spotify" }] }
        T.ok(B.streamMatches(spotify, "spotify", { appName: "spotify", binary: "spotify" }), "an app's stream by its binary")
        T.ok(B.streamMatches({ entryId: "org.mozilla.firefox", name: "Firefox", windows: [] }, "", { name: "Firefox" }),
             "by the node's own name, before it is bound")
        T.ok(B.streamMatches(teams, "brave", { appName: "Brave", binary: "brave" }),
             "a web app's sound is its browser's: the wheel over Teams turns Brave")
        T.ok(!B.streamMatches(spotify, "spotify", { appName: "Firefox", binary: "firefox" }), "never another app's")
        T.eq([B.volumeNotice(0.454), B.volumeNotice(1.2), B.volumeNotice(-1), B.volumeNotice(null)],
             ["Volume 45%", "Volume 100%", "Nothing playing", "Nothing playing"], "what the icon says")
        T.eq(B.VOLUME_STEP, 0.05, "a notch is a volume key's step")
        T.eq([D.optionValue("badges", "true"), D.optionValue("previews", "false"), D.optionValue("wheelVolume", "yes")], [true, false, null],
             "dock setOption badges, previews, wheelVolume")

        // ---- the strip of an app's windows ----------------------------------------------------------
        T.ok(P.wanted(true, { windows: [{}] }) && !P.wanted(false, { windows: [{}] }) && !P.wanted(true, { windows: [] })
             && !P.wanted(true, { special: "settings", windows: [] }) && !P.wanted(true, null),
             "the windows for an app that has some, with the previews on")
        const card = { width: 200, height: 160 }
        T.eq(P.stripSize(2, card, 8, 8, 6), { width: 424, height: 176 }, "two cards")
        T.eq(P.stripSize(9, card, 8, 8, 6), P.stripSize(6, card, 8, 8, 6), "at most six wide; more scroll")
        T.eq(P.stripSize(0, card, 8, 8, 6), P.stripSize(1, card, 8, 8, 6), "never less than one")
        const screen = { width: 1920, height: 1200 }
        const bottom = P.surfaceSize("bottom", card, 8, 8, 6, screen, 8)
        T.eq(bottom, { width: 1256, height: 184 }, "the surface: the widest strip and the bridge below it")
        T.eq(P.surfaceSize("bottom", card, 8, 8, 6, { width: 900, height: 1440 }, 8).width, 900, "never wider than the screen")
        T.eq(P.surfaceSize("left", card, 8, 8, 6, screen, 8), { width: 1264, height: 176 }, "beside a side dock, the bridge beside it")
        const body = { x: 0, y: 1148, width: 1920, height: 52 }
        const strip = P.stripSize(2, card, 8, 8, 6)
        let at = P.place("bottom", { x: 900, y: 1154, width: 40, height: 40 }, body, bottom, strip, screen, 8)
        T.eq([at.x, at.y, at.stripX, at.stripY], [292, 964, 416, 0], "above the dock, against its body, the strip centred on the icon")
        T.eq(at.mask, { x: 416, y: 0, width: 424, height: 184 }, "the input: the strip and the bridge down to the dock")
        T.eq(at.x + at.stripX + strip.width / 2, 920, "the strip's middle is the icon's")
        at = P.place("bottom", { x: 4, y: 1154, width: 40, height: 40 }, body, bottom, strip, screen, 8)
        T.eq([at.x, at.stripX], [0, 0], "the first app on a taskbar: kept on the screen")
        at = P.place("bottom", { x: 1876, y: 1154, width: 40, height: 40 }, body, bottom, strip, screen, 8)
        T.eq([at.x + bottom.width, at.x + at.stripX + strip.width], [1920, 1920], "the last one too")
        const side = P.surfaceSize("left", card, 8, 8, 6, screen, 8)
        at = P.place("left", { x: 6, y: 500, width: 40, height: 40 }, { x: 0, y: 200, width: 52, height: 800 }, side, strip, screen, 8)
        T.eq([at.x, at.y, at.stripX, at.stripY], [52, 432, 8, 0], "beside a left dock, centred on the icon across")
        T.eq(at.mask, { x: 0, y: 0, width: 432, height: 176 }, "the bridge to its left")
        at = P.place("right", { x: 1874, y: 500, width: 40, height: 40 }, { x: 1868, y: 200, width: 52, height: 800 }, side, strip, screen, 8)
        T.eq([at.x, at.x + at.stripX + strip.width + 8], [604, 1868], "beside a right dock, the strip against it")
        at = P.place("left", { x: 6, y: 1150, width: 40, height: 40 }, { x: 0, y: 200, width: 52, height: 1000 }, side, strip, screen, 8)
        T.eq(at.y + side.height, 1200, "kept on the screen at the bottom")
        T.eq([P.grown("bottom", body, 24), P.grown("left", { x: 0, y: 200, width: 52, height: 800 }, 24),
              P.grown("right", { x: 1868, y: 200, width: 52, height: 800 }, 24), P.grown("bottom", body, 0), P.grown("bottom", null, 24)],
             [{ x: 0, y: 1124, width: 1920, height: 76 }, { x: 0, y: 200, width: 76, height: 800 },
              { x: 1844, y: 200, width: 76, height: 800 }, body, null],
             "a magnifying dock: its icons grow towards the screen, nothing more without magnification")
        at = P.place("bottom", { x: 900, y: 1154, width: 40, height: 40 }, P.grown("bottom", body, 24), bottom, strip, screen, 8)
        T.eq(at.y + bottom.height, 1124, "the strip and its bridge end where the magnified icons begin")

        T.finish("DockWindowsTest")
    }
}
