import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/lock/LockCatalogue.js" as C
import "../../services/LayoutLogic.js" as L

ShellRoot {
    Component.onCompleted: {
        const types = lock => L.lockTypes(lock)
        const sizes = lock => L.lockItems(lock).map(item => [item.w, item.h])

        // ---- the catalogue ------------------------------------------------
        T.ok(C.catalogue.every(item => item.type && item.label && item.icon),
             "every entry has a type, a name and a glyph")
        T.ok(C.catalogue.every(item => item.w <= L.GRID_MAX_W && item.h <= L.GRID_MAX_H),
             "no entry starts outside the grid")
        T.ok(C.catalogue.every(item => item.w >= C.minSize(item.type).w
                                       && item.h >= C.minSize(item.type).h),
             "nor below its own floor - a start size that is clamped is not a start size")
        T.eq(C.label("clock"), "Time", "a known type is named")
        T.eq(C.label("nothing at all"), "nothing at all", "an unknown one says what it was asked")
        T.eq(C.icon("nothing at all"), "", "and carries no glyph")
        T.eq(C.size("nothing at all"), { w: 1, h: 1 }, "and starts at one step")
        T.eq(C.isKnown("media"), true, "the player is in the catalogue")
        T.eq(C.isKnown("password"), false,
             "the login block is not: it is not arranged, and nothing interactive is")
        T.eq(C.minSize("clock"), { w: 2, h: 2 }, "rolling digits name a floor")
        T.eq(C.minSize("date"), { w: 1, h: 1 }, "a line of text does not")

        // ---- the surface ---------------------------------------------------
        const d = L.defaultLock()
        T.eq(types(d), ["clock", "date", "media"], "what a fresh lock screen carries")
        T.ok(L.lockItems(d).every(item => item.id.indexOf("lock-") === 0), "its ids are its own")
        T.eq(sizes(d), [[2, 3], [2, 1], [2, 2]], "and each starts at its catalogue size")
        T.eq(types(L.sanitizeLock(null)), types(d), "a missing surface is the default one")
        T.eq(types(L.sanitizeLock({ lock: [] })), types(d), "and so is an empty one")

        // One item per pill, like the other two tile surfaces.
        const smuggled = L.sanitizeLock({ lock: [{ id: "lock-1", items: [
            { type: "clock", display: "full", size: "small", w: 2, h: 2, options: {} },
            { type: "date", display: "full", size: "small", w: 1, h: 1, options: {} }] }] })
        T.eq(types(smuggled), ["clock"], "a second item in one pill is dropped, not shown twice")

        // ---- the operations ------------------------------------------------
        const id0 = L.lockItems(d)[0].id
        T.eq(types(L.moveLockItemTo(d, id0, 2)), ["date", "media", "clock"], "an item moves")
        T.eq(types(L.removeLockItem(d, id0)), ["date", "media"], "and can be taken off")
        T.eq(types(L.addLockItem(d, "weather")), ["clock", "date", "media", "weather"],
             "and put back at the end")
        T.eq(types(L.addLockItem(d, "password")), types(d),
             "a type the catalogue does not know is refused")
        T.eq(sizes(L.setLockItemSize(d, id0, 4, 6))[0], [4, 6], "a cell takes the grid's whole size")
        T.eq(sizes(L.setLockItemSize(d, id0, 99, 99))[0], [4, 6], "never past it")
        T.eq(sizes(L.setLockItemSize(d, id0, 1, 1))[0], [2, 2], "and never below its own floor")
        T.eq(sizes(L.setLockItemSize(d, "nothing", 1, 1)), sizes(d), "an unknown id changes nothing")
        T.eq(JSON.stringify(L.defaultLock()), JSON.stringify(d), "none of it touched the input")

        // ---- it lives beside the others, and never in them -------------------
        const config = L.sanitize({ configVersion: 2, profiles: { minimal: {} } })
        T.ok(config.lock !== undefined && config.notch !== undefined,
             "the lock screen sits outside profiles, next to the notch")
        T.eq(config.profiles.minimal.lock, undefined, "and not inside one")
        T.eq(types(config.lock), types(d), "a file without one gets the default, with no migration")
        const ids = L.lockItems(config.lock).map(item => item.id)
            .concat(L.notchItems(config.notch, "expanded").map(item => item.id))
            .concat(L.quickItems(config.profiles.minimal.quick).map(item => item.id))
            .concat(L.dashboardItems(config.profiles.minimal.dashboard).map(item => item.id))
        T.eq(ids.length, new Set(ids).size, "and no surface's ids collide with another's")

        T.finish("LockSurfaceTest")
    }
}
