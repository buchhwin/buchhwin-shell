import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import "Harness.js" as T
import "../../shell/components/ScrollLogic.js" as Logic

// ScrollFeel and its arithmetic: a wheel notch is 120 px and quick notches
// add up, a touchpad's pixels count four times, a swipe that ends moving is
// flung on and one that rested is not, nothing goes past either end of the
// list, a list at its end hands the wheel on, and a move from anywhere else
// wins over a glide. The events are plain objects with the fields of a
// WheelEvent, handed to `handle()`: Quickshell has no way to turn a wheel
// here, and Qt's own order of delivery (the rows, then this, then the
// Flickable) was checked with qmltestrunner and real wheel events instead.
ShellRoot {
    id: root

    function wheel(angleY, angleX) {
        return { phase: Qt.NoScrollPhase, angleDelta: Qt.point(angleX || 0, angleY), pixelDelta: Qt.point(0, 0) }
    }
    function finger(pixelY, pixelX) {
        return { phase: Qt.ScrollUpdate, angleDelta: Qt.point(-(pixelX || 0) * 12, -pixelY * 12), pixelDelta: Qt.point(pixelX || 0, pixelY) }
    }
    function phase(which) {
        return { phase: which, angleDelta: Qt.point(0, 0), pixelDelta: Qt.point(0, 0) }
    }

    // A page of 2000 px in a 400 px view: it rests between 0 and 1600.
    Flickable {
        id: page
        width: 300
        height: 400
        contentHeight: 2000
        boundsBehavior: Flickable.StopAtBounds
        ScrollFeel { id: pageFeel; view: page; duration: 0 }
    }
    // The same with the glide and the fling of Full.
    Flickable {
        id: glide
        width: 300
        height: 400
        contentHeight: 2000
        boundsBehavior: Flickable.StopAtBounds
        ScrollFeel { id: glideFeel; view: glide; duration: 180; fling: true; flingDecay: 250; flingMax: 4800 }
    }

    // Lists need a window to lay out their delegates.
    FloatingWindow {
        visible: true
        implicitWidth: 640
        implicitHeight: 480
        // Like the select's list: a highlight kept in range must not pull
        // the list back after a scroll.
        ListView {
            id: column
            width: 300
            height: 200
            model: 50
            currentIndex: 0
            highlight: Item {}
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item { width: 300; height: 40 }
            ScrollFeel { id: columnFeel; view: column; duration: 0 }
        }
        // Like the switcher: a row of cards.
        ListView {
            id: strip
            y: 220
            width: 600
            height: 100
            orientation: ListView.Horizontal
            model: 30
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item { width: 100; height: 100 }
            ScrollFeel { id: stripFeel; view: strip; duration: 0 }
        }
    }

    Timer {
        id: laidOut
        interval: 300
        onTriggered: {
            // ---- lists --------------------------------------------------
            T.eq(column.contentHeight, 2000, "the list laid out its 50 rows")
            T.eq(columnFeel.handle(root.wheel(-120)), true, "a notch scrolls a list")
            column.forceLayout()
            T.eq(column.contentY, 120, "120 px, and the highlight's range does not pull it back")
            T.eq(columnFeel.handle(root.wheel(360)), true, "back up")
            T.eq(column.contentY, 0, "to the top and no further")
            T.eq(stripFeel.handle(root.wheel(-120)), false, "a row of cards hands an up-and-down wheel on, as Qt's does")
            T.eq(strip.contentX, 0, "and does not move")
            T.eq(stripFeel.handle(root.wheel(0, -120)), true, "a sideways wheel scrolls it")
            T.eq(strip.contentX, 120, "by a notch")
            T.finish("ScrollTest")
        }
    }

    Component.onCompleted: {
        // ---- arithmetic ---------------------------------------------------
        T.eq(Logic.wheelPixels(-120, 120), 120, "a notch towards the user scrolls 120 px down")
        T.eq(Logic.wheelPixels(120, 120), -120, "a notch away from the user scrolls up")
        T.eq(Logic.wheelPixels(-30, 120), 30, "a high-resolution wheel's quarter notch is a quarter")
        T.eq(Logic.wheelPixels(-120, 72), 72, "Qt's own step for comparison")
        T.eq(Logic.fingerPixels(-30, 4), 120, "30 touchpad pixels down are 120 px")
        T.eq(Logic.fingerPixels(30, 4), -120, "the compositor's direction is kept (natural scrolling is its sign)")
        T.eq(Logic.range(0, 2000, 400, 0, 0), { low: 0, high: 1600 }, "a page rests between its top and its end")
        T.eq(Logic.range(0, 300, 400, 0, 0), { low: 0, high: 0 }, "a page shorter than the view does not move")
        T.eq(Logic.range(-80, 2000, 400, 10, 20), { low: -90, high: 1540 }, "a list's origin and margins move both ends")
        T.eq([Logic.hasRoom(0, 120, 0, 1600), Logic.hasRoom(0, -120, 0, 1600)], [true, false], "room down from the top, none up")
        T.eq([Logic.hasRoom(1600, 120, 0, 1600), Logic.hasRoom(1599.8, 120, 0, 1600)], [false, false], "none past the end, half a pixel counts as there")
        T.eq(Logic.hasRoom(800, 0, 0, 1600), false, "no step, no room needed")
        T.eq(Logic.clamp(1700, 0, 1600), 1600, "clamped to the end")
        T.eq([Logic.easedAt(0, 120, 0, 180), Logic.easedAt(0, 120, 180, 180), Logic.easedAt(0, 120, 400, 180)], [0, 120, 120],
             "a glide starts where it was and lands where it was sent")
        T.near(Logic.easedAt(0, 120, 90, 180), 105, "half-way in time it is seven eighths there (OutCubic)", 1e-6)
        T.eq(Logic.easedAt(0, 120, 0, 0), 120, "no duration is a jump")
        T.near(Logic.flingDistance(4800, 250), 1200, "a fling covers its speed times the time constant")
        T.near(Logic.flingOffset(4800, 250, 10000), 1200, "and that is where it ends", 1e-3)
        T.near(Logic.flingOffset(4800, 250, 250), 1200 * (1 - Math.exp(-1)), "most of it in the first time constant", 1e-6)
        T.eq([Logic.flingDone(4800, 250, 100), Logic.flingDone(4800, 250, 2000)], [false, true], "a fling ends once it crawls")

        // A steady swipe of 10 events, 30 units each, 17 ms apart, lifting
        // one interval after the last: 4 x 30 / 17 ms = 7059 px/s, capped.
        const swipe = []
        for (let i = 0; i < 10; ++i) swipe.push({ t: i * 17, d: 120 })
        T.eq(Logic.releaseVelocity(swipe, 170, 4800), 4800, "a quick swipe flings at the cap")
        T.near(Logic.releaseVelocity(swipe, 170, 100000), 120 / 17 * 1000, "the speed of the last tenth of a second", 1)
        T.eq(Logic.releaseVelocity(swipe, 153 + 100, 4800), 0, "fingers that rested before they lifted do not fling")
        T.eq(Logic.releaseVelocity([{ t: 0, d: 120 }], 10, 4800), 0, "one event is no speed")
        T.eq(Logic.releaseVelocity([{ t: 0, d: 1 }, { t: 17, d: 1 }], 20, 4800), 0, "a crawl is a stop, not a throw")
        T.eq(Logic.releaseVelocity([{ t: 0, d: -120 }, { t: 17, d: -120 }], 20, 4800), -4800, "upwards too")
        let kept = []
        for (let i = 0; i < 40; ++i) kept = Logic.keepSamples(kept, { t: i * 17, d: 1 })
        T.ok(kept.length <= 13, "a long swipe keeps only the samples it needs: " + kept.length)

        // Where a real swipe lands: a touchpad sends an event every ~7 ms,
        // 180-350 px in all (recorded live, 16.10.). Doubled plus the fling
        // that is 800-1300 px, a browser's kinetic scroll, not a page.
        const steady = Logic.swipeLands(300, 40, 7, Metrics.scrollFingerFactor, Metrics.scrollFlingMax, Animations.scrollFling)
        T.ok(steady >= 1000 && steady <= 1400, "a steady 300 px swipe lands like a browser's: " + Math.round(steady))
        T.eq([Metrics.scrollNotch, Metrics.scrollFingerFactor], [120, 2], "the theme's notch and factor")
        T.eq(Animations.scroll, Animations.motionEnabled ? 180 : 0, "the glide in Full, a jump otherwise")

        // ---- a page ---------------------------------------------------------
        T.eq(pageFeel.enabled, SettingsService.value("input.browserScroll") !== false, "on unless settings.json says browserScroll: false")
        T.ok(pageFeel.parent === page.contentItem, "it sits in the content, after the rows and before the Flickable")
        T.eq(pageFeel.z, -1, "under the rows")
        T.eq(pageFeel.handle(root.wheel(-120)), true, "a notch is used")
        T.eq(page.contentY, 120, "one notch, 120 px")
        pageFeel.handle(root.wheel(-120))
        pageFeel.handle(root.wheel(-120))
        T.eq(page.contentY, 360, "three notches, 360 px")
        T.eq([pageFeel.y, pageFeel.height], [360, 400], "it follows the view over the content")
        T.eq(pageFeel.handle(root.wheel(0, -120)), false, "a sideways wheel is handed on in a page that does not scroll sideways")
        T.eq(page.contentX, 0, "and nothing moves across")
        T.eq(pageFeel.handle(root.finger(-30)), true, "a touchpad event is used")
        T.eq(page.contentY, 420, "twice its 30 pixels")
        T.eq(pageFeel.handle(root.finger(30)), true, "and back the other way")
        T.eq(page.contentY, 360, "in the direction the compositor sent")
        // Qt on Wayland fills pixelDelta for a wheel notch too (15 per detent):
        // without a phase it is still a notch, not a 15-pixel swipe.
        T.eq(pageFeel.handle({ phase: Qt.NoScrollPhase, angleDelta: Qt.point(0, -120), pixelDelta: Qt.point(0, -15) }), true,
             "a notch with Wayland's pixelDelta is used")
        T.eq(page.contentY, 480, "as a notch: 120 px")
        page.contentY = 360
        page.contentY = 1550
        T.eq(pageFeel.handle(root.phase(Qt.ScrollBegin)), false, "a swipe begins")
        T.eq(pageFeel.handle(root.finger(-30)), true, "a swipe near the end is used")
        T.eq(page.contentY, 1600, "and stops at the end")
        // Handed on, the Flickable added this update to where the swipe
        // began and the list jumped back there (pitfall 105).
        T.eq(pageFeel.handle(root.finger(-30)), true, "the rest of a swipe this list carried stays with it at the end")
        T.eq(page.contentY, 1600, "and moves nothing")
        T.eq(pageFeel.handle(root.phase(Qt.ScrollEnd)), false, "the swipe ends")
        T.eq(pageFeel.handle(root.phase(Qt.ScrollBegin)), false, "a new one begins at the end")
        T.eq(pageFeel.handle(root.finger(-30)), false, "one that never moved the list goes on to what is around it")
        T.eq(pageFeel.handle(root.finger(30)), true, "until it turns back: then the list takes it")
        T.eq(pageFeel.handle(root.finger(-30)), true, "and keeps it, to the end again")
        T.eq(pageFeel.handle(root.phase(Qt.ScrollEnd)), false, "the swipe ends")
        page.contentY = 1600
        T.eq(pageFeel.handle(root.wheel(-120)), false, "the wheel at the end goes on as before")
        T.eq(page.contentY, 1600, "nothing moved")
        T.eq(pageFeel.handle(root.wheel(120)), true, "up from the end is used again")
        T.eq(pageFeel.handle(root.phase(Qt.ScrollBegin)), false, "a swipe's start is everybody's news, never kept")
        T.eq(pageFeel.handle(root.phase(Qt.ScrollEnd)), false, "so is its end")
        page.interactive = false
        T.eq(pageFeel.enabled, false, "a view that takes no input gets no scrolling from here either")
        page.interactive = true
        T.eq(pageFeel.enabled, SettingsService.value("input.browserScroll") !== false, "and gets it back")

        // ---- a glide --------------------------------------------------------
        T.eq(glideFeel.handle(root.wheel(-120)), true, "a notch starts a glide")
        T.eq([glide.contentY, glideFeel.motions.y.kind, glideFeel.motions.y.to], [0, "ease", 120], "towards 120")
        glideFeel.handle(root.wheel(-120))
        T.eq(glideFeel.motions.y.to, 240, "a second notch during the glide adds to where it goes")
        T.eq(glideFeel.scrolling, true, "and the list says it is scrolling")
        glideFeel.motions.y.start -= 1000
        glideFeel.step()
        T.eq([glide.contentY, glideFeel.motions.y.kind], [240, ""], "the glide lands")
        glide.contentY = 1500
        glideFeel.handle(root.wheel(-120))
        T.eq(glideFeel.motions.y.to, 1600, "a glide goes no further than the end")
        T.eq(glideFeel.handle(root.wheel(-120)), true, "while it is still on its way there the wheel stays with it")
        glide.contentY = 700
        glideFeel.step()
        T.eq([glide.contentY, glideFeel.motions.y.kind], [700, ""], "a move from anywhere else (keys, a jump to a row) wins")

        // ---- a fling --------------------------------------------------------
        glideFeel.handle(root.phase(Qt.ScrollBegin))
        const now = Date.now()
        glideFeel.samples = { y: [{ t: now - 51, d: 120 }, { t: now - 34, d: 120 }, { t: now - 17, d: 120 }], x: [] }
        glideFeel.handle(root.phase(Qt.ScrollEnd))
        T.eq([glideFeel.motions.y.kind, glideFeel.motions.y.velocity], ["fling", 4800], "a swipe that lifts moving is flung on")
        glideFeel.motions.y.start -= 10000
        glideFeel.step()
        T.eq([Math.round(glide.contentY), glideFeel.motions.y.kind], [1600, ""], "and a fling stops at the end of the list")
        glideFeel.handle(root.phase(Qt.ScrollBegin))
        glideFeel.samples = { y: [{ t: now - 400, d: 120 }, { t: now - 383, d: 120 }], x: [] }
        glideFeel.handle(root.phase(Qt.ScrollEnd))
        T.eq(glideFeel.motions.y.kind, "", "fingers that stopped before lifting leave the list where it is")
        glideFeel.fling = false
        glideFeel.samples = { y: [{ t: Date.now() - 34, d: 120 }, { t: Date.now() - 17, d: 120 }], x: [] }
        glideFeel.handle(root.phase(Qt.ScrollEnd))
        T.eq(glideFeel.motions.y.kind, "", "no fling in Reduced and Off")
        glideFeel.fling = true
        glide.contentY = 400
        glideFeel.samples = { y: [{ t: Date.now() - 34, d: 120 }, { t: Date.now() - 17, d: 120 }], x: [] }
        glideFeel.handle(root.phase(Qt.ScrollEnd))
        T.eq(glideFeel.motions.y.kind, "fling", "flinging")
        glideFeel.handle(root.finger(-5))
        T.eq(glideFeel.motions.y.kind, "", "fingers on the pad again stop a fling")
        glideFeel.handle(root.wheel(-120))
        glideFeel.enabled = false
        T.eq(glideFeel.motions.y.kind, "", "switched off, nothing keeps moving")

        laidOut.start()
    }
}
