import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/LayoutLogic.js" as Logic
import "../../services/profile/ProfileLogic.js" as Profile

// Super+Alt+E layout editor for every desktop mode. Widgets: add, remove,
// move, scale, group, style, show or hide them, move them between monitors.
// Bar: drag pills between the left, centre and right zone, add, remove and
// set their display. Notch: its options. Plus profiles and undo.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData
        screen: modelData
        visible: LayoutService.editMode
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "buchhwin-layout-editor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: !LayoutService.editMode ? WlrKeyboardFocus.None
            : PanelService.screen === modelData ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // The editor is its own window, so it needs its own tooltip layer: a
        // control finds one by walking up its parents, and ShellPanel's does
        // not reach here.
        ToolTipLayer { id: editorTips; z: 100 }

        FocusScope {
            id: editorRoot
            anchors.fill: parent
            focus: true
            readonly property Item toolTipLayer: editorTips
            property var selection: []
            property var guides: []
            property var rects: ({})
            property bool pickerOpen: false
            property bool gridEnabled: false
            readonly property string screenName: window.modelData.name
            readonly property var selectedItems: selection.map(id => LayoutService.item(id)).filter(Boolean)
            readonly property var primary: selectedItems.length === 1 ? selectedItems[0] : null
            readonly property bool primaryIsGroup: primary !== null && primary.members !== undefined

            // The active desktop mode decides what is edited; exactly one of
            // the three is true.
            readonly property bool widgetsMode: LayoutService.widgetsShown
            readonly property bool barMode: LayoutService.barShown
            // The order the cards are drawn in, so each one can wiggle at a
            // different point of the cycle.
            function placementIndex(id) { return LayoutService.placementIds(screenName, true).indexOf(id) }
            readonly property bool notchMode: LayoutService.notchShown

            // Bar editing: the selected pill and, inside it, an item
            // (-1 = the whole pill).
            property string barPill: ""
            property int barItem: -1
            readonly property var barPlace: barPill.length && LayoutService.revision >= 0
                ? LayoutService.barPlace(barPill) : null
            readonly property var barPillEntry: barPlace ? LayoutService.bar[barPlace.zone][barPlace.index] : null
            // Zone new pills go into: the selected pill's, otherwise the centre.
            property string addZone: "center"
            // Picker target: a new pill in `addZone` or the selected pill.
            property bool addToPill: false
            readonly property string barUnit: LayoutService.bar.style === "bar" ? "group" : "pill"
            // Where the editor's own panels may start, so the picker and the
            // inspector never cover the bar being edited. The bar is on one
            // edge, so exactly one of these three is pushed in - and `!==
            // "bottom"` used to stand for "top", which was true while those
            // were the only two edges there were: a bar on a *side* covers
            // nothing along the top and was pushing the panels down anyway.
            readonly property string barSide: barMode ? LayoutService.barEdge(screenName) : ""
            function clearOf(side) {
                return editorRoot.barSide === side
                    ? Math.max(Metrics.spaceXl, LayoutService.barBottom(screenName) + Metrics.spaceLg)
                    : Metrics.spaceXl
            }
            readonly property real contentTop: clearOf("top")
            readonly property real contentLeft: clearOf("left")
            readonly property real contentRight: clearOf("right")

            function addToBar(type) {
                if (addToPill && barPlace) {
                    const id = barPill
                    LayoutService.barAddItem(id, type, "")
                    const place = LayoutService.barPlace(id)
                    selectBar(id, place ? LayoutService.bar[place.zone][place.index].items.length - 1 : -1)
                    return
                }
                const created = LayoutService.barAddPillId(addZone, type, "")
                if (created.length) selectBar(created, 0)
            }

            function selectBar(pillId, index) {
                selection = []
                barPill = pillId
                barItem = index
                // The real bar holds the selected pill still while the others
                // lean, so the selection is visible on the bar itself.
                LayoutService.editorSelection = pillId
                if (pillId.length) {
                    const place = LayoutService.barPlace(pillId)
                    if (place) addZone = place.zone
                }
            }
            function barPillLabel(pillId) {
                const place = LayoutService.barPlace(pillId)
                if (!place) return ""
                return LayoutService.bar[place.zone][place.index].items
                    .map(entry => (WidgetRegistry.type(entry.type) || { label: entry.type }).label).join(" · ")
            }
            function cycleBarSelection(step) {
                const ids = Logic.barPillIds(LayoutService.bar)
                if (!ids.length) return
                const index = ids.indexOf(barPill)
                selectBar(ids[(index + step + ids.length) % ids.length], -1)
            }
            // Del removes the selected unit - the pill - exactly as it removes
            // the selected widget. Single items go through the inspector.
            function removeBarSelection() {
                if (!barPillEntry) return
                const id = barPill
                selectBar("", -1)
                LayoutService.barRemovePill(id)
            }
            function cycleBarDisplay() {
                if (!barPillEntry || barItem < 0) return
                const item = barPillEntry.items[barItem]
                const options = WidgetRegistry.pillDisplays(item.type).map(entry => entry.value)
                if (!options.length) return
                LayoutService.barSetDisplay(barPill, barItem, options[(options.indexOf(item.display) + 1) % options.length])
            }

            Connections {
                target: LayoutService
                function onEditModeChanged() {
                    if (LayoutService.editMode) {
                        PanelService.close()
                        PanelService.useFocusedScreen()
                        editorRoot.forceActiveFocus()
                    } else {
                        editorRoot.selection = []
                        editorRoot.pickerOpen = false
                        editorRoot.barPill = ""
                        editorRoot.barItem = -1
                    }
                }
                function onRevisionChanged() {
                    editorRoot.selection = editorRoot.selection.filter(id => LayoutService.item(id) !== null)
                    if (editorRoot.barPill.length && !LayoutService.barPlace(editorRoot.barPill)) {
                        editorRoot.barPill = ""
                        editorRoot.barItem = -1
                    }
                }
            }

            function select(id, additive) {
                if (additive) {
                    const index = selection.indexOf(id)
                    selection = index >= 0 ? selection.filter(item => item !== id) : selection.concat([id])
                } else if (selection.indexOf(id) < 0) {
                    selection = [id]
                }
            }
            function reportRect(id, x, y, width, height) {
                rects[id] = { x: x, y: y, width: width, height: height }
            }
            function forgetRect(id) { delete rects[id] }
            function otherRects(id) {
                return Object.keys(rects).filter(key => key !== id).map(key => rects[key])
            }
            function change(callback) {
                LayoutService.beginChange()
                callback()
                LayoutService.save()
            }
            function removeSelection() {
                if (!selection.length) return
                change(() => selection.slice().forEach(id => LayoutService.removeItem(id)))
                selection = []
            }

            Keys.onEscapePressed: {
                // A drag is what Escape cancels first, everywhere: closing the
                // editor out from under a held item would write the drop.
                if (LayoutService.arrangeDragging.length) notchOverlay.cancelAll()
                else if (pickerOpen) pickerOpen = false
                else if (selection.length) selection = []
                else if (barPill.length) selectBar("", -1)
                else LayoutService.editMode = false
            }
            Keys.onDeletePressed: barMode ? removeBarSelection() : removeSelection()
            function cycleSelection(step) {
                const ids = LayoutService.placementIds(screenName, true)
                if (!ids.length) return
                const index = selection.length ? ids.indexOf(selection[selection.length - 1]) : -1
                selection = [ids[(index + step + ids.length) % ids.length]]
            }
            function nudge(dx, dy) {
                if (!primary || !rects[primary.id]) return
                const rect = rects[primary.id]
                const left = Math.max(0, Math.min(width - rect.width, rect.x + dx))
                const top = Math.max(0, Math.min(height - rect.height, rect.y + dy))
                change(() => LayoutService.updateItem(primary.id,
                    Logic.relativePosition(left, top, rect.width, rect.height, width, height)))
            }
            function adjustScale(delta) {
                if (!primary) return
                change(() => LayoutService.updateItem(primary.id, {
                    scale: Math.max(Metrics.widgetScaleMin, Math.min(Metrics.widgetScaleMax, Math.round((primary.scale + delta) * 100) / 100))
                }))
            }
            function cycleStyle() {
                if (!primary) return
                const styles = ["minimal", "capsule", "card"]
                change(() => LayoutService.updateItem(primary.id, { style: styles[(styles.indexOf(primary.style) + 1) % styles.length] }))
            }

            // Bar mode speaks the same keys as widget mode: Tab walks the
            // pills, the arrow keys move the selected one along the bar (a
            // widget moves by pixels, a pill by slots - the bar lays itself
            // out), S cycles the display and Del removes what is selected.
            // Removing one item of a pill is the inspector's job, the way a
            // widget group is edited there too.
            function barKey(event) {
                if (event.key === Qt.Key_Tab) cycleBarSelection(1)
                else if (event.key === Qt.Key_Backtab) cycleBarSelection(-1)
                else if (event.key === Qt.Key_Left) LayoutService.barMovePill(barPill, -1)
                else if (event.key === Qt.Key_Right) LayoutService.barMovePill(barPill, 1)
                else if (event.key === Qt.Key_S) cycleBarDisplay()
                else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) removeBarSelection()
                else return false
                return true
            }

            // The desktop mode can also change from outside the editor
            // (Super+Alt+D), so the selection is cleared on the change itself.
            Connections {
                target: LayoutService
                function onDesktopModeChanged() {
                    editorRoot.selection = []
                    editorRoot.selectBar("", -1)
                }
            }

            Keys.onPressed: event => {
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                const step = (event.modifiers & Qt.ShiftModifier) ? Metrics.gridSize : 1
                event.accepted = true
                if (event.key === Qt.Key_Z && ctrl) LayoutService.undo()
                else if (event.key === Qt.Key_A && !notchMode) pickerOpen = !pickerOpen
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) LayoutService.editMode = false
                else if (barMode) event.accepted = barKey(event)
                else if (notchMode) event.accepted = false
                else if (event.key === Qt.Key_G) gridEnabled = !gridEnabled
                else if (event.key === Qt.Key_Tab) cycleSelection(1)
                else if (event.key === Qt.Key_Backtab) cycleSelection(-1)
                else if (event.key === Qt.Key_Left) nudge(-step, 0)
                else if (event.key === Qt.Key_Right) nudge(step, 0)
                else if (event.key === Qt.Key_Up) nudge(0, -step)
                else if (event.key === Qt.Key_Down) nudge(0, step)
                else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) adjustScale(0.05)
                else if (event.key === Qt.Key_Minus) adjustScale(-0.05)
                else if (event.key === Qt.Key_S) cycleStyle()
                else if (event.key === Qt.Key_H && primary) change(() => LayoutService.updateItem(primary.id, { visible: !primary.visible }))
                else event.accepted = false
            }

            Rectangle { anchors.fill: parent; color: Colors.scrim }

            // Grid
            Repeater {
                model: editorRoot.gridEnabled ? Math.ceil(editorRoot.width / Metrics.gridSize) : 0
                Rectangle { required property int index; x: index * Metrics.gridSize; width: Metrics.guideWidth; height: editorRoot.height; color: Colors.border }
            }
            Repeater {
                model: editorRoot.gridEnabled ? Math.ceil(editorRoot.height / Metrics.gridSize) : 0
                Rectangle { required property int index; y: index * Metrics.gridSize; height: Metrics.guideWidth; width: editorRoot.width; color: Colors.border }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    editorRoot.forceActiveFocus()
                    editorRoot.selection = []
                    editorRoot.pickerOpen = false
                    editorRoot.selectBar("", -1)
                }
            }

            Repeater {
                model: editorRoot.widgetsMode ? LayoutService.placementIds(editorRoot.screenName, true) : []
                WidgetCard {
                    required property string modelData
                    placementId: modelData
                    editor: editorRoot
                }
            }

            // Desktop mode "Bar": frames and drop targets on the real bar.
            BarEditOverlay {
                id: barOverlay
                visible: editorRoot.barMode
                editor: editorRoot
                anchors.fill: parent
            }

            // Desktop mode "Notch": the picker and the options below the
            // notch, and the frames and the drop marker on top of it.
            NotchEdit {
                visible: editorRoot.notchMode
                screenName: editorRoot.screenName
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: implicitHeight
            }
            NotchEditOverlay {
                id: notchOverlay
                visible: editorRoot.notchMode
                editor: editorRoot
                anchors.fill: parent
            }

            Repeater {
                model: editorRoot.guides
                Rectangle {
                    required property var modelData
                    color: Colors.guide
                    x: modelData.orientation === "vertical" ? modelData.position : 0
                    y: modelData.orientation === "horizontal" ? modelData.position : 0
                    width: modelData.orientation === "vertical" ? Metrics.guideWidth : editorRoot.width
                    height: modelData.orientation === "horizontal" ? Metrics.guideWidth : editorRoot.height
                }
            }

            // Toolbar
            Rectangle {
                id: toolbar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.spaceXl
                width: toolbarRow.implicitWidth + Metrics.spaceMd * 2
                height: toolbarRow.implicitHeight + Metrics.spaceMd * 2
                radius: Metrics.radiusPanel
                color: Colors.panelFor("editor")
                border.width: Metrics.borderWidth
                border.color: Colors.panelBorder
                MouseArea { anchors.fill: parent }

                RowLayout {
                    id: toolbarRow
                    anchors.centerIn: parent
                    spacing: Metrics.spaceSm

                    ShellText { text: "Layout"; role: "title"; Layout.leftMargin: Metrics.spaceSm }
                    ShellText {
                        text: LayoutService.readOnly ? "Read-only" : window.modelData.name
                        role: "small"
                        color: LayoutService.readOnly ? Colors.warning : Colors.mutedText
                        Layout.rightMargin: Metrics.spaceSm
                    }
                    SegmentedControl {
                        style: "pill"
                        current: LayoutService.activeMode
                        options: LayoutService.modeNames.map(name => ({
                            value: name,
                            label: Profile.label(name, LayoutService.templates)
                        }))
                        onSelected: value => LayoutService.setActiveMode(value)
                    }
                    // The desktop mode decides what this editor edits.
                    SegmentedControl {
                        style: "pill"
                        current: LayoutService.desktopMode
                        options: [{ value: "widgets", label: "Widgets", icon: Icons.edit },
                                  { value: "pills", label: "Bar", icon: "󰘔" },
                                  { value: "notch", label: "Notch", icon: "󱂩" }]
                        onSelected: value => { editorRoot.selection = []; editorRoot.selectBar("", -1); LayoutService.setDesktopMode(value) }
                    }
                    ShellButton {
                        visible: !editorRoot.notchMode
                        icon: Icons.add; text: "Add"
                        variant: editorRoot.pickerOpen ? "accent" : "surface"
                        onClicked: editorRoot.pickerOpen = !editorRoot.pickerOpen
                    }
                    ShellButton {
                        visible: editorRoot.widgetsMode
                        icon: Icons.grid
                        variant: editorRoot.gridEnabled ? "accent" : "surface"
                        toolTip: editorRoot.gridEnabled ? "Stop snapping to the grid" : "Snap to the grid"
                        onClicked: editorRoot.gridEnabled = !editorRoot.gridEnabled
                    }
                    ShellButton {
                        icon: Icons.undo
                        enabledState: LayoutService.undoStack.length > 0
                        toolTip: "Undo"
                        onClicked: LayoutService.undo()
                    }
                    ShellButton { text: "Done"; variant: "accent"; onClicked: LayoutService.editMode = false }
                }
            }

            ShellText {
                anchors.horizontalCenter: toolbar.horizontalCenter
                anchors.bottom: toolbar.top
                anchors.bottomMargin: Metrics.spaceSm
                // One sentence for both surfaces: the bar leaves out what only
                // free placement can do rather than saying it differently.
                text: editorRoot.notchMode ? "Drag to reorder what the notch carries · ↑ ↓ send an item to the other row · Ctrl+Z undoes · Switch the mode above · Enter done · Esc back"
                    : editorRoot.barMode ? "Drag or arrow keys · Tab selects · A adds · S changes the look · Del removes · Ctrl+Z undoes · Esc back"
                    : "Drag or arrow keys · Alt disables snapping · Shift+Click multi-selects · Tab selects · A adds · S changes the look · +/− resizes · G grid · Del removes · Ctrl+Z undoes · Esc back"
                role: "small"
                color: Colors.text
                style: Text.Outline
                styleColor: Colors.scrimStrong
            }

            // Widget and bar item picker
            EditorPanel {
                id: picker
                visible: editorRoot.pickerOpen && !editorRoot.notchMode
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: toolbar.top
                anchors.margins: Metrics.spaceXl
                // Clear of the zones while the bar is edited, whichever edge
                // it is on.
                anchors.topMargin: editorRoot.contentTop
                anchors.leftMargin: editorRoot.contentLeft
                width: Metrics.editorSidebarWidth

                title: "Add"
                contentSpacing: Metrics.spaceXs

                ColumnLayout {
                    visible: editorRoot.barMode
                    Layout.fillWidth: true
                    Layout.bottomMargin: Metrics.spaceSm
                    spacing: Metrics.spaceXs
                    SectionLabel { text: "Zone" }
                    SegmentedControl {
                        Layout.fillWidth: true
                        current: editorRoot.addZone
                        options: [{ value: "left", label: "Left" }, { value: "center", label: "Center" }, { value: "right", label: "Right" }]
                        onSelected: value => { editorRoot.addZone = value; editorRoot.addToPill = false }
                    }
                    SegmentedControl {
                        visible: editorRoot.barPill.length > 0
                        Layout.fillWidth: true
                        current: editorRoot.addToPill ? "pill" : "new"
                        options: [{ value: "new", label: "New " + editorRoot.barUnit },
                                  { value: "pill", label: "Selected " + editorRoot.barUnit }]
                        onSelected: value => editorRoot.addToPill = value === "pill"
                    }
                }
                Item { Layout.preferredHeight: editorRoot.barMode ? 0 : Metrics.spaceSm }

                Repeater {
                    model: WidgetRegistry.categories
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Metrics.spaceXxs
                        SectionLabel { text: modelData.label; Layout.topMargin: Metrics.spaceSm; Layout.leftMargin: Metrics.spaceSm }
                        Repeater {
                            model: WidgetRegistry.typesIn(modelData.id)
                            ListRow {
                                required property var modelData
                                Layout.fillWidth: true
                                compact: true
                                icon: modelData.icon
                                title: modelData.label
                                trailingText: modelData.available ? "" : (modelData.note || "")
                                opacity: modelData.available ? 1 : Effects.disabledOpacity
                                onClicked: {
                                    if (!modelData.available) return
                                    if (editorRoot.barMode) {
                                        editorRoot.addToBar(modelData.name)
                                        return
                                    }
                                    editorRoot.change(() => {
                                        const id = LayoutService.addWidget(editorRoot.screenName, modelData.name)
                                        if (id.length) editorRoot.selection = [id]
                                    })
                                }
                            }
                        }
                    }
                }
            }

            // Options of the selected pill (desktop mode "Bar").
            BarInspector {
                editor: editorRoot
                // Opposite the selected pill, so the inspector never covers it.
                x: editorRoot.pickerOpen || !editorRoot.barPlace || editorRoot.barPlace.zone === "right"
                    ? editorRoot.width - width - editorRoot.contentRight : editorRoot.contentLeft
                y: Math.max(editorRoot.contentTop, (toolbar.y - height) / 2)
                width: Metrics.editorSidebarWidth
                height: Math.min(implicitHeight, toolbar.y - editorRoot.contentTop - Metrics.spaceXl)
            }

            // Inspector
            EditorPanel {
                id: inspector
                visible: editorRoot.widgetsMode && editorRoot.selectedItems.length > 0
                // Vertically centred on the side away from the selection.
                readonly property var selectedRect: editorRoot.primary ? editorRoot.rects[editorRoot.primary.id] : null
                readonly property bool onLeft: selectedRect !== null && selectedRect !== undefined
                    && selectedRect.x + selectedRect.width / 2 > editorRoot.width * 0.75 && !editorRoot.pickerOpen
                    ? false : selectedRect && selectedRect.x + selectedRect.width / 2 > editorRoot.width / 2 ? false : !editorRoot.pickerOpen
                x: onLeft ? editorRoot.contentLeft : editorRoot.width - width - editorRoot.contentRight
                y: Math.max(editorRoot.contentTop, (toolbar.y - height) / 2)
                width: Metrics.editorSidebarWidth
                height: Math.min(implicitHeight, toolbar.y - Metrics.spaceXl * 2)

                title: editorRoot.primary === null ? editorRoot.selectedItems.length + " widgets selected" : editorRoot.primaryIsGroup ? "Group" : (WidgetRegistry.type(editorRoot.primary.type) || { label: editorRoot.primary.type }).label

                ColumnLayout {
                    visible: editorRoot.primary !== null
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    SectionLabel { text: "Style" }
                    SegmentedControl {
                        Layout.fillWidth: true
                        current: editorRoot.primary ? editorRoot.primary.style : "minimal"
                        options: [{ value: "minimal", label: "Minimal" }, { value: "capsule", label: "Capsule" }, { value: "card", label: "Card" }]
                        onSelected: value => editorRoot.change(() => LayoutService.updateItem(editorRoot.primary.id, { style: value }))
                    }
                }

                ColumnLayout {
                    visible: editorRoot.primary !== null && !editorRoot.primaryIsGroup
                        && (WidgetRegistry.type(editorRoot.primary.type) || { sizes: [] }).sizes.length > 1
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    SectionLabel { text: "Size" }
                    SegmentedControl {
                        Layout.fillWidth: true
                        current: editorRoot.primary && editorRoot.primary.size ? editorRoot.primary.size : "small"
                        options: (editorRoot.primary && WidgetRegistry.type(editorRoot.primary.type) ? WidgetRegistry.type(editorRoot.primary.type).sizes : [])
                            .map(size => ({ value: size, label: size === "small" ? "Small" : size === "medium" ? "Medium" : "Large" }))
                        onSelected: value => editorRoot.change(() => LayoutService.updateItem(editorRoot.primary.id, { size: value }))
                    }
                }

                ColumnLayout {
                    visible: editorRoot.primary !== null
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    RowLayout {
                        SectionLabel { text: "Scale" }
                        Item { Layout.fillWidth: true }
                        ShellText { text: editorRoot.primary ? Math.round(editorRoot.primary.scale * 100) + "%" : ""; role: "small" }
                    }
                    ShellSlider {
                        Layout.fillWidth: true
                        from: Metrics.widgetScaleMin
                        to: Metrics.widgetScaleMax
                        value: editorRoot.primary ? editorRoot.primary.scale : 1
                        onReleased: value => editorRoot.change(() => LayoutService.updateItem(editorRoot.primary.id, { scale: Math.round(value * 100) / 100 }))
                    }
                }

                RowLayout {
                    visible: editorRoot.primary !== null
                    Layout.fillWidth: true
                    ShellText { text: "Visible"; Layout.fillWidth: true }
                    ShellToggle {
                        checked: editorRoot.primary ? editorRoot.primary.visible : true
                        onToggled: value => editorRoot.change(() => LayoutService.updateItem(editorRoot.primary.id, { visible: value }))
                    }
                }

                ColumnLayout {
                    visible: editorRoot.primary !== null && Quickshell.screens.length > 1
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    SectionLabel { text: "Display" }
                    Repeater {
                        model: Quickshell.screens.filter(screen => screen.name !== editorRoot.screenName)
                        ShellButton {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "󰍹"
                            text: "Move to " + modelData.name
                            onClicked: {
                                const id = editorRoot.primary.id
                                editorRoot.change(() => LayoutService.moveToScreen(id, modelData.name))
                                editorRoot.selection = []
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: editorRoot.primaryIsGroup
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXs
                    SectionLabel { text: "Order" }
                    Repeater {
                        model: editorRoot.primaryIsGroup ? LayoutService.members(editorRoot.primary.id) : []
                        ListRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            compact: true
                            icon: (WidgetRegistry.type(modelData.type) || { icon: "" }).icon
                            title: (WidgetRegistry.type(modelData.type) || { label: modelData.type }).label
                            RowLayout {
                                spacing: Metrics.spaceXxs
                                ShellButton { icon: Icons.back; compact: true; variant: "ghost"
                                    onClicked: editorRoot.change(() => LayoutService.moveMember(editorRoot.primary.id, modelData.id, -1)) }
                                ShellButton { icon: Icons.forward; compact: true; variant: "ghost"
                                    onClicked: editorRoot.change(() => LayoutService.moveMember(editorRoot.primary.id, modelData.id, 1)) }
                            }
                        }
                    }
                }

                ShellButton {
                    visible: editorRoot.selectedItems.length > 1 && editorRoot.selectedItems.every(entry => entry.members === undefined)
                    Layout.fillWidth: true
                    icon: "󰕸"
                    text: "Group"
                    onClicked: editorRoot.change(() => {
                        const id = LayoutService.groupItems(editorRoot.selection)
                        if (id.length) editorRoot.selection = [id]
                    })
                }
                ShellButton {
                    visible: editorRoot.primaryIsGroup
                    Layout.fillWidth: true
                    icon: "󰕹"
                    text: "Ungroup"
                    onClicked: {
                        const id = editorRoot.primary.id
                        editorRoot.change(() => LayoutService.ungroup(id))
                        editorRoot.selection = []
                    }
                }
                ShellButton {
                    Layout.fillWidth: true
                    icon: Icons.remove
                    text: "Remove"
                    variant: "danger"
                    onClicked: editorRoot.removeSelection()
                }
            }
        }
    }
}
