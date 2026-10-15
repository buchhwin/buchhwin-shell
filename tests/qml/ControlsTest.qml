import Quickshell
import QtQuick
import qs.theme
import qs.shell.components
import "Harness.js" as T

// The shared controls' newer manners, where they can be held to account
// without a window: the select's filter (opening clears it, a filter that
// matches nothing says so, Enter on nothing takes nothing), the field's error
// outline, and the disabled look of the chip, the segments, the select and
// the field - dimmed, and then nothing answers. Last, the segments that draw
// only a glyph: their label is their name and their tooltip. Where the focus
// goes as a select opens and closes needs a window, which these tests do not
// open.
ShellRoot {
    id: root
    property int chipFired: 0
    property var chosen: []

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
        }
        ToolTipLayer { id: layer }
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

        T.finish("ControlsTest")
    }
}
