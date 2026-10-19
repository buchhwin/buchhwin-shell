//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import qs.shell.editor
import "Harness.js" as T
import "../../services/LayoutLogic.js" as Logic
import "../../shell/editor/EditLogic.js" as EditLogic

// The layout editor's pieces over the sandboxed LayoutService: a real
// WidgetCard in a Repeater bound to placementIds, as EditLayer has it, with a
// stand-in for the editor around it (EditLayer itself is a layer window,
// which cannot be made offscreen - testing.md pitfall 87).
//
// A dragged card keeps its place a binding: after a drag, an undo moves the
// card back with the stored widget, and two arrow-key nudges (EditLayer's,
// read from the rects the card reports) move it two steps. A drag takes its
// undo step at the drop, so one Escape ended, or one let go where it began,
// leaves none; the rest of a press Escape ended moves nothing. A click on the
// resize handle takes no step either. An edit that changes nothing takes no
// step and no write (EditLogic), a full list of steps included. The bar's
// inspector leaves a pill where it is when its own zone is clicked, and the
// bar's overlay lets go of a drag when it is hidden or destroyed.
//
// It runs under the lock screen's shell id: nothing here needs the shell's,
// and there no notification server is asked for on the session's bus
// (pitfall 82, 86). The card is a CPU widget, which reads /proc and nothing
// else.
ShellRoot {
    id: root
    property int waits: 0
    property string cardId: ""
    property bool overlayShown: true
    property bool overlayBuilt: true

    FloatingWindow {
        implicitWidth: 1920
        implicitHeight: 1200
        Item {
            id: ed
            width: 1920
            height: 1200
            property var selection: []
            property bool gridEnabled: false
            property var rects: ({})
            property var guides: []
            readonly property string screenName: "TEST-1"
            function reportRect(id, x, y, w, h) { rects[id] = { x: x, y: y, width: w, height: h } }
            function forgetRect(id) { delete rects[id] }
            function otherRects(id) { return [] }
            function placementIndex(id) { return 0 }
            function takeFocus() {}
            function select(id, additive) { selection = [id] }
            function change(callback) { EditLogic.change(LayoutService, callback) }
            // EditLayer.nudge, as it is there.
            readonly property var primary: selection.length === 1 ? LayoutService.item(selection[0]) : null
            function nudge(dx, dy) {
                if (!primary || !rects[primary.id]) return
                const rect = rects[primary.id]
                const left = Math.max(0, Math.min(width - rect.width, rect.x + dx))
                const top = Math.max(0, Math.min(height - rect.height, rect.y + dy))
                change(() => LayoutService.updateItem(primary.id,
                    Logic.relativePosition(left, top, rect.width, rect.height, width, height)))
            }

            Repeater {
                id: cards
                model: LayoutService.loaded ? LayoutService.placementIds("TEST-1", true) : []
                WidgetCard {
                    required property string modelData
                    placementId: modelData
                    editor: ed
                }
            }
        }

        // The bar's side of the editor: what BarInspector and BarEditOverlay
        // read of EditLayer's editorRoot.
        Item {
            id: barEd
            property string barPill: ""
            property int barItem: -1
            readonly property string zoneTarget: "bar"
            readonly property bool zonesMode: true
            readonly property string screenName: "TEST-1"
            readonly property var zones: LayoutService.zonesOf("bar")
            readonly property var barPlace: barPill.length && LayoutService.revision >= 0 ? LayoutService.pillPlace("bar", barPill) : null
            readonly property var barPillEntry: barPlace ? ((zones[barPlace.zone] || [])[barPlace.index] || null) : null
            function selectBar(id, index) { barPill = id; barItem = index }
            function takeFocus() {}
            function barPillLabel(id) { return "" }

            BarInspector {
                id: inspector
                editor: barEd
                width: 280
                height: 900
            }
            Loader {
                id: overlayLoader
                active: root.overlayBuilt
                sourceComponent: BarEditOverlay {
                    editor: barEd
                    target: "bar"
                    visible: root.overlayShown
                    width: 1920
                    height: 1200
                }
            }
        }
    }

    function cardFor(id) {
        for (let index = 0; index < cards.count; ++index) {
            const card = cards.itemAt(index)
            if (card && card.placementId === id) return card
        }
        return null
    }
    function steps() { return LayoutService.undoStack.length }
    // A control inside the inspector by the name a screen reader gives it.
    function control(item, name) {
        if (!item) return null
        if (item.accessibleName === name) return item
        for (const child of item.children) {
            const found = control(child, name)
            if (found) return found
        }
        return null
    }
    function leftZone() { return LayoutService.zonesOf("bar").left.map(pill => pill.id) }

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.waits += 1
            const there = LayoutService.loaded && LayoutService.stateSettled && !LayoutService.builtinApplying.length
            if (!there && root.waits < 250) return
            stop()
            T.ok(LayoutService.loaded && !LayoutService.readOnly, "the layout loads in the sandbox, writable")
            LayoutService.beginChange()
            root.cardId = LayoutService.addWidget("TEST-1", "cpu")
            LayoutService.save()
            T.ok(root.cardId.length > 0, "a CPU widget on the test screen")
            Qt.callLater(root.cardCases)
        }
    }

    function cardCases() {
        const id = root.cardId
        const card = cardFor(id)
        T.ok(card !== null, "its card is there (" + cards.count + " cards)")
        if (!card) { T.finish("EditorCardTest"); return }
        ed.selection = [id]
        const rest0 = card.restingPosition.x
        T.near(card.x, rest0, "the card rests where the widget is stored", 0.5)

        // ---- a drag, then undo and two nudges -----------------------------------------------
        const target = rest0 > 960 ? 300 : 1500
        const before = steps()
        card.press(Qt.point(card.x + 10, card.y + 10))
        card.dragTo(Qt.point(target + 10, card.y + 10), true)
        T.eq([card.dragging, steps()], [true, before], "dragging, and no step taken before the drop")
        T.near(card.x, target, "the card follows the pointer", 0.5)
        card.drop()
        T.eq([card.dragging, steps()], [false, before + 1], "the drop is one step")
        T.near(card.restingPosition.x, target, "the widget is stored where it was dropped", 1)
        T.near(card.x, card.restingPosition.x, "and the card rests there", 0.5)
        LayoutService.undo()
        T.eq(cardFor(id), card, "the same card after the undo")
        T.near(card.restingPosition.x, rest0, "undo puts the stored widget back", 1)
        T.near(card.x, card.restingPosition.x, "and the card with it: its place is still a binding", 0.5)
        const nudgeFrom = card.restingPosition.x
        ed.nudge(-10, 0)
        ed.nudge(-10, 0)
        T.near(card.restingPosition.x, nudgeFrom - 20, "two nudges are two steps, read from the place the card reports", 1)
        T.near(card.x, card.restingPosition.x, "and the card follows each", 0.5)

        // ---- Escape during a drag ---------------------------------------------------------------
        const rest1 = card.restingPosition.x
        const before1 = steps()
        card.press(Qt.point(card.x + 5, card.y + 5))
        card.dragTo(Qt.point(card.x + 400, card.y + 5), true)
        T.ok(card.dragging, "a second drag")
        card.cancelDrag()
        T.eq([card.dragging, steps(), ed.guides.length], [false, before1, 0], "Escape ends it: no step, no guides")
        T.near(card.x, rest1, "the card is back where the widget rests", 0.5)
        card.dragTo(Qt.point(rest1 + 600, card.y + 5), true)
        T.eq(card.dragging, false, "the rest of that press does not start it again")
        card.drop()
        T.eq(steps(), before1, "and its release drops nothing")
        T.near(card.restingPosition.x, rest1, "the stored widget never moved", 0.5)

        // A drag let go where it began.
        const pressedAt = Qt.point(card.x + 5, card.y + 5)
        card.press(pressedAt)
        card.dragTo(Qt.point(pressedAt.x + 200, pressedAt.y), true)
        T.ok(card.dragging, "out")
        card.dragTo(pressedAt, true)
        card.drop()
        T.eq(steps(), before1, "a drag let go where it began takes no step")

        // ---- the resize handle ------------------------------------------------------------------
        const scale0 = card.entry.scale
        card.beginResize(500)
        card.endResize()
        T.eq([steps(), card.entry.scale, card.resizing], [before1, scale0, false], "a click on the handle takes no step")
        card.beginResize(500)
        card.resizeTo(540)
        T.ok(card.previewScale > scale0, "pulled: a bigger preview")
        card.cancelResize()
        T.eq([steps(), card.entry.scale, card.previewItem.scale], [before1, scale0, scale0], "a resize cancelled leaves the scale")
        card.beginResize(500)
        card.resizeTo(540)
        card.endResize()
        T.eq(steps(), before1 + 1, "a real resize is one step")
        T.ok(card.entry.scale > scale0, "and it is stored")

        // ---- EditLogic: nothing changed, no step -------------------------------------------------
        const style = card.entry.style
        const steps2 = steps()
        const text2 = LayoutService.pendingText
        T.eq(EditLogic.change(LayoutService, () => LayoutService.updateItem(id, { style: style })), false,
             "the style it has already: nothing changed")
        T.eq([steps(), LayoutService.pendingText], [steps2, text2], "no step and no write")
        T.eq(EditLogic.change(LayoutService, () => LayoutService.groupItems([id])), false, "a group of one is no group")
        T.eq(steps(), steps2, "and takes no step")
        T.eq(EditLogic.change(LayoutService, () => LayoutService.updateItem(id, { style: style === "card" ? "capsule" : "card" })), true,
             "another style is a change")
        T.ok(steps() === steps2 + 1 && LayoutService.pendingText !== text2, "one step and a write")
        while (steps() < 30) LayoutService.beginChange()
        const full = JSON.stringify(LayoutService.undoStack)
        EditLogic.change(LayoutService, () => LayoutService.updateItem(id, { visible: card.entry.visible }))
        T.eq(JSON.stringify(LayoutService.undoStack), full, "a full list keeps its oldest step through a change that changed nothing")

        // ---- a removed widget's card goes at once (there is nothing to fade) -------------------------
        LayoutService.beginChange()
        LayoutService.removeItem(id)
        LayoutService.save()
        T.eq(cardFor(id), null, "a removed widget's card is gone in the same turn")
        Qt.callLater(root.barCases)
    }

    function barCases() {
        // The list was filled above; counted from empty again.
        LayoutService.undoStack = []
        LayoutService.barAddPill("left", "cpu", "")
        LayoutService.barAddPill("left", "ram", "")
        const left = leftZone()
        T.ok(left.length >= 3, "a left zone of three pills or more")
        barEd.selectBar(left[0], -1)
        const zone = control(inspector, "Zone")
        T.ok(zone !== null, "the inspector's Zone control")
        if (!zone) { T.finish("EditorCardTest"); return }
        const before = steps()
        zone.choose("left")
        T.eq([leftZone(), steps()], [left, before], "the zone it is in: the pill stays where it is, no step")
        zone.choose("right")
        const right = LayoutService.zonesOf("bar").right.map(pill => pill.id)
        T.eq([right[right.length - 1], steps()], [left[0], before + 1], "another zone: to its end, one step")

        // ---- the bar's overlay lets go of a drag --------------------------------------------------
        const overlay = overlayLoader.item
        overlay.beginDrag(left[1])
        T.eq(LayoutService.editorDragging, left[1], "a pill is being dragged")
        root.overlayShown = false
        T.eq([LayoutService.editorDragging, overlay.dragPill], ["", ""], "hidden (the desktop mode switched): the drag ends")
        root.overlayShown = true
        overlayLoader.item.beginDrag(left[1])
        root.overlayBuilt = false
        T.eq(LayoutService.editorDragging, "", "destroyed (the editor closed under the hand): the drag ends too")
        T.finish("EditorCardTest")
    }
}
