//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import qs.shell.lock
import "Harness.js" as T
import "../../services/lock/LockLogic.js" as L
import "../../services/LayoutLogic.js" as LayoutLogic

// The lock screen itself, as the lock process runs it (the shell id above),
// offscreen and without a session lock (`surfaces: false`), on the PAM
// fixtures in tests/fixtures/pam - never on the real services: every screen
// here names a fixture, and nothing is submitted before the screen is seen
// to use it. No directory, so the screens remove no files when they unlock.
ShellRoot {
    id: root

    // A password submitted before the reader speaks: test-fingerprint-late
    // starts like pam_fprintd, silent for a second, and then waits 4 s for a
    // finger. The password has to go to test-password at once when the reader
    // speaks, not after the reader's wait.
    LockScreen {
        id: early
        nested: true
        dir: ""
        requestedService: "test-fingerprint-late"
        lidHook: "0"
        surfaces: false
    }
    // A wrong password on test-password: PAM_AUTH_ERR, the path a wrong
    // password takes at a real login.
    LockScreen {
        id: wrong
        nested: true
        dir: ""
        requestedService: "test-password"
        lidHook: "0"
        surfaces: false
    }
    // The state behind a face, for what the face asks of the session.
    LockScreen {
        id: faceState
        nested: true
        dir: ""
        requestedService: "test-password"
        lidHook: "0"
        surfaces: false
    }
    LockFace {
        id: face
        width: 1920
        height: 1200
        lockState: faceState
        screenName: ""
    }

    function find(item, test) {
        if (!item) return null
        if (test(item)) return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) {
            const found = find(kids[i], test)
            if (found) return found
        }
        return null
    }
    function lockOf(types) {
        return LayoutLogic.sanitizeLock({ lock: types.map((type, index) => ({ id: "lock-" + (index + 1),
            items: [{ type: type, display: "full", size: "small", w: 2, h: 2, options: {} }] })) })
    }
    function itemsOf(types) { return LayoutLogic.lockItems(lockOf(types)) }

    readonly property real started: Date.now()
    function at() { return Date.now() - started }

    // The early submit, as it went.
    property bool fixturesInUse: false
    property real submittedAt: -1
    property real stageAt: -1
    property bool submittedBeforeStage: false
    Connections {
        target: early
        function onFingerprintStageChanged() { if (early.fingerprintStage && root.stageAt < 0) root.stageAt = root.at() }
        function onUnlockingChanged() { if (early.unlocking) root.earlyUnlocked() }
    }

    Timer {
        // Within the reader's first second of silence, as a quick retry after
        // a typo lands there (a conversation starts 1 s after every shake).
        interval: 400
        running: root.fixturesInUse
        onTriggered: {
            early.password = "lock-test-password"
            root.submittedBeforeStage = !early.fingerprintStage
            root.submittedAt = root.at()
            early.submit()
            wrong.password = "not-the-password"
            wrong.submit()
        }
    }
    Timer {
        // The reader's wait has ended by now; without the switch the password
        // was only asked for then.
        interval: 7000
        running: root.fixturesInUse
        onTriggered: root.earlyUnlocked()
    }

    // ---- what a face asks of the session -------------------------------------
    // A turn after everything has completed, the face's own parts included.
    Timer {
        id: faceChecks
        interval: 100
        onTriggered: {
            T.eq([CalendarService.trackers, WeatherService.trackers], [0, 0],
                 "a face without events or weather asks for neither")
            faceState.lockItems = root.itemsOf(["clock", "events"])
            T.eq(CalendarService.trackers, 1, "an events block asks for the calendar")
            // The block goes at the end of the turn, and its demand with it
            // (asked at the end of the test).
            faceState.lockItems = root.itemsOf(["clock", "weather"])
            T.eq(WeatherService.trackers, 0, "the weather is only shown, never fetched")
            const backdrop = root.find(face, item => item.blurMax !== undefined && item.source !== undefined)
            T.ok(backdrop !== null, "the face has its blurred backdrop")
            if (backdrop)
                T.eq([backdrop.layer.enabled, backdrop.layer.textureSize.width, backdrop.layer.textureSize.height],
                     [true, 480, 300], "the backdrop's layer is a quarter of the screen")

            // Caps Lock and the layout: a burst of keys is one check now and
            // one after it, not a hyprctl each (it finds no Hyprland here).
            faceState.keyActivity()
            faceState.keyActivity()
            faceState.keyActivity()
            T.eq(faceState.keysUnchecked, true, "keys right after a check wait for the next one")
        }
    }

    property bool done: false
    function earlyUnlocked() {
        if (done) return
        done = true
        T.ok(submittedBeforeStage, "the password went in before the reader spoke")
        T.ok(stageAt > submittedAt && submittedAt >= 0, "and the reader spoke after it (" + submittedAt + " ms, then " + stageAt + " ms)")
        T.ok(early.unlocking, "the early password unlocks")
        T.ok(early.passwordOnly, "through the password-only service, not the reader's own prompt")
        T.ok(stageAt >= 0 && at() - stageAt < 3000, "while the reader would still be waiting (" + (at() - stageAt) + " ms after it spoke)")

        // The wrong password failed once, as at a login: one shake, the field
        // empty again, nothing said in words and nothing unlocked.
        T.eq([wrong.shakes, wrong.unlocking, wrong.password, wrong.status, wrong.passwordOnly],
             [1, false, "", "", false], "a wrong password shakes once and starts over")

        T.eq(CalendarService.trackers, 0, "the face let the calendar go with its events block")
        T.eq(faceState.keysUnchecked, false, "the burst of keys was checked once after it")
        T.finish("LockScreenTest")
    }

    Component.onCompleted: {
        // ---- the arrangement, read from layout.json ------------------------
        // Only the lock section, and the same items the whole file's sanitizer
        // gives - for the fixture, for a file without one and for nonsense.
        const fixture = {
            configVersion: 3, activeMode: "minimal",
            profiles: { default: { modes: { minimal: {} } } },
            lock: { lock: [{ id: "lock-1", items: [{ type: "clock", display: "full", size: "small", w: 2, h: 2, options: {} }] },
                           { id: "lock-2", items: [{ type: "weather", display: "full", size: "small", w: 9, h: 9, options: {} }] }] }
        }
        for (const config of [fixture, { configVersion: 3 }, { lock: "nonsense" }, { lock: { lock: [] } }, [], 7]) {
            T.eq(LayoutLogic.lockItems(LayoutLogic.sanitizeLock(config && typeof config === "object" ? config.lock : null)),
                 LayoutLogic.lockItems(LayoutLogic.sanitize(config).lock),
                 "the lock section alone gives what the whole file gives (" + JSON.stringify(config).slice(0, 40) + ")")
        }
        const fresh = wrong.lockItems
        wrong.readLayout(JSON.stringify({ configVersion: 3, lock: LayoutLogic.defaultLock() }))
        T.ok(wrong.lockItems === fresh, "a file with the default arrangement keeps the items as they are")
        wrong.readLayout(JSON.stringify(fixture))
        const read = wrong.lockItems
        T.eq(read.map(item => item.type), ["clock", "weather"], "the file's arrangement is read")
        const elsewhere = JSON.parse(JSON.stringify(fixture))
        elsewhere.activeMode = "work"
        elsewhere.profiles.default.modes.work = {}
        wrong.readLayout(JSON.stringify(elsewhere))
        T.ok(wrong.lockItems === read, "a write elsewhere in the file rebuilds nothing")
        const changed = JSON.parse(JSON.stringify(fixture))
        changed.lock.lock.pop()
        wrong.readLayout(JSON.stringify(changed))
        T.eq(wrong.lockItems.map(item => item.type), ["clock"], "a changed arrangement is taken")

        faceState.lockItems = itemsOf(["clock", "date"])
        faceChecks.start()

        // ---- the conversations -----------------------------------------------
        // Every screen here must be on a fixture before anything is typed.
        T.eq([early.mainService, early.passwordService, wrong.mainService, faceState.mainService],
             ["test-fingerprint-late", "test-password", "test-password", "test-password"], "the screens use the fixtures")
        fixturesInUse = early.mainService === "test-fingerprint-late" && early.passwordService === "test-password"
            && wrong.mainService === "test-password" && L.systemService(early.passwordService) === false
        if (!fixturesInUse) {
            done = true
            T.finish("LockScreenTest")
        }
    }
}
