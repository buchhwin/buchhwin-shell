import Quickshell
import Quickshell.Io
import QtQuick
import qs.theme
import qs.services
import "Harness.js" as T
import "../../services/notch/NotchLogic.js" as N
import "../../services/LayoutLogic.js" as L

ShellRoot {
    // The real built-in preset, so a broken file fails here and not on a desktop.
    FileView { id: islandFile; path: Qt.resolvedUrl("../../config/notch-presets/island.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: classicFile; path: Qt.resolvedUrl("../../config/notch-presets/classic.json").toString().replace("file://", ""); blockLoading: true }
    FileView { id: taskbarFile; path: Qt.resolvedUrl("../../config/dock-presets/taskbar.json").toString().replace("file://", ""); blockLoading: true }

    Component.onCompleted: {
        const at = (h, m) => new Date(2026, 8, 17, h, m || 0)
        const now = at(14, 30)

        // Time text: the clock widget's, 24 or 12 hours as the setting says.
        T.eq(N.timeText(at(9, 5)), "09:05", "time is zero padded")
        T.eq(N.timeText(at(23, 59)), "23:59", "24-hour time")
        T.eq(N.timeText(at(18, 52), false), "18:52", "24 hours when the clock is set to them")
        T.eq([N.timeText(at(18, 52), true), N.timeText(at(9, 5), true), N.timeText(at(0, 30), true)],
             ["6:52 PM", "9:05 AM", "12:30 AM"], "and the 12-hour form the bar's clock writes")

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
        T.eq(N.eventWhen({ start: at(14), end: at(15), allDay: false }, now, true), "Now · until 3:00 PM",
             "running, on a 12-hour clock")
        T.eq(N.eventWhen(events[2], now, true), "5:00 PM – 6:00 PM", "later today, on a 12-hour clock")
        T.eq(N.eventWhen({ start: at(18), end: at(18), allDay: false }, now, true), "6:00 PM", "a point in time too")
        T.eq(N.eventWhen(events[3], now, true), "In 15 min", "a countdown has no clock to follow")

        // Status items
        const items = N.statusItems({
            battery: { present: true, percent: 83.4, charging: true, icon: "B" },
            network: { icon: "W", connected: true },
            bluetooth: { available: true, icon: "BT", connected: false },
            dnd: true,
            volume: { icon: "V", muted: true }
        })
        T.eq(items.map(item => item.id), ["network", "bluetooth", "dnd", "volume", "battery"],
             "status order: the bars' own, the battery at the outer end")
        T.eq([items[4].text, items[4].charging], ["83%", true], "battery percent")
        T.eq(items.map(item => item.dim), [false, true, false, true, false], "dimmed when off")
        T.eq(N.statusItems({ battery: { present: false }, network: { icon: "W", connected: false },
                             bluetooth: { available: false }, dnd: false, volume: { icon: "V", muted: false } }).map(item => item.id),
             ["network", "volume"], "desktop without battery or Bluetooth")
        T.eq(N.statusItems(undefined), [], "no state")
        T.eq(N.statusItems({ dnd: true, stayAwake: { on: true, icon: "C" }, volume: { icon: "V", muted: false } })
                 .map(item => item.id + ":" + item.icon), ["dnd:󰂛", "stayAwake:C", "volume:V"],
             "stay awake after Do Not Disturb, while it holds")
        T.eq(N.statusItems({ stayAwake: { on: false, icon: "C" } }), [], "and not when it does not")
        const battery = extra => N.statusItems({ battery: Object.assign({ present: true, percent: 12, icon: "B" }, extra) })[0]
        T.eq([battery({ low: true }).low, battery({ low: true }).charging], [true, false], "a low battery")
        T.eq([battery({ low: true, charging: true }).low, battery({ low: true, charging: true }).charging], [false, true],
             "charging wins over low")
        T.eq([battery({}).low, battery({ low: "yes" }).low], [false, false], "low only when said so")
        T.eq(items[4].low, false, "a charging battery is not low")

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
        T.eq(N.stripItems([one("clock")], false, true).map(i => i.type), ["timer", "clock"], "a running timer leads the strip")
        T.eq(N.stripItems([one("clock")], true, true).map(i => i.type), ["recording", "timer", "clock"],
             "after a recording, which is the more urgent of the two")

        // The strip around its clock: as wide on the lighter side as on the
        // heavier one, so the time sits in the middle of the screen. The pad
        // the lighter side gets is split, half outside the group (the row's
        // offset, for a left pad) and half between the group and the clock.
        T.eq(N.stripSymmetry(227, 130, 40), { width: 300, offset: 0, leftPad: 0, rightPad: 73 },
             "a heavier left side widens the right")
        T.eq(N.stripSymmetry(200, 20, 40), { width: 320, offset: 60, leftPad: 120, rightPad: 0 },
             "a heavier right side pads the left, and the row shifts by half of it")
        T.eq(N.stripSymmetry(120, 40, 40), { width: 120, offset: 0, leftPad: 0, rightPad: 0 }, "already symmetric: nothing changes")
        T.eq(N.stripSymmetry(40, 0, 40), { width: 40, offset: 0, leftPad: 0, rightPad: 0 }, "a clock alone")
        T.eq(N.stripSymmetry(200, -1, 0), { width: 200, offset: 0, leftPad: 0, rightPad: 0 }, "no clock: the row as measured")
        T.eq(N.stripSymmetry(200, 180, 40), { width: 200, offset: 0, leftPad: 0, rightPad: 0 }, "a clock that is not inside the row yet is ignored")
        // The lighter group in the middle of its half: a group of 60 left of
        // the clock, 200 right of it. The half is 200 wide, the group starts
        // at the offset and ends a pad's half before the clock, whose left
        // edge is the strip's centre less half the clock - the same gap on
        // both sides of the group.
        const centred = N.stripSymmetry(300, 60, 40)
        T.eq(centred, { width: 440, offset: 70, leftPad: 140, rightPad: 0 }, "a left pad is split in two")
        T.eq([centred.offset, (centred.width - 40) / 2 - (centred.offset + 60)], [70, 70],
             "half of it outside the group and half between the group and the clock: the group is centred in its half")
        // And the right-hand counterpart: the row does not shift, the gap
        // the strip puts after the clock is half the right pad.
        T.eq(N.stripSymmetry(300, 200, 40).rightPad / 2, 70, "a right pad's inner half sits between the clock and its group")

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
        // The gap is the mode's own (Settings > Appearance, gaps_out), not a
        // fixed 12: the window still starts six below the shape.
        for (const gap of [0, 8]) {
            T.eq(N.reserveHeight("notch", 32, 6, gap) + gap - 32, 6, "a notch leaves six at gap " + gap)
            T.eq(N.reserveHeight("pill", 32, 6, gap) + gap - (6 + 32), 6, "and a pill at gap " + gap)
        }
        T.eq(N.reserveHeight("notch", 32, 6, 60), 0, "a gap wider than the notch and its margin: nothing reserved")
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
        // The collapsed corners against a body that is a slider now: clamped
        // at half the height, not scaled with it.
        T.eq(N.collapsedRadius(14, 34), 14, "Island's corners fit its body as they are")
        T.eq([N.collapsedRadius(14, 48), N.collapsedRadius(14, 28)], [14, 14],
             "a taller or lower body keeps the corners' number while they fit")
        T.eq(N.collapsedRadius(22, 34), 17, "large shell corners round off at half the height")
        T.eq(N.collapsedRadius(N.BODY_RADIUS.max, N.BODY_HEIGHT.min), N.BODY_HEIGHT.min / 2,
             "the roundest corners on the lowest body: a pill's ends")
        T.eq([N.collapsedRadius(-3, 34), N.collapsedRadius("x", 34), N.collapsedRadius(14, undefined)], [0, 0, 0],
             "nonsense is square")

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
             { id: "notch", type: "cpu", w: 1, h: 2, display: "full", options: {} }, "a widget added to the overview starts two rows tall")

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

        // The strip refuses the blocks it cannot draw: added there, one was an
        // empty spot that could not go back into the overview either.
        T.ok(N.STRIP_REFUSES.every(type => types(L.addNotchItem(three, type, "collapsed"), "collapsed").join() === "clock"),
             "no media, events or status block is added to the strip")
        T.eq(types(L.addNotchItem(three, "events", "collapsed"), "expanded"), ["weather", "media"], "nor anywhere else instead")
        T.eq(types(L.addNotchItem(three, "battery", "collapsed"), "collapsed"), ["clock", "battery"], "a widget still is")
        T.eq([types(L.moveNotchItemTo(three, "e2", "collapsed", 0), "collapsed"), types(L.moveNotchItemTo(three, "e2", "collapsed", 0), "expanded")],
             [["clock"], ["weather", "media"]], "the media block is not moved into the strip, and stays where it was")
        const strayStrip = L.sanitizeNotch({ collapsed: [{ id: "c", items: [{ type: "clock" }] }, { id: "s", items: [{ type: "events" }] }],
                                             expanded: [{ id: "m", items: [{ type: "media" }] }] })
        T.eq([types(strayStrip, "collapsed"), types(strayStrip, "expanded")], [["clock"], ["media", "events"]],
             "an events block stored in the strip goes back to the overview")
        T.eq(L.notchItems(strayStrip, "expanded").map(item => [item.w, item.h])[1], [1, 2], "at its floor")
        const twice = L.sanitizeNotch({ collapsed: [{ id: "c", items: [{ type: "media" }] }],
                                        expanded: [{ id: "m", items: [{ type: "media" }] }] })
        T.eq([types(twice, "collapsed"), types(twice, "expanded")], [["clock"], ["media"]],
             "or away when the overview has it, and the strip gets its time back")

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

        // How the notch opens.
        T.eq([N.hoverMode("click"), N.hoverMode("off"), N.hoverMode("sideways"), N.hoverMode(undefined)],
             ["click", "off", "hover", "hover"], "hover mode validated")
        T.eq([N.hoverOpens("hover"), N.hoverOpens("click"), N.hoverOpens("off")], [true, false, false], "only hover opens on hover")
        // Swiping the collapsed notch between its pages.
        T.eq(N.swipeStep(0, 0, 0, -120), 0.35, "a wheel notch down is a third of a page to the right")
        T.ok(N.swipeStep(0, 0, 0, -240) >= N.SWIPE.threshold, "two notches turn the page")
        T.eq(N.swipeStep(-60, 5, 0, 0), 0.2, "a touchpad's pixels count whole, the larger axis wins")
        T.eq([N.swipeSettle(0, 0.6, [-1, 0, 1]), N.swipeSettle(0, -0.6, [-1, 0, 1]), N.swipeSettle(0, 0.4, [-1, 0, 1])],
             [1, -1, 0], "past 56 % it crosses, short of it it snaps back")
        T.eq([N.swipeSettle(0, 0.9, [-1, 0]), N.swipeSettle(1, 0.9, [-1, 0, 1]), N.swipeSettle(-1, 0.7, [-1, 0, 1])],
             [0, 1, 0], "no page past the last, and back to the strip from the side")
        T.eq([N.buttonAction("clipboard"), N.buttonAction("playPause"), N.buttonAction("evil"), N.buttonAction(undefined)],
             ["clipboard", "playPause", "none", "none"], "the middle and right buttons do nothing unless set")
        T.ok(L.NOTCH_PRESET_OPTIONS.indexOf("middleAction") >= 0 && L.NOTCH_PRESET_OPTIONS.indexOf("rightAction") >= 0,
             "a preset carries what the other two buttons do")
        // The hover waits for a display: a notification widened the notch
        // under a resting pointer, the overview opened and the notification
        // jumped out into a popup over it.
        T.eq(N.hoverMayOpen(true, false, false, false), true, "the pointer stayed: the overview opens")
        T.eq(N.hoverMayOpen(true, false, false, true), false, "not while the notch shows a notification or a level")
        T.eq([N.hoverMayOpen(false, false, false, false), N.hoverMayOpen(true, true, false, false), N.hoverMayOpen(true, false, true, false)],
             [false, false, false], "nor once the pointer left, during a swipe, or with a panel up")
        T.eq([N.clickResult("hover", "dashboard"), N.clickResult("hover", "expand"), N.clickResult("hover", "evil"),
              N.clickResult("click", "dashboard"), N.clickResult("off", "expand")],
             ["dashboard", "expand", "dashboard", "expand", "dashboard"], "what a click on the collapsed notch does")
        T.eq([N.delay(120, N.OPEN_DELAY), N.delay(-5, N.OPEN_DELAY), N.delay(99999, N.CLOSE_DELAY), N.delay("x", N.CLOSE_DELAY)],
             [120, 0, 2000, 400], "delays clamped, nonsense falls back")

        // Status glyphs in the accent: nowhere, the overview, or the strip too.
        T.eq(N.ACCENT_GLYPHS, ["off", "overview", "all"], "the three accent-glyph settings")
        T.eq([N.accentGlyphs("all"), N.accentGlyphs("overview"), N.accentGlyphs("evil"), N.accentGlyphs(undefined)],
             ["all", "overview", "off", "off"], "an unknown accent-glyph setting is off")
        T.eq([N.glyphsInAccent("off", "overview"), N.glyphsInAccent("off", "strip")], [false, false], "off: white everywhere")
        T.eq([N.glyphsInAccent("overview", "overview"), N.glyphsInAccent("overview", "strip")], [true, false],
             "overview: the open notch only, the strip stays white")
        T.eq([N.glyphsInAccent("all", "overview"), N.glyphsInAccent("all", "strip")], [true, true], "all: both places")
        T.eq([N.glyphsInAccent("evil", "overview"), N.glyphsInAccent(undefined, "strip"), N.glyphsInAccent("all", "bar")],
             [false, false, false], "nonsense is off, and no other place takes the accent")
        T.ok(L.NOTCH_PRESET_OPTIONS.indexOf("accentGlyphs") >= 0, "a preset carries the glyph colour")

        // The collapsed body: clamped to its ranges, rounded, and the theme's
        // token (the caller's fallback) for anything that is not a number.
        T.eq([N.bodySize(32, N.BODY_HEIGHT, 40), N.bodySize(10, N.BODY_HEIGHT, 40), N.bodySize(999, N.BODY_RADIUS, 16),
              N.bodySize(11.4, N.BODY_RADIUS, 16), N.bodySize("x", N.BODY_PADDING, 22), N.bodySize(undefined, N.BODY_PADDING, 22)],
             [32, 24, 32, 11, 22, 22], "body sizes clamped and rounded, nonsense falls back to the token")
        T.eq(Object.keys(N.BODY_RANGES), ["bodyHeight", "bodyRadius", "bodyPadding"], "one range per body setting, under its key")
        T.ok(N.BODY_HEIGHT.min <= 32 && N.BODY_RADIUS.min <= 11 && N.BODY_PADDING.min <= 16, "Classic's body is inside the ranges")
        T.ok(N.BODY_HEIGHT.max >= 34 && N.BODY_RADIUS.max >= 14 && N.BODY_PADDING.max >= 22, "and so is Island's")
        // A notch without stored values is Island's: the settings' defaults
        // and the theme's fallback tokens are the preset file's body.
        const islandBody = JSON.parse(islandFile.text()).options
        T.eq([Metrics.notchHeight, Metrics.notchRadius, Metrics.notchPadding],
             [islandBody.bodyHeight, islandBody.bodyRadius, islandBody.bodyPadding], "the theme's fallback is Island's body")
        T.eq(["bodyHeight", "bodyRadius", "bodyPadding"].map(key => SettingsService.defaultOf("notch." + key)),
             [islandBody.bodyHeight, islandBody.bodyRadius, islandBody.bodyPadding], "and so are the settings' defaults")

        // The Height row stores whole pixels inside the range on release, and
        // nothing - no undo step - for a release on the stored value.
        T.eq(N.bodyChange("bodyHeight", 30.4, 34), 30, "whole pixels")
        T.eq(N.bodyChange("bodyHeight", 33.6, 34), null, "a release that rounds to the stored height is no change")
        T.eq([N.bodyChange("bodyHeight", 12, 34), N.bodyChange("bodyHeight", 99, 34)], [24, 64], "inside the range")
        T.eq(N.bodyChange("bodyHeight", 40, 34), 40, "the old Island height is still a choice")
        T.eq([N.bodyChange("bodyHeight", "x", 34), N.bodyChange("bodyHeight", null, 34), N.bodyChange("bodyHeight", "", 34)],
             [null, null, null], "not a number is nothing to store")
        T.eq(N.bodyChange("bodyHeight", 24, undefined), 24, "a height without a stored one is a change")
        T.eq([N.bodyChange("openDelay", 300, 150), N.bodyChange("toString", 30, 34)], [null, null],
             "only the body keys")
        T.eq(N.migrate({ notch: { expandOnHover: false, reserve: true } }).notch, { reserve: true, hoverMode: "click" },
             "expandOnHover off becomes click")
        T.eq(N.migrate({ notch: { expandOnHover: true, hoverMode: "off" } }).notch, { hoverMode: "off" },
             "an existing hover mode wins, the old key goes")
        const untouched = { notch: { reserve: true } }
        T.ok(N.migrate(untouched) === untouched, "nothing to migrate, nothing copied")

        // Presets: the short form, sanitizing, and the user's own.
        const spec = { label: "Test", collapsed: ["workspace", "clock"],
                       expanded: [{ type: "clock", w: 4, h: 1 }, { type: "media", w: 1, h: 1 }, "", { type: 3 }],
                       options: { hoverMode: "click", openDelay: 90, bodyHeight: 32, evil: "x", shape: { nested: 1 } } }
        const fromSpec = L.sanitizeNotchPreset(spec, true)
        T.eq(L.notchTypes(fromSpec.layout, "collapsed"), ["workspace", "clock"], "strip from the short form")
        T.eq(L.notchItems(fromSpec.layout, "expanded").map(item => [item.type, item.w, item.h]),
             [["clock", 4, 1], ["media", 2, 2]], "sizes kept, the media floor applied, junk entries dropped")
        T.eq(fromSpec.options, { hoverMode: "click", openDelay: 90, bodyHeight: 32 }, "only known, primitive options kept")
        T.ok(["bodyHeight", "bodyRadius", "bodyPadding"].every(key => L.NOTCH_PRESET_OPTIONS.indexOf(key) >= 0),
             "a preset carries the collapsed body")
        T.eq([fromSpec.id, fromSpec.builtin], ["test", true], "id from the label, marked built-in")
        T.eq(L.sanitizeNotchPreset({ label: "  " }), null, "a preset needs a name")

        const island = L.sanitizeNotchPreset(JSON.parse(islandFile.text()), true)
        T.ok(island !== null && island.label === "Island", "the Island preset file reads")
        T.eq(L.notchTypes(island.layout, "collapsed"), ["workspace", "clock", "network", "battery"], "Island strip")
        T.eq(L.notchItems(island.layout, "collapsed").map(item => [item.display, item.options.style || "", item.options.mode || "", item.options.glyph || ""]),
             [["full", "dots", "open", ""], ["full", "", "", ""], ["icon", "", "", ""], ["icon", "", "", ""]],
             "dots for the open workspaces, the network and the battery as their plain glyphs (13.10.: no bars, no lying battery)")
        T.eq(L.notchTypes(island.layout, "expanded")[0], "clock", "Island opens on the time and date")
        const openWorkspaces = L.notchItems(island.layout, "expanded").filter(item => item.type === "workspace")
        T.eq(openWorkspaces.map(item => item.options.style), ["dots"], "Island's open workspaces are round dots, like its strip")
        T.eq(island.options.hoverMode, "hover", "Island opens on hover")
        T.eq([island.options.bodyHeight, island.options.bodyRadius, island.options.bodyPadding], [34, 14, 22],
             "Island's body is the theme's: 34 tall, corners of 14, 22 of air")

        // Classic is the notch as it was before Island: the time alone in the
        // strip, the overview of five on hover, at the default width.
        const classic = L.sanitizeNotchPreset(JSON.parse(classicFile.text()), true)
        T.ok(classic !== null && classic.label === "Classic", "the Classic preset file reads")
        T.eq(L.notchTypes(classic.layout, "collapsed"), ["clock"], "Classic strip: the time alone")
        T.eq(L.notchTypes(classic.layout, "expanded")[0], "clock", "Classic opens on the time and date")
        T.eq(L.notchTypes(classic.layout, "expanded"), L.notchTypes(L.defaultNotch(), "expanded"),
             "and its overview is the default notch's: weather, music, events and status")
        T.eq(L.notchItems(classic.layout, "expanded").map(item => [item.w, item.h]), sizes(fresh),
             "at the default notch's sizes")
        T.eq(classic.options.hoverMode, "hover", "Classic opens on hover")
        T.eq([classic.options.shape, classic.options.expandedWidth, classic.options.eventCount], ["notch", 0, 2],
             "hanging from the edge, at the default width, two events")
        T.eq([classic.options.bodyHeight, classic.options.bodyRadius, classic.options.bodyPadding], [32, 11, 16],
             "Classic's body is the one before Island: 32 tall, corners of 11, 16 of air")

        // The files themselves: sanitizing drops an unknown option without a
        // word, and a body size outside its range would be clamped on screen
        // to something other than what the file says.
        const files = [["Island", islandFile], ["Classic", classicFile]]
        for (let i = 0; i < files.length; i++) {
            const options = JSON.parse(files[i][1].text()).options
            T.ok(Object.keys(options).every(key => L.NOTCH_PRESET_OPTIONS.indexOf(key) >= 0),
                 files[i][0] + ": every option in the file is one a preset carries")
            T.ok(Object.keys(N.BODY_RANGES).every(key => N.bodySize(options[key], N.BODY_RANGES[key], -1) === options[key]),
                 files[i][0] + ": the body sizes are inside their ranges")
            T.eq(N.collapsedRadius(options.bodyRadius, options.bodyHeight), options.bodyRadius,
                 files[i][0] + ": its corners are drawn as the file says, at the designed corner scale")
        }

        let presetConfig = L.sanitize({})
        T.eq(presetConfig.notchPresets, [], "no saved presets by default")
        const added = L.addNotchPreset(presetConfig, "My notch", L.defaultNotch(), { hoverMode: "off" }, ["island"])
        T.eq(added.id, "custom-my-notch", "saved presets get their own id space")
        presetConfig = L.sanitize(added.config)
        T.eq(presetConfig.notchPresets.length, 1, "kept by sanitize")
        T.eq(L.addNotchPreset(presetConfig, "My notch", L.defaultNotch(), {}, []).id, "custom-my-notch-2", "a second one with the same name")
        presetConfig = L.sanitize(L.renameNotchPreset(presetConfig, "custom-my-notch", "  Renamed  "))
        T.eq(presetConfig.notchPresets[0].label, "Renamed", "renamed, trimmed")
        T.eq(L.renameNotchPreset(presetConfig, "custom-my-notch", " ").notchPresets[0].label, "Renamed", "an empty name changes nothing")
        presetConfig = L.sanitize(L.removeNotchPreset(presetConfig, "custom-my-notch"))
        T.eq(presetConfig.notchPresets, [], "removed")
        T.eq(L.addNotchPreset(presetConfig, "", L.defaultNotch(), {}, []).id, "", "no name, nothing saved")

        // ---- numbers the IPC sets: one rule, the notch's own ranges --------
        T.eq(N.optionRange("openDelay"), N.OPEN_DELAY, "the open delay's range is the one the notch clamps to")
        T.eq(N.optionRange("closeDelay"), N.CLOSE_DELAY, "and the close delay's")
        T.eq(N.optionRange("bodyHeight"), N.BODY_HEIGHT, "the body keys by their setting")
        T.eq([N.optionRange("reserve"), N.optionRange("toString"), N.optionRange("")], [null, null, null], "no range for anything else")
        T.eq(N.optionNumber("openDelay", "1500"), null, "1500 ms is refused for opening, not stored and clamped to 1000")
        T.eq(N.optionNumber("openDelay", "1000"), 1000, "the open delay's top")
        T.eq(N.optionNumber("closeDelay", "1500"), 1500, "1500 ms is a close delay")
        T.eq(N.optionNumber("closeDelay", "2001"), null, "above the close delay's top")
        T.eq(N.optionNumber("openDelay", "149.6"), 150, "rounded to whole ms")
        T.eq([N.optionNumber("openDelay", "-1"), N.optionNumber("openDelay", "soon"), N.optionNumber("openDelay", ""),
              N.optionNumber("openDelay", " ")], [null, null, null, null], "negative, not a number or nothing")
        T.eq(N.optionNumber("bodyHeight", "64"), 64, "a body size inside its range")
        T.eq(N.optionNumber("bodyHeight", "65"), null, "and one outside it")
        T.eq(N.optionNumber("reserve", "1"), null, "a key that takes no number")
        T.eq(N.delay(N.optionNumber("openDelay", "1000"), N.OPEN_DELAY), 1000, "what is stored is what the notch uses")

        // ---- what an empty overview cell says ------------------------------
        T.eq(N.emptyText("weather", { weather: "noLocation" }, "Weather"), "No location", "weather without a place")
        T.eq(N.emptyText("weather", { weather: "disabled" }, "Weather"), "Weather off", "weather switched off")
        T.eq(N.emptyText("weather", { weather: "error" }, "Weather"), "No forecast", "no forecast to be had")
        T.eq(N.emptyText("weather", { weather: "loading" }, "Weather"), "Loading …", "on its way")
        T.eq(N.emptyText("events", {}, "Events"), "No events", "a day without events")
        T.eq(N.emptyText("calendarSummary", {}, "Events"), "No events", "the events widget too")
        T.eq([N.emptyText("media", {}, "Media"), N.emptyText("nowPlaying", {}, "Playback")],
             ["Nothing playing", "Nothing playing"], "the media block and the Playback widget")
        T.eq(N.emptyText("activeWindow", { workspaceEmpty: true }, "Active window"), "Empty workspace", "nothing open here")
        T.eq(N.emptyText("activeWindow", { workspaceEmpty: false }, "Active window"), "No window", "windows, none focused")
        T.eq(N.emptyText("privacy", {}, "Privacy"), "Privacy", "anything else keeps its name")
        T.eq(N.emptyText("cpu", null, ""), "cpu", "and without one, its type")

        // ---- beside a taskbar (notch.dockDuplicates) -----------------------
        T.eq([N.dockDuplicates("hide"), N.dockDuplicates("keep"), N.dockDuplicates(undefined), N.dockDuplicates("x")],
             ["hide", "keep", "keep", "keep"], "keep unless told to hide")
        // The real Taskbar preset's layout and Island's strip.
        const taskbar = JSON.parse(taskbarFile.text())
        const held = N.DOCK_READOUTS.filter(type => L.dockHasType(taskbar.layout, type))
        T.eq(held, ["clock", "date", "network", "volume", "battery", "notificationIndicator"],
             "the Taskbar holds the clock, the date, the status glyphs and the bell")
        const bar = { enabled: true, span: taskbar.options.span, visibility: taskbar.options.visibility, screens: ["eDP-1"] }
        const islandStrip = L.notchItems(L.sanitizeNotchPreset(JSON.parse(islandFile.text()), true).layout, "collapsed")
        const stripLeft = types => N.withoutTypes(islandStrip, types).map(item => item.type)
        T.eq(stripLeft(N.dockDuplicateTypes("hide", bar, held, "eDP-1", false)), ["workspace"],
             "hidden: Island's strip keeps its workspaces, the time, Wi-Fi and the battery go")
        T.eq(stripLeft(N.dockDuplicateTypes("keep", bar, held, "eDP-1", false)), ["workspace", "clock", "network", "battery"],
             "kept by default")
        T.eq(N.dockDuplicateTypes("hide", bar, held, "DP-8", false), [], "a screen without the taskbar keeps its strip")
        T.eq(N.dockDuplicateTypes("hide", bar, held, "", false), [], "a strip that names no screen keeps everything")
        T.eq(N.dockDuplicateTypes("hide", bar, held, "eDP-1", true), [], "the layout editor arranges every item")
        T.eq(N.dockDuplicateTypes("hide", Object.assign({}, bar, { enabled: false }), held, "eDP-1", false), [],
             "a dock that is off shows nothing twice")
        T.eq(N.dockDuplicateTypes("hide", Object.assign({}, bar, { span: "fit" }), held, "eDP-1", false), [],
             "nor does a dock that only fits its apps")
        T.eq(N.dockDuplicateTypes("hide", Object.assign({}, bar, { visibility: "intellihide" }), held, "eDP-1", false), [],
             "nor one that hides: the strip would be the only readout most of the time")
        T.eq(N.dockDuplicateTypes("hide", bar, ["apps", "start", "clock"], "eDP-1", false), ["clock"],
             "only readouts count")
        T.eq(N.dockDuplicateTypes("hide", null, held, "eDP-1", false), [], "no dock at all")
        T.ok(N.withoutTypes(islandStrip, []) === islandStrip, "nothing to leave out: the very list")
        T.eq(N.withoutTypes(null, ["clock"]), [], "no list")

        // ---- what the strip draws ------------------------------------------
        // A widget with nothing to say is left out, as the bar and the
        // overview leave it out; a placed recording or timer item only while
        // one runs; and while arranged, everything.
        const shows = (type, hasData, recording, timer, arranging) => N.stripShows(type, hasData, recording, timer, arranging)
        T.eq([shows("privacy", false, false, false, false), shows("nowPlaying", false, false, false, false)], [false, false],
             "\"Microphone active\" while nothing listens, a pause glyph without a player: gone")
        T.eq([shows("battery", true, false, false, false), shows("workspace", undefined, false, false, false)], [true, true],
             "a widget with something to show, or one that never says, is drawn")
        T.eq([shows("clock", true, false, false, false), shows("clock", true, true, true, false)], [true, true], "the time always")
        T.eq([shows("recording", true, false, false, false), shows("recording", true, true, false, false)], [false, true],
             "a placed recording item only while recording, not as a lone red dot")
        T.eq([shows("timer", true, false, false, false), shows("timer", true, false, true, false)], [false, true],
             "a timer item only while it runs")
        T.eq([shows("privacy", false, false, false, true), shows("recording", true, false, false, true)], [true, true],
             "arranged, every part is there to be taken hold of")

        // ---- what the editor offers ----------------------------------------
        const widgets = WidgetRegistry.availableTypes()
        const offeredAll = N.catalogue(N.BLOCKS, widgets)
        const typesOf = list => list.map(entry => entry.type)
        const unique = list => list.every((value, index) => list.indexOf(value) === index)
        T.ok(unique(typesOf(offeredAll)), "every type is offered once (the weather was there twice)")
        T.ok(unique(offeredAll.map(entry => entry.label)), "and no two under the same name (two \"Events\" before)")
        T.eq(offeredAll.find(entry => entry.type === "calendarSummary").label, "Calendar",
             "the calendar widget is called apart from the events block")
        T.eq(N.widgetLabel("battery", "Battery"), "Battery", "every other widget keeps the registry's name")
        T.eq(typesOf(offeredAll).slice(0, 4), ["weather", "media", "events", "status"], "the notch's own blocks first")
        T.eq(offeredAll.find(entry => entry.type === "weather").category, "blocks", "the weather once, as the block")
        T.ok(typesOf(offeredAll).indexOf("apps") < 0 && typesOf(offeredAll).indexOf("start") < 0, "and no piece of the dock")
        // The strip draws the time, the recording and the timer itself and a
        // widget file for anything else; three blocks have none.
        T.eq(N.BLOCKS.map(block => block.type).filter(type => !N.stripTakes(type)), ["media", "events", "status"],
             "the strip cannot draw three of the blocks")
        T.ok(N.STRIP_REFUSES.every(type => WidgetRegistry.source(type) === ""), "because none of them has a widget file")
        T.ok(N.stripTakes("weather") && N.stripTakes("clock") && widgets.every(widget => N.stripTakes(widget.name)),
             "the weather, the time and every widget it can")
        const onIsland = ["workspace", "clock", "network", "battery", "activeWindow", "media", "notificationIndicator", "status"]
        const forStrip = typesOf(N.offered(offeredAll, onIsland, "collapsed"))
        const forOverview = typesOf(N.offered(offeredAll, onIsland, "expanded"))
        T.ok(["media", "events", "status"].every(type => forStrip.indexOf(type) < 0), "the strip's list offers none of them")
        T.ok(forStrip.indexOf("weather") >= 0 && forStrip.indexOf("calendarSummary") >= 0, "but the weather and the calendar widget")
        T.ok(forOverview.indexOf("events") >= 0 && forOverview.indexOf("calendarSummary") >= 0, "the overview's list has both")
        T.ok(onIsland.every(type => forOverview.indexOf(type) < 0 && forStrip.indexOf(type) < 0),
             "and neither offers what the notch carries already")
        const groups = N.catalogueGroups(N.offered(offeredAll, onIsland, "expanded"),
                                         WidgetRegistry.categories.filter(category => !category.dockOnly))
        T.eq([groups[0].id, groups[0].label], ["blocks", "Blocks"], "the list in groups, the blocks first")
        T.eq(groups.reduce((total, group) => total + group.entries.length, 0), forOverview.length, "each entry in one group")
        T.ok(groups.every(group => group.entries.length > 0 && group.label.length > 0), "under a heading, and no empty heading")
        T.eq(N.catalogueGroups([{ type: "x", label: "X", category: "nowhere" }], []).map(group => group.id), ["other"],
             "an entry of no known group is still offered")
        T.ok(WidgetRegistry.type("workspace").icon !== Icons.arrange
             && WidgetRegistry.type("workspace").icon !== WidgetRegistry.type("quickPanel").icon,
             "the workspaces have a glyph of their own, not the editor's grid beside the control center's squares")

        // ---- an overview cell that goes while it is empty --------------------
        const cell = (type, options) => ({ type: type, options: options || {} })
        T.eq(N.hidesEmpty(cell("media", { hideEmpty: true }), false, false), true, "a block that asks to go goes while it has nothing")
        T.eq(N.hidesEmpty(cell("media", { hideEmpty: true }), true, false), false, "and comes back with the song")
        T.eq(N.hidesEmpty(cell("media", { hideEmpty: true }), false, true), false, "never while the notch is arranged")
        T.eq([N.hidesEmpty(cell("media"), false, false), N.hidesEmpty(cell("media", { hideEmpty: "yes" }), false, false)],
             [false, false], "without the option, or with anything but true, the cell keeps its place")
        T.eq([N.hidesEmpty(cell("nowPlaying", { hideEmpty: true }), false, false), N.hidesEmpty(cell("status", { hideEmpty: true }), false, false)],
             [false, false], "only the notch's own blocks that can be empty")
        T.eq(N.hidesEmpty(null, false, false), false, "no item, nothing hidden")
        T.eq(L.notchItems(island.layout, "expanded").filter(item => item.options.hideEmpty === true).map(item => item.type), ["media"],
             "Island lets its music card go while nothing plays")
        T.eq(L.notchItems(classic.layout, "expanded").filter(item => item.options.hideEmpty === true).map(item => item.type),
             ["weather", "media"], "Classic its weather without a forecast and its music")

        // ---- a page turns back ------------------------------------------------
        T.ok(N.SWIPE.returnMs >= 1000 && N.SWIPE.returnMs > N.SWIPE.idleMs,
             "a page goes back to the strip a few seconds after the pointer has left")

        // ---- the preset files say what they are --------------------------------
        const islandSpec = JSON.parse(islandFile.text())
        T.ok(islandSpec.description.indexOf("pill") < 0 && islandSpec.description.indexOf("notch") >= 0,
             "Island is described as the notch it applies, not as a pill")
        // A built-in preset sets the look and how the notch opens. The
        // accent glyphs, what the other two buttons do, swiping and where the
        // panels open are the user's own: filled in with defaults they would
        // be reset on every apply (the accent glyphs set to "all" among them).
        const personal = ["accentGlyphs", "middleAction", "rightAction", "swipe", "panelOrigin"]
        for (let i = 0; i < files.length; i++) {
            const spec = JSON.parse(files[i][1].text())
            T.ok(personal.every(key => spec.options[key] === undefined),
                 files[i][0] + ": leaves the user's own choices alone")
            T.ok(["collapsed", "expanded"].every(zone => (spec[zone] || []).every(entry =>
                     typeof entry === "string" || !entry.options || entry.options.hideEmpty === undefined
                     || N.HIDE_EMPTY_TYPES.indexOf(entry.type) >= 0)),
                 files[i][0] + ": hides only a block that can be empty")
        }

        T.finish("NotchTest")
    }
}
