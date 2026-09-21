import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/settings/SettingsNavLogic.js" as N

ShellRoot {
    Component.onCompleted: {
        T.eq(N.PAGES.length, 25, "all pages listed")
        T.ok(N.PAGES.every(page => typeof page.subtitle === "string" && page.subtitle.length > 0), "every page carries its own subtitle")
        T.ok(N.PAGES.every(page => !/\.$/.test(page.subtitle)), "a subtitle is a label, not a sentence")
        T.eq(N.ungroupedPages(), [], "every page is in exactly one group")
        T.eq(new Set(N.PAGES.map(page => page.id)).size, N.PAGES.length, "page ids are unique")
        T.ok(N.GROUPS.every(group => group.pages.every(id => N.pageById(id) !== null)), "groups only name known pages")
        T.ok(["appearance", "wallpaper", "desktop", "widgets", "bar", "terminal", "notifications", "weather", "calendar", "network",
              "bluetooth", "kdeConnect", "audio", "lockScreen", "power", "shortcuts", "input", "displays", "defaultApps",
              "updates", "autostart", "accounts", "login", "about"].every(id => N.pageById(id) !== null), "page ids used by IPC and the launcher stay")

        const all = N.rows("")
        T.eq(all.filter(row => row.kind === "heading").length, N.GROUPS.length, "one heading per group")
        T.eq(all[0], { kind: "heading", key: "personalization", title: "Personalization" }, "first row is a heading")
        T.eq(all[1].id, "appearance", "appearance is the first page")
        T.eq(N.pageIds(all).length, N.PAGES.length, "no query shows every page")
        T.eq(N.pageIds(all), N.GROUPS.reduce((ids, group) => ids.concat(group.pages), []), "pages follow the group order")

        const wifi = N.rows("wifi")
        T.eq(wifi.map(row => row.kind === "heading" ? "#" + row.key : row.id), ["#connectivity", "network"], "search hides empty groups")
        T.eq(N.rows("  WiFi ").length, 2, "search ignores case and outer spaces")
        T.eq(N.pageIds(N.rows("akku")), ["kdeConnect", "power"], "keywords from different groups")
        T.eq(N.pageIds(N.rows("konten")), ["accounts"], "German keyword finds the accounts page")
        T.eq(N.rows("#connectivity").length, 0, "no match gives no rows")
        T.eq(N.pageIds(N.rows("devices")), ["bluetooth", "displays", "audio", "input", "power"], "group title matches its pages")
        T.eq(N.pageIds(N.rows("lock fingerprint")), ["lockScreen"], "every word must match")
        T.eq(N.rows(undefined).length, all.length, "undefined query shows everything")

        const groups = [{ key: "a", title: "A", pages: ["x", "missing"] }, { key: "b", title: "B", pages: [] }]
        const pages = [{ id: "x", title: "X", icon: "", keywords: "" }, { id: "y", title: "Y", icon: "", keywords: "" }]
        T.eq(N.rows("", groups, pages).map(row => row.kind), ["heading", "page"], "unknown ids and empty groups are skipped")
        T.eq(N.ungroupedPages(groups, pages), ["y"], "ungrouped page is reported")

        T.eq(N.step(all, "appearance", 1), "wallpaper", "down to the next page")
        T.eq(N.step(all, "lockScreen", 1), "desktop", "down skips the heading")
        T.eq(N.step(all, "desktop", 1), "widgets", "Widgets is its own page next to Desktop")
        T.eq(N.pageIds(N.rows("widgets")), ["widgets"], "searching for widgets finds the widget page")
        T.eq(N.step(all, "desktop", -1), "lockScreen", "up skips the heading")
        T.eq(N.step(all, "appearance", -1), "appearance", "up stops at the first page")
        T.eq(N.step(all, "about", 1), "about", "down stops at the last page")
        T.eq([N.step(wifi, "appearance", 1), N.step(wifi, "appearance", -1)], ["network", "network"], "hidden current page jumps into the list")
        T.eq(N.step([], "appearance", 1), "", "no rows")
        const grouped = N.rows("")
        const personalization = grouped.filter(row => row.kind === "page" && row.group === "personalization")
        T.eq([personalization[0].first, personalization[0].last], [true, false], "the first page of a group opens its card")
        T.eq([personalization[personalization.length - 1].first, personalization[personalization.length - 1].last],
             [false, true], "the last page of a group closes it")
        const single = N.rows("", [{ key: "g", title: "G", pages: ["about"] }])
        const only = single.filter(row => row.kind === "page")
        T.eq([only.length, only[0].first, only[0].last], [1, true, true], "a group with one page opens and closes the card")

        T.finish("SettingsNavTest")
    }
}
