import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.shell.components
import "Harness.js" as T

// The shared controls' newer manners, where they can be held to account
// without a window: the select's filter (opening clears it, a filter that
// matches nothing says so, Enter on nothing takes nothing), the field's error
// outline, and the disabled look of the chip, the segments, the select and
// the field - dimmed, and then nothing answers. Then the segments that draw
// only a glyph: their label is their name and their tooltip. Then the
// slider's keys (a whole gesture, `moved` and `released`), its wheel (a step
// per notch, a swipe left to the page unless Ctrl is held) and its fill from a
// middle, Escape in a field (back to what it had, not empty), and the inks of
// a selected row. Where the focus goes as a select opens and closes needs a
// window, which these tests do not open; one small window lays out the
// editor toolbar's two segment controls at their own width, which is where a
// label used to be cut.
ShellRoot {
    id: root
    property int chipFired: 0
    property var chosen: []
    property var slid: []

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
    function findAll(item, test, out) {
        const list = out || []
        if (!item) return list
        if (test(item)) list.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) findAll(kids[i], test, list)
        return list
    }
    function textItem(item, words) {
        return find(item, child => child.text === words && child.role !== undefined)
    }

    Item {
        id: host
        width: 600
        height: 400
        readonly property Item toolTipLayer: layer

        Column {
            width: parent.width
            ShellSelect {
                id: select
                width: 300
                filterable: true
                options: [{ value: "a", label: "Alpha" }, { value: "b", label: "Beta" }, { value: "c", label: "Gamma" }]
                current: "a"
                onSelected: value => root.chosen.push(value)
            }
            ShellTextField { id: field; width: 300; focusOnTab: true }
            ChipButton { id: chip; title: "Chip"; focusOnTab: true; onClicked: root.chipFired += 1 }
            SegmentedControl {
                id: segments
                width: 300
                compact: true
                focusOnTab: true
                options: [{ value: "one", label: "First", icon: "1" },
                          { value: "two", label: "Second", icon: "2" },
                          { value: "three", label: "Third" }]
                current: "one"
                onSelected: value => root.chosen.push(value)
            }
            SegmentedControl {
                id: tabs
                width: 300
                style: "underline"
                options: [{ value: "x", label: "Ex" }, { value: "y", label: "Why" }]
                current: "x"
            }
            // Only `moved`, like the volume and brightness sliders.
            ShellSlider {
                id: level
                width: 220
                value: 0.5
                onMoved: value => root.slid.push("moved " + value.toFixed(2))
                onReleased: value => root.slid.push("released " + value.toFixed(2))
            }
            ShellSlider { id: speed; width: 220; from: -1; to: 1; origin: 0; value: 0.5 }
            ShellTextField { id: stored; width: 300; text: "https://search.example/?q=%s" }
            ShellTextField {
                id: entry
                width: 300
                // Like Add shortcut: Return hands the text on and empties the
                // field for the next one.
                onAccepted: text = ""
            }
            ListRow { id: chosenRow; width: 300; title: "Row"; subtitle: "Second line"; trailingText: "Now"; selected: true }
            ChipButton { id: onChip; title: "Dark mode"; subtitle: "On"; active: true }
        }
        ToolTipLayer { id: layer }
    }

    // The layout editor's toolbar: both controls at their own width.
    FloatingWindow {
        id: toolbarWindow
        visible: true
        implicitWidth: 720
        implicitHeight: 120
        Row {
            SegmentedControl {
                id: profileModes
                options: ["Minimal", "Work", "Gaming", "Laptop", "Docked"].map(name => ({ value: name, label: name }))
                current: "Minimal"
            }
            SegmentedControl {
                id: desktopModes
                options: [{ value: "widgets", label: "Widgets", icon: Icons.arrange },
                          { value: "pills", label: "Bar", icon: Icons.grid },
                          { value: "notch", label: "Notch", icon: Icons.window }]
                current: "widgets"
            }
        }
        // A passphrase field and somewhere else for the focus to go: what
        // Escape goes back to lives only as long as the focus.
        Row {
            y: Metrics.controlHeightLg * 2
            ShellTextField { id: secret; width: 300; echoMode: TextInput.Password; onAccepted: {} }
            ShellButton { id: elsewhere; text: "Elsewhere"; focusOnTab: true }
            // Three options: no filter, so the list is walked from the header.
            ShellSelect {
                id: plain
                width: 160
                options: [{ value: "a", label: "Alpha" }, { value: "b", label: "Beta" }, { value: "c", label: "Gamma" }]
                current: "a"
            }
        }
        // A link that goes somewhere carries its chevron after the words,
        // and an accent button that cannot act drops the accent.
        Row {
            y: Metrics.controlHeightLg * 3
            ShellButton { id: forwardLink; text: "All apps"; trailingIcon: Icons.forward; variant: "ghost" }
            ShellButton { id: offAccent; icon: Icons.play; toolTip: "Play"; variant: "accent"; enabledState: false }
            ShellButton { id: onAccent; icon: Icons.play; toolTip: "Play"; variant: "accent" }
        }
    }
    Timer {
        id: laidOut
        interval: 300
        onTriggered: {
            const labels = root.findAll(profileModes, child => child.truncated !== undefined && child.role !== undefined && child.visible)
                .concat(root.findAll(desktopModes, child => child.truncated !== undefined && child.role !== undefined && child.visible))
            T.eq(labels.map(label => label.text), ["Minimal", "Work", "Gaming", "Laptop", "Docked", "Widgets", "Bar", "Notch"], "the toolbar's labels")
            T.eq(labels.filter(label => label.truncated).map(label => label.text), [],
                 "at its own width a pill control cuts no label (the trough's inset is asked for)")
            const row = root.find(profileModes, child => child instanceof RowLayout)
            T.eq(profileModes.implicitWidth, row.implicitWidth + Metrics.spaceXs * 2, "the inset on both sides")

            // ---- field: no passphrase kept past the focus ----------------
            const secretInput = root.find(secret, child => child instanceof TextInput)
            secret.focusInput(Qt.TabFocusReason)
            T.eq([secret.inputActiveFocus, secret.savedText], [true, ""], "focused empty, Escape would clear")
            secretInput.text = "hunter2"
            secretInput.accepted()
            T.eq(secret.savedText, "hunter2", "Return kept with the focus: Escape keeps what was handed on")
            elsewhere.forceActiveFocus()
            T.eq([secret.inputActiveFocus, secret.savedText], [false, ""], "the focus gone, no copy of the passphrase is left")
            secret.text = ""
            T.eq(secret.revert(), false, "and nothing can put it back once the dialog has emptied the field")

            // ---- the focus ring: built while it is shown -------------------
            elsewhere.forceActiveFocus()
            const ringOf = control => root.find(control, child => child.controlRadius !== undefined && child.inset !== undefined)
            const outlinesOf = ring => root.find(ring, child => child instanceof Loader)
            T.ok(ringOf(elsewhere).active && outlinesOf(ringOf(elsewhere)).item !== null, "the focused button's ring is drawn")
            T.ok(!ringOf(forwardLink).active && outlinesOf(ringOf(forwardLink)).item === null,
                 "a button without the focus has no outlines built at all")

            // ---- select: a click hands the header the keys ---------------
            plain.openList(false)
            const plainHeader = root.find(plain, child => child instanceof Rectangle && child.parent === plain && child.down !== undefined)
            T.eq([plain.expanded, plainHeader.activeFocus, plain.quietHeader], [true, true, true],
                 "a click on a list without a filter gives its header the focus, quietly")
            const plainRing = root.find(plainHeader, child => child.controlRadius !== undefined)
            T.eq(plainRing.active, false, "with no ring: the open list marks the control")
            plainHeader.Keys.escapePressed(null)
            T.eq([plain.expanded, elsewhere.activeFocus], [false, true],
                 "so Escape closes the list (not the panel) and hands the focus back")
            plain.focusInput(Qt.TabFocusReason)
            plain.openList(false)
            T.eq([plain.quietHeader, plainRing.active], [false, true], "a header the keyboard already had keeps its ring")
            plain.closeList()

            // ---- button: a trailing glyph, an accent that is off ----------
            const words = root.textItem(forwardLink, "All apps")
            const chevron = root.find(forwardLink, child => child.glyph === Icons.forward)
            T.ok(words !== null && chevron !== null && chevron.visible, "the link has its words and its chevron")
            if (words && chevron) T.ok(chevron.x > words.x + words.width - 1, "the chevron comes after the words")
            T.ok(forwardLink.implicitWidth >= words.implicitWidth + chevron.implicitWidth + forwardLink.sidePadding * 2,
                 "and the button is wide enough for both")
            T.eq(forwardLink.sidePadding, Metrics.controlPadding, "the air beside the words, for a margin that takes it back")
            const leading = root.findAll(forwardLink, child => child.glyph !== undefined && child.visible)
            T.eq(leading.length, 1, "no leading glyph without an icon")
            T.ok(Qt.colorEqual(offAccent.color, Colors.surface2), "an accent button that cannot act is a grey disc, not a faded accent")
            T.ok(Qt.colorEqual(offAccent.foreground, Colors.mutedText), "with the muted ink")
            T.ok(offAccent.opacity < 1, "and dimmed like every disabled button")
            T.ok(Qt.colorEqual(onAccent.color, Colors.accentFill) && Qt.colorEqual(onAccent.foreground, Colors.accentFillText),
                 "one that can act keeps the accent, as a fill with its words")

            // Last, as it takes the window away: an open list goes with its
            // window, as a panel's does when the panel closes.
            plain.openList(false)
            T.eq(plain.expanded, true, "a list open in a window")
            toolbarWindow.visible = false
            T.eq(plain.expanded, false, "goes with the window")
            T.finish("ControlsTest")
        }
    }

    Component.onCompleted: {
        // ---- select -----------------------------------------------------
        T.eq(select.listHeight, Metrics.selectListHeight, "the list height is the theme's")
        select.openList(true)
        T.eq([select.expanded, select.filter], [true, ""], "Space opens it with an empty filter")
        select.filter = "et"
        T.eq(select.visibleOptions.map(option => option.value), ["b"], "the filter narrows the list")
        const none = root.textItem(select, "No matches")
        T.ok(none !== null, "there is a line for a filter that matches nothing")
        T.eq(none.visible, false, "and it is hidden while something matches")
        select.filter = "zzz"
        T.eq([select.visibleOptions.length, none.visible], [0, true], "a filter that matches nothing says so")
        select.closeList()
        T.eq(select.expanded, false, "closing closes")
        select.openList(false)
        T.eq([select.filter, none.visible], ["", false], "and opening again starts from an empty filter")
        T.eq(select.quietFilter, true, "opened by a click, the filter's focus is a quiet one")
        select.closeList()

        select.enabledState = false
        T.eq(select.opacity, Effects.disabledOpacity, "a disabled select is dimmed")
        select.openList(true)
        T.eq(select.expanded, false, "and does not open")
        select.step(1)
        T.eq(root.chosen, [], "nor step")
        const selectMouse = root.find(select, child => child instanceof MouseArea)
        T.eq(selectMouse.enabled, false, "nor take a click")
        select.enabledState = true
        select.openList(true)
        select.enabledState = false
        T.eq(select.expanded, false, "disabling an open select closes it")
        select.enabledState = true
        select.step(1)
        T.eq(root.chosen, ["b"], "enabled again, it steps")

        // ---- field ------------------------------------------------------
        T.ok(Qt.colorEqual(field.border.color, "transparent"), "a field without an error has no outline")
        field.error = true
        T.ok(Qt.colorEqual(field.border.color, Colors.danger), "an error is a danger outline")
        field.error = false
        field.enabledState = false
        const input = root.find(field, child => child instanceof TextInput)
        T.eq([field.opacity, input.enabled], [Effects.disabledOpacity, false], "a disabled field is dimmed and takes nothing")
        field.focusInput()
        T.eq(field.quietFocus, false, "and handing it the focus leaves no quiet flag behind")
        field.enabledState = true

        // ---- chip -------------------------------------------------------
        chip.enabledState = false
        const chipMouse = root.find(chip, child => child instanceof MouseArea)
        T.eq([chip.opacity, chip.activeFocusOnTab, chipMouse.enabled], [Effects.disabledOpacity, false, false],
             "a disabled chip is dimmed, out of the tab order and deaf to the mouse")
        chip.Keys.spacePressed(null)
        chip.Keys.returnPressed(null)
        chip.Keys.enterPressed(null)
        chip.activate()
        T.eq(root.chipFired, 0, "and to the keys")
        chip.enabledState = true
        chip.Keys.spacePressed(null)
        T.eq([root.chipFired, chip.activeFocusOnTab], [1, true], "enabled again, it answers")

        // ---- segments ---------------------------------------------------
        const segs = root.findAll(segments, child => child.iconOnly !== undefined)
        T.eq(segs.map(segment => segment.iconOnly), [false, true, false],
             "compact draws the chosen one's label and the glyph of the others; a segment without a glyph keeps its label")
        const tipOf = segment => root.find(segment, child => child.anchorItem === segment)
        T.eq(segs.map(segment => tipOf(segment).text), ["", "Second", ""], "a glyph on its own has its label as a tooltip")
        T.eq(segs.map(segment => segment.Accessible.name), ["First", "Second", "Third"], "every segment is named by its label")
        tipOf(segs[1]).show()
        T.eq(layer.label, "Second", "the tooltip reaches the layer")
        tipOf(segs[1]).release()
        T.eq(layer.label, "", "and goes again")

        segments.enabledState = false
        T.eq(segments.opacity, Effects.disabledOpacity, "disabled segments are dimmed")
        T.eq(segments.activeFocusOnTab, false, "and out of the tab order")
        segments.Keys.rightPressed(null)
        segments.choose("two")
        T.eq(root.chosen, ["b"], "and neither the arrows nor a choice reach the caller")
        T.eq(tipOf(segs[1]).text, "", "nor does a dimmed glyph explain itself")
        T.ok(root.findAll(segments, child => child instanceof MouseArea).every(area => !area.enabled), "nor take a click")
        segments.enabledState = true
        segments.Keys.rightPressed(null)
        T.eq(root.chosen, ["b", "two"], "enabled again, the arrows step")

        const tabSegs = root.findAll(tabs, child => child.iconOnly !== undefined)
        T.eq(tabSegs.map(segment => segment.iconOnly), [false, false], "full width draws every label")
        const line = root.findAll(tabs, child => child instanceof Rectangle && child.parent === tabs)[2]
        T.ok(Qt.colorEqual(line.color, Colors.accentLine), "the underline is the readable accent line")
        const capsule = root.findAll(segments, child => child instanceof Rectangle && child.parent === segments)[2]
        T.ok(Qt.colorEqual(capsule.border.color, Colors.segmentBorder), "the selected capsule has the segment's own edge")

        // ---- slider -----------------------------------------------------
        level.Keys.rightPressed(null)
        level.Keys.leftPressed(null)
        T.eq(root.slid, ["moved 0.55", "released 0.55", "moved 0.45", "released 0.45"],
             "an arrow is a whole gesture: moved, then released")
        level.commit(1)
        T.eq(root.slid.slice(4), ["moved 1.00", "released 1.00"], "and so is the end a key goes to")
        level.enabledState = false
        level.Keys.rightPressed(null)
        T.eq(root.slid.length, 6, "a disabled slider moves nothing")
        level.enabledState = true
        level.value = 0.5
        T.eq([level.wheelTarget(1), level.wheelTarget(-1)], [0.55, 0.45], "a wheel step is a twentieth either way")
        T.ok(isNaN(level.wheelTarget(0)), "no step is no target")
        level.value = 1
        T.eq(level.wheelTarget(1), 1, "and none past the end")
        level.value = 0.5
        // The wheel itself, with plain events (WheelLogic has the rules and
        // their test). There is no window to give the slider the focus, so
        // Ctrl stands in for it.
        const withCtrl = (phase, angle, pixels) => ({ phase: phase, angleDelta: Qt.point(0, angle),
                                                     pixelDelta: Qt.point(0, pixels), modifiers: Qt.ControlModifier })
        root.slid = []
        const eighths = [0, 1, 2, 3, 4, 5, 6, 7].map(() => level.wheel(withCtrl(Qt.NoScrollPhase, 15, 0)))
        T.eq(eighths, [true, true, true, true, true, true, true, true], "a fine wheel's eighths are the slider's")
        T.eq(root.slid, ["moved 0.55", "released 0.55"], "and eight of them are one step, not eight")
        root.slid = []
        T.eq(level.wheel({ phase: Qt.ScrollUpdate, angleDelta: Qt.point(0, -100), pixelDelta: Qt.point(0, -8), modifiers: 0 }),
             false, "a swipe without Ctrl goes on to the page")
        T.eq(level.wheel(withCtrl(Qt.ScrollBegin, 0, 0)), false, "a swipe's begin always goes on")
        T.eq(level.wheel(withCtrl(Qt.ScrollUpdate, -480, -40)), true, "a swipe under Ctrl is the slider's")
        T.eq(root.slid, ["moved 0.45", "released 0.45"], "one step for 40 px of travel")
        level.wheelCarry = null
        const fillOf = slider => root.find(slider, child => child instanceof Rectangle && child.parent !== slider)
        const levelTrack = fillOf(level).parent
        T.eq([fillOf(level).x, fillOf(level).width], [0, levelTrack.width * 0.5], "a level fills from the left end")
        const speedTrack = fillOf(speed).parent
        T.eq([fillOf(speed).x, fillOf(speed).width], [speedTrack.width * 0.5, speedTrack.width * 0.25],
             "a value with a middle fills from the middle to the knob")
        // A track's position creeps on a second at a time: no spring for it.
        level.glide = false
        level.value = 0.52
        T.near(level.shownRatio, 0.52, "without the glide a new value is drawn at once")
        level.value = 0.5
        level.glide = true
        T.ok(Qt.colorEqual(fillOf(level).color, Colors.accentFill), "the fill is the accent made for fills")

        // ---- field: Escape ----------------------------------------------
        const storedInput = root.find(stored, child => child instanceof TextInput)
        stored.savedText = stored.text   // what focusing the field does
        storedInput.text = "https://search.example/?q="
        stored.edited = true
        storedInput.Keys.escapePressed(null)
        T.eq([stored.text, stored.edited], ["https://search.example/?q=%s", false],
             "Escape puts the stored value back instead of an empty field")
        T.eq(stored.revert(), false, "and the next Escape has nothing to put back: it is the owner's")
        const searchInput = root.find(field, child => child instanceof TextInput)
        field.savedText = ""
        searchInput.text = "vol"
        T.eq([field.revert(), field.text], [true, ""], "a field that got the focus empty is cleared, as a search is")
        const entryInput = root.find(entry, child => child instanceof TextInput)
        entryInput.text = "kitty"
        entryInput.accepted()
        T.eq([entry.text, entry.savedText], ["", ""], "Return hands on; what the owner leaves is what Escape keeps")

        // ---- inks on a highlight -----------------------------------------
        const rowContent = root.find(chosenRow, child => child.subtitleColor !== undefined)
        T.ok(Qt.colorEqual(rowContent.subtitleColor, Colors.mutedOnSoft), "a selected row's second line is the muted ink made for the tint")
        T.ok(Qt.colorEqual(rowContent.iconColor, Colors.accentOnSoft), "its glyph the accent made for the tint")
        T.ok(Qt.colorEqual(root.textItem(chosenRow, "Now").color, Colors.mutedOnSoft), "and its trailing text too")
        const chipContent = root.find(onChip, child => child.subtitleColor !== undefined)
        T.ok(Qt.colorEqual(chipContent.titleColor, Colors.accentOnSoft) && Qt.colorEqual(chipContent.subtitleColor, Colors.mutedOnSoft),
             "an active chip's title and second line likewise")

        laidOut.start()
    }
}
