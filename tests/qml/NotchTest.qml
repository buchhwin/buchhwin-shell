import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notch/NotchLogic.js" as N
import "../../services/LayoutLogic.js" as L

ShellRoot {
    Component.onCompleted: {
        const at = (h, m) => new Date(2026, 8, 17, h, m || 0)
        const now = at(14, 30)

        // Time text
        T.eq(N.timeText(at(9, 5)), "09:05", "time is zero padded")
        T.eq(N.timeText(at(23, 59)), "23:59", "24-hour time")

        // Next event
        const events = [
            { title: "Holiday", start: at(0), end: new Date(2026, 8, 18), allDay: true },
            { title: "Done", start: at(9), end: at(10), allDay: false },
            { title: "Later", start: at(17), end: at(18), allDay: false },
            { title: "Soon", start: at(14, 45), end: at(15, 15), allDay: false }
        ]
        T.eq(N.nextEvent(events, now).title, "Soon", "earliest upcoming timed event")
        T.eq(N.nextEvent(events.concat([{ title: "Running", start: at(14), end: at(15), allDay: false }]), now).title, "Running", "running event first")
        T.eq(N.nextEvent([events[0], events[1]], now).title, "Holiday", "all-day event when nothing timed is left")
        T.eq(N.nextEvent([events[1]], now), null, "only finished events")
        T.eq(N.nextEvent([], now), null, "no events")
        T.eq(N.nextEvent(null, now), null, "missing events")
        T.eq(N.nextEvent([{ title: "Reminder", start: at(16), end: at(16), allDay: false }], now).title, "Reminder", "zero-length future event")

        // Event time line
        T.eq(N.eventWhen(events[0], now), "All day", "all day")
        T.eq(N.eventWhen({ start: at(14), end: at(15), allDay: false }, now), "Now · until 15:00", "running")
        T.eq(N.eventWhen(events[3], now), "In 15 min", "starting within an hour")
        T.eq(N.eventWhen({ start: new Date(now.getTime() + 20000), end: at(15), allDay: false }, now), "In 1 min", "starting in seconds")
        T.eq(N.eventWhen(events[2], now), "17:00 – 18:00", "later today")
        T.eq(N.eventWhen({ start: at(18), end: at(18), allDay: false }, now), "18:00", "point in time")
        T.eq(N.eventWhen(null, now), "", "no event")

        // Rows
        T.eq(N.rows({}), ["header", "status"], "minimal overview")
        T.eq(N.rows({ event: true, media: true }), ["header", "event", "media", "status"], "all rows in order")
        T.eq(N.rows({ media: true }), ["header", "media", "status"], "media without event")

        // Status items
        const items = N.statusItems({
            battery: { present: true, percent: 83.4, charging: true, icon: "B" },
            network: { icon: "W", connected: true },
            bluetooth: { available: true, icon: "BT", connected: false },
            dnd: true,
            volume: { icon: "V", muted: true }
        })
        T.eq(items.map(item => item.id), ["battery", "network", "bluetooth", "dnd", "volume"], "status order")
        T.eq([items[0].text, items[0].charging], ["83%", true], "battery percent")
        T.eq(items.map(item => item.dim), [false, false, true, false, true], "dimmed when off")
        T.eq(N.statusItems({ battery: { present: false }, network: { icon: "W", connected: false },
                             bluetooth: { available: false }, dnd: false, volume: { icon: "V", muted: false } }).map(item => item.id),
             ["network", "volume"], "desktop without battery or Bluetooth")
        T.eq(N.statusItems(undefined), [], "no state")

        // Collapsed width: the dragged width is a floor, the content can push
        // past it, and the surface is the ceiling.
        T.eq(N.collapsedWidth(40, 0, 160, 400, 14), 160, "minimum width")
        T.eq(N.collapsedWidth(140, 0, 160, 400, 14), 168, "a wide strip grows the notch")
        T.eq(N.collapsedWidth(40, 300, 160, 400, 14), 300, "a width that was dragged is kept")
        T.eq(N.collapsedWidth(340, 300, 160, 400, 14), 368, "but content that no longer fits wins")
        T.eq(N.collapsedWidth(500, 0, 160, 400, 14), 400, "a strip never outgrows the surface")
        T.eq(N.collapsedWidth(500, 0, 460, 400, 14), 460, "the minimum wins over a smaller maximum")

        // The overview's size: a floor for both, bounded by the surface.
        const room = { minWidth: 200, maxWidth: 700, maxHeight: 400, width: 384 }
        T.eq(N.expandedSize(0, 0, 120, room), { width: 384, height: 120 }, "nothing dragged yet: the default width, the content's height")
        T.eq(N.expandedSize(500, 0, 120, room), { width: 500, height: 120 }, "a dragged width")
        T.eq(N.expandedSize(500, 300, 120, room), { width: 500, height: 300 }, "a dragged height holds room open")
        T.eq(N.expandedSize(500, 100, 260, room), { width: 500, height: 260 }, "what the grid needs always wins")
        T.eq(N.expandedSize(9999, 9999, 120, room), { width: 700, height: 400 }, "neither outgrows the surface")
        T.eq(N.expandedSize(50, 0, 120, room).width, 200, "nor shrinks below the minimum")

        // Columns follow the width, so a cell stays the size of its contents.
        T.eq([N.gridColumns(384, 175, 4), N.gridColumns(700, 175, 4), N.gridColumns(200, 175, 4)], [2, 4, 1],
             "a wider notch gets more columns, not wider cells")
        T.eq(N.gridColumns(4000, 175, 4), 4, "never more than the grid allows")

        // What the strip draws: the arranged list, led by the recording chip.
        const strip = (items, recording) => N.stripItems(items, recording).map(i => i.type)
        const one = (type, id) => ({ id: id || type, type: type })
        T.eq(strip([one("clock")], false), ["clock"], "the list as it stands")
        T.eq(strip([one("clock")], true), ["recording", "clock"], "the chip leads while recording")
        T.eq(strip([one("recording"), one("clock")], true), ["recording", "clock"], "never twice")
        T.eq(strip([one("clock"), one("recording")], true), ["clock", "recording"], "the placed one keeps its place")
        T.eq(strip(null, true), ["recording"], "a missing list is still a strip")
        T.eq(N.stripItems([one("clock", "notch-clock-1")], true).map(i => i.id), ["", "notch-clock-1"],
             "the automatic chip carries no id, so it cannot be dragged")
        T.eq(N.stripItems([one("clock", "notch-clock-1")], false)[0].id, "notch-clock-1", "stored ids are kept")

        // A pill is a notch that let go of the top edge.
        T.eq(N.pillTop("pill", 10), 10, "a pill sits below the edge")
        T.eq(N.pillTop("notch", 10), 0, "a notch hangs from it")
        T.eq(N.pillTop("pill", -5), 0, "never above it")
        // Both shapes leave the same margin to the window below them. What the
        // window really starts at is the reserve plus the compositor's own gap,
        // so both of these land on the shape's bottom edge plus 6.
        T.eq(N.reserveHeight("notch", 32, 6, 12), 26, "a notch reserves its height and margin, less the compositor's gap")
        T.eq(N.reserveHeight("pill", 32, 6, 12), 32, "a pill reserves the margin above it as well")
        T.eq(N.reserveHeight("notch", 32, 6, 12) + 12 - 32, 6, "a notch leaves six to the window")
        T.eq(N.reserveHeight("pill", 32, 6, 12) + 12 - (6 + 32), 6, "and so does a pill")
        T.eq(N.reserveHeight("pill", 32, 12, 12), 44, "a wider margin than the window gap does cost room")
        T.eq(N.reserveHeight("pill", 32, 2, 40), 0,
             "a gap wider than the shape clears it on its own, so nothing is reserved")
        T.eq(N.pillRadius(32, 11, 34, false), 16, "a collapsed pill is round at its ends")
        T.eq(N.pillRadius(200, 11, 34, true), 34, "an expanded one takes the panel radius")
        T.eq(N.pillRadius(20, 11, 34, true), 10, "and never more than half its height")

        // Corners and outline
        T.eq(N.fitCorners(100, 30, 8, 12), { ear: 8, radius: 12 }, "corners fit")
        T.eq(N.fitCorners(100, 10, 8, 12), { ear: 5, radius: 5 }, "corners clamped to a low body")
        T.eq(N.fitCorners(10, 100, 8, 40), { ear: 8, radius: 5 }, "radius clamped to a narrow body")
        T.eq(N.geometry(100, 60, 30, 8, 12), { ear: 8, radius: 12, left: 70, right: 130, bottom: 30 },
             "outline with ears and bottom corners")
        T.eq(N.geometry(50, -4, 0, 8, 12), { ear: 0, radius: 0, left: 50, right: 50, bottom: 0 },
             "empty body collapses to a point")
        T.eq(N.mix(10, 20, 0.25), 12.5, "mix")

        // The wide layout's event list
        const day = new Date(2026, 8, 17, 12, 0)
        const ev = (h, m, eh, title, allDay) => ({ start: new Date(2026, 8, 17, h, m),
            end: new Date(2026, 8, 17, eh, 0), title: title, allDay: allDay === true })
        const list = [ev(16, 0, 17, "Late"), ev(9, 0, 10, "Over"), ev(0, 0, 0, "Conference", true),
                      ev(11, 30, 13, "Running"), ev(14, 0, 15, "Next")]
        T.eq(N.upcomingEvents(list, day, 3).map(e => e.title), ["Running", "Next", "Late"],
             "timed events that have not ended, earliest first")
        T.eq(N.upcomingEvents(list, day, 9).map(e => e.title), ["Running", "Next", "Late", "Conference"],
             "all-day events come after the timed ones")
        T.eq(N.upcomingEvents(list, day, 1).map(e => e.title), ["Running"], "count limits the list")
        T.eq(N.upcomingEvents([], day, 2).length, 0, "no events")
        T.eq(N.upcomingEvents([null, { title: "broken" }], day, 2).length, 0, "broken entries are skipped")

        // ---- the two lists the notch is arranged from --------------------
        const types = (notch, zone) => L.notchTypes(notch, zone)
        const fresh = L.defaultNotch()
        T.eq(types(fresh, "collapsed"), ["clock"], "the strip starts with the time")
        T.eq(types(fresh, "expanded"), ["clock", "weather", "media", "events", "status"],
             "and the overview with the big time, the weather and the rest")

        // The header became an item, once, for a notch stored before it was.
        const headless = L.sanitizeNotch({ collapsed: [{ id: "c", items: [{ type: "clock" }] }],
                                           expanded: [{ id: "m", items: [{ type: "media" }] }] })
        const adopted = L.adoptNotchHeader(headless)
        T.eq(types(adopted, "expanded"), ["clock", "media"], "the overview gets a clock at the front")
        T.eq(types(adopted, "collapsed"), ["clock"], "and the strip keeps its own")
        T.ok(L.notchItems(adopted, "expanded")[0].id !== L.notchItems(adopted, "collapsed")[0].id,
             "with an id of its own, because ids are unique across both zones")
        T.eq(types(L.adoptNotchHeader(adopted), "expanded"), ["clock", "media"], "and never twice")
        T.eq(JSON.stringify(L.adoptNotchHeader(fresh)), JSON.stringify(fresh), "a notch that already has one is untouched")
        T.eq(L.notchItems(fresh, "collapsed").map(item => item.id), ["notch-clock-1"],
             "and the editor gets its stored id with it")
        T.eq(L.notchItems(null, "collapsed"), [], "no notch, no items")

        // How big an item sits, in grid steps.
        const sizes = notch => L.notchItems(notch, "expanded").map(item => [item.w, item.h])
        T.eq(sizes(fresh), [[2, 2], [2, 2], [2, 2], [2, 2], [4, 1]],
             "the overview starts as it always looked: the time and the weather, media and events, the status row across the bottom")
        const id0 = L.notchItems(fresh, "expanded")[0].id
        T.eq(sizes(L.setNotchItemSize(fresh, id0, 4, 3))[0], [4, 3], "a corner dragged out")
        T.eq(sizes(L.setNotchItemSize(fresh, id0, 1, 1))[0], [1, 1], "and back in")
        T.eq(sizes(L.setNotchItemSize(fresh, id0, 99, 99))[0], [4, 6], "never past the grid")
        T.eq(sizes(L.setNotchItemSize(fresh, id0, 0, 0))[0], [1, 1], "never smaller than one cell")
        T.eq(sizes(L.setNotchItemSize(fresh, "nothing", 4, 4)), sizes(fresh), "an unknown id changes nothing")
        T.eq(JSON.stringify(L.defaultNotch()), JSON.stringify(fresh), "none of it touched the input")
        T.eq(L.notchItems(L.addNotchItem(fresh, "cpu", "expanded"), "expanded").slice(-1)[0],
             { id: "notch", type: "cpu", w: 1, h: 2 }, "a widget added to the overview starts two rows tall")

        // A type the catalogue gives a floor cannot be pulled below it: the
        // grid refuses rather than handing back a cell that only clips. The
        // media block is the one that has one.
        const mediaId = L.notchItems(fresh, "expanded").find(item => item.type === "media").id
        const squashed = L.notchItems(L.setNotchItemSize(fresh, mediaId, 1, 1), "expanded")
            .find(item => item.id === mediaId)
        T.eq([squashed.w, squashed.h], [2, 2], "the media block stops at its own smallest useful cell")
        T.eq(L.notchMinSize("media"), { w: 2, h: 2 }, "and says so")
        T.eq(L.notchMinSize("clock"), { w: 1, h: 1 }, "a type with no floor goes down to one step")
        T.eq(L.notchMinSize("nothing at all"), { w: 1, h: 1 }, "and so does an unknown one")
        // The same floor applies to what the file says, not only to a drag:
        // a media block written one cell wide loads two cells wide.
        const squashedFile = L.sanitizeNotch({ collapsed: [{ id: "c", items: [{ type: "clock" }] }],
                                               expanded: [{ id: "m", items: [{ type: "media", w: 1, h: 1 }] },
                                                          { id: "e", items: [{ type: "events", w: 1, h: 1 }] }] })
        T.eq(L.notchItems(squashedFile, "expanded").map(item => [item.w, item.h]), [[2, 2], [1, 2]],
             "a file below the floor is raised to it on load")

        // Reading a file back.
        T.eq(types(L.sanitizeNotch(null), "expanded"), types(fresh, "expanded"), "no notch at all falls back")
        const kept = L.sanitizeNotch({ collapsed: [{ id: "a", items: [{ type: "date" }] }],
                                       expanded: [{ id: "b", items: [{ type: "media" }] }] })
        T.eq([types(kept, "collapsed"), types(kept, "expanded")], [["date"], ["media"]], "a stored notch is kept")
        const smuggled = L.sanitizeNotch({ collapsed: [{ id: "a", items: [{ type: "clock" }, { type: "date" }] }], expanded: [] })
        T.eq(types(smuggled, "collapsed"), ["clock"], "a pill with two items keeps the first")
        T.eq(types(L.sanitizeNotch({ collapsed: [], expanded: [] }), "collapsed"), ["clock"],
             "an empty strip comes back with the time - a notch with nothing in it is not a notch")
        T.eq(types(L.sanitizeNotch({ collapsed: [{ id: "a", items: [{ type: "clock" }] }], expanded: [] }), "expanded"), [],
             "an empty overview is left empty, because that is a choice")
        const clash = L.sanitizeNotch({ collapsed: [{ id: "same", items: [{ type: "clock" }] }],
                                        expanded: [{ id: "same", items: [{ type: "media" }] }] })
        T.ok(clash.collapsed[0].id !== clash.expanded[0].id, "two items never share an id, even across the zones")

        // Moving, within a zone and between them.
        const three = L.sanitizeNotch({ collapsed: [{ id: "c1", items: [{ type: "clock" }] }],
                                        expanded: [{ id: "e1", items: [{ type: "weather" }] },
                                                   { id: "e2", items: [{ type: "media" }] }] })
        T.eq(types(L.moveNotchItemTo(three, "e2", "expanded", 0), "expanded"), ["media", "weather"],
             "an item moves inside its zone")
        T.eq(types(L.moveNotchItemTo(three, "e1", "collapsed", 0), "collapsed"), ["weather", "clock"],
             "and into the other one")
        T.eq(types(L.moveNotchItemTo(three, "e1", "collapsed", 0), "expanded"), ["media"],
             "leaving the zone it came from")
        T.eq(types(L.moveNotchItemTo(three, "nope", "collapsed", 0), "collapsed"), ["clock"], "an unknown id changes nothing")
        T.eq(types(L.moveNotchItemTo(three, "e1", "nowhere", 0), "expanded"), ["weather", "media"], "so does an unknown zone")

        // Adding and removing.
        T.eq(types(L.addNotchItem(three, "battery"), "expanded"), ["weather", "media", "battery"],
             "a new item lands in the overview, where there is room")
        T.eq(types(L.addNotchItem(three, "battery", "collapsed"), "collapsed"), ["clock", "battery"],
             "unless the strip was asked for")
        T.eq(types(L.addNotchItem(three, "clock"), "expanded"), ["weather", "media"],
             "a type already on the notch is not added a second time")
        T.eq(types(L.addNotchItem(three, ""), "expanded"), ["weather", "media"], "nothing to add")
        T.eq(types(L.removeNotchItem(three, "e1"), "expanded"), ["media"], "an item is removed")
        T.eq(types(L.removeNotchItem(three, "nope"), "expanded"), ["weather", "media"], "an unknown one is not")

        // The whole layout carries it, without a version bump.
        const config = L.sanitize({ configVersion: 3, profiles: {} })
        T.eq(config.configVersion, 3, "adding the notch does not move the layout version")
        T.eq(types(config.notch, "collapsed"), ["clock"], "a file without a notch gets the default")
        const stored = L.sanitize({ configVersion: 3, profiles: {},
                                    notch: { collapsed: [{ id: "x", items: [{ type: "date" }] }], expanded: [] } })
        T.eq(types(stored.notch, "collapsed"), ["date"], "a file with one keeps it")

        // Operations never touch what they were given.
        const before = JSON.stringify(three)
        L.moveNotchItemTo(three, "e1", "collapsed", 0)
        L.addNotchItem(three, "battery")
        L.removeNotchItem(three, "e1")
        T.eq(JSON.stringify(three), before, "every operation copies rather than edits")

        T.finish("NotchTest")
    }
}
