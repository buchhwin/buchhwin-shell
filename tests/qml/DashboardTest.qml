import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/dashboard/DashboardLogic.js" as D
import "../../services/LayoutLogic.js" as L

// The dashboard's cards: the catalogue, and the surface they sit on - which is
// the control center's surface with a different catalogue, so the point of
// most of this is that the shared operations really are shared.
ShellRoot {
    function types(dashboard) { return L.dashboardTypes(dashboard) }

    Component.onCompleted: {
        // ---- the catalogue --------------------------------------------------
        T.eq(D.label("calendar"), "Month", "a card has a name")
        T.eq(D.label("nonsense"), "nonsense", "an unknown type is its own name")
        T.eq([D.isKnown("agenda"), D.isKnown("nonsense")], [true, false], "known and not")
        T.ok(D.catalogue.every(card => card.icon.length > 0), "every card has an icon for the picker")
        // A start size that cannot be stored is not a start size: the layout
        // file clamps every cell to GRID_MAX_H, so nothing may begin above it.
        T.ok(D.catalogue.every(card => card.h >= 1 && card.h <= L.GRID_MAX_H),
             "no card starts taller than a layout file can hold")
        T.ok(D.catalogue.every(card => card.w >= 1 && card.w <= L.GRID_MAX_W),
             "nor wider")
        // Not in the table means a desktop widget the dashboard accepts, and a
        // widget is a line, not a card: one 64 px row, not three.
        T.eq(D.size("cpu"), { w: 1, h: 1 }, "a widget starts one row tall")

        // ---- the surface ----------------------------------------------------
        const d = L.defaultDashboard()
        T.eq(types(d), ["clock", "weather", "calendar", "agenda", "events"], "the dashboard it starts with")
        T.ok(types(d).every(type => D.isKnown(type)), "and every one of them is in the catalogue")
        T.eq(L.dashboardItems(d)[0].id, "dashboard-1", "ids are the surface's own")
        T.eq([L.dashboardItems(d)[0].w, L.dashboardItems(d)[0].h], [1, 2], "a card is stored with its size")

        // Sanitizing: the same rules the control center's tiles get.
        T.eq(types(L.sanitizeDashboard(null)), types(d), "nothing becomes the default")
        T.eq(types(L.sanitizeDashboard({ dashboard: [] })), types(d), "and so does an empty one")
        T.eq(L.sanitizeDashboard({ dashboard: [{ id: "a", items: [{ type: "clock" }, { type: "weather" }] }] })
              .dashboard[0].items.length, 1, "one card per pill")

        // Move, remove, add and resize, and none of them touches what it was given.
        const moved = L.moveDashboardCardTo(d, L.dashboardItems(d)[0].id, 3)
        T.eq(types(moved), ["weather", "calendar", "agenda", "clock", "events"], "a card is moved to an index")
        T.eq(types(d), ["clock", "weather", "calendar", "agenda", "events"], "the original is never changed")
        const without = L.removeDashboardCard(d, L.dashboardItems(d)[1].id)
        T.eq(types(without), ["clock", "calendar", "agenda", "events"], "a card is taken off")
        T.eq(types(L.addDashboardCard(without, "weather")),
             ["clock", "calendar", "agenda", "events", "weather"], "and comes back at the end")
        T.eq(types(L.addDashboardCard(d, "weather")), types(d), "one that is already there is not added twice")
        T.eq(types(L.addDashboardCard(d, "")), types(d), "nor is nothing")
        const sized = L.setDashboardCardSize(d, L.dashboardItems(d)[0].id, 2, 4)
        T.eq([L.dashboardItems(sized)[0].w, L.dashboardItems(sized)[0].h], [2, 4], "a corner dragged out")
        T.eq(L.dashboardItems(L.setDashboardCardSize(d, L.dashboardItems(d)[0].id, 99, 99))[0].h,
             L.GRID_MAX_H, "never past the grid")
        T.eq(L.dashboardItems(L.setDashboardCardSize(d, "nothing", 2, 2))[0],
             L.dashboardItems(d)[0], "an unknown id changes nothing")

        // The picker offers what is not on it. A fresh dashboard is not the
        // whole catalogue: `media` and `system` are there to be added, not to
        // arrive with seven cards already on the screen.
        T.eq(D.missing(types(d)).map(card => card.type), ["media", "system"],
             "a default dashboard still has the two readouts to offer")
        T.eq(D.missing([]).length, D.catalogue.length, "an empty one can have everything back")
        T.eq(D.missing(["clock"]).map(card => card.type),
             ["weather", "calendar", "agenda", "events", "media", "system"], "and the rest in catalogue order")
        T.eq(D.missing(D.catalogue.map(card => card.type)).length, 0, "a dashboard with everything offers nothing")

        // The two new ones, and the reason their start sizes are not the
        // control center's: a row is 30 px there and 64 here.
        T.eq(D.size("media"), { w: 1, h: 3 }, "a player opens three rows tall, not the quick panel's five")
        T.eq(D.size("system"), { w: 1, h: 3 }, "and so do the three meters")
        T.eq(D.minSize("media"), { w: 1, h: 2 },
             "a player at one row is not a smaller player, it is not a player")
        T.eq(D.minSize("system"), { w: 1, h: 2 }, "and one meter is not a readout")
        T.ok(D.catalogue.every(card => card.h <= 6), "nothing starts above the grid's own ceiling")

        // The two surfaces are the same surface: their ids never collide and
        // neither one's operations reach into the other.
        const config = L.sanitize({ configVersion: 2, profiles: { minimal: {} } })
        const profile = config.profiles.minimal
        T.ok(profile.dashboard !== undefined && profile.quick !== undefined,
             "a profile carries both surfaces")
        T.eq(types(profile.dashboard), types(d), "the dashboard is filled in like the tiles are")
        T.ok(L.dashboardItems(profile.dashboard).every(card => card.id.indexOf("dashboard-") === 0),
             "and its ids are its own")

        // A card that names a floor cannot be pulled below it, and one that
        // does not goes down to a single step. A month grid below four rows
        // is a strip of numbers with no month in it.
        T.eq(D.minSize("calendar"), { w: 1, h: 4 }, "the month grid names its own floor")
        T.eq(D.minSize("agenda"), { w: 1, h: 4 }, "and so does the week")
        T.eq(D.minSize("clock"), { w: 1, h: 1 }, "the clock is happy at a single step")
        T.eq(D.minSize("nothing at all"), { w: 1, h: 1 }, "and an unknown card has no floor to keep")
        const month = L.dashboardItems(L.setDashboardCardSize(d, "dashboard-3", 1, 1))
            .find(card => card.type === "calendar")
        T.eq([month.w, month.h], [1, 4], "squashing the month grid stops at the floor")
        // Every start size is still inside the grid, and not below its own
        // floor either - a start size that is clamped on the first write is
        // not a start size.
        T.ok(D.catalogue.every(card => card.h <= 6 && card.w <= 4
                               && card.h >= D.minSize(card.type).h
                               && card.w >= D.minSize(card.type).w),
             "every card starts inside the grid and above its own floor")

        // A surface takes a desktop widget beside its own tiles, but only one
        // the caller vouches for: the widget registry is a QML singleton and
        // the layout library cannot see it, so the guard is a callback.
        const knows = type => type === "cpu" || type === "clock"
        const withWidget = L.addDashboardCard(d, "cpu", knows)
        T.eq(types(withWidget).slice(-1), ["cpu"], "a widget the caller knows is taken")
        T.eq(types(L.addDashboardCard(d, "cpu")), types(d), "and refused without the callback")
        T.eq(types(L.addDashboardCard(d, "not a widget", knows)), types(d), "as is one it does not know")
        T.eq(types(L.addDashboardCard(withWidget, "cpu", knows)), types(withWidget), "and never twice")

        T.finish("DashboardTest")
    }
}
