import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.theme
import qs.services
// Registers the widget module so widgets can share WidgetBase.
import qs.shell.widgets

// Visual container for one widget or a group: style (minimal, capsule, card),
// hover feedback and click actions. Also used by the layout editor.
Item {
    id: root
    required property var item            // widget or group data
    property bool editing: false
    // Screen position of this frame's window, so clicks can open panels next to it.
    property point screenOrigin: Qt.point(0, 0)
    property bool interactive: !editing
    readonly property bool isGroup: item !== null && item.members !== undefined
    readonly property var entries: isGroup ? LayoutService.members(item.id) : (item ? [item] : [])
    readonly property string styleName: item ? item.style : "minimal"
    readonly property real scaleFactor: item ? item.scale : 1
    readonly property bool hovered: hover.hovered
    // False when every widget currently has nothing to show (no player, no
    // window). Counted from hasData instead of the measured width: a hidden
    // surface reports no width, so a widget whose data arrives later would
    // never become visible again.
    property int showingCount: 0
    readonly property bool hasContent: showingCount > 0
    function recount() {
        let count = 0
        for (let i = 0; i < entryRepeater.count; ++i) {
            const loader = entryRepeater.itemAt(i)
            if (loader && loader.showing) count += 1
        }
        showingCount = count
    }
    property bool pressed: false

    readonly property int padX: styleName === "minimal" ? Metrics.spaceSm * scaleFactor
        : styleName === "capsule" ? Metrics.spaceLg * scaleFactor : Metrics.spaceLg * scaleFactor
    readonly property int padY: styleName === "minimal" ? Metrics.spaceXs * scaleFactor
        : styleName === "capsule" ? Metrics.spaceSm * scaleFactor : Metrics.spaceMd * scaleFactor

    implicitWidth: content.implicitWidth + padX * 2
    implicitHeight: content.implicitHeight + padY * 2

    HoverHandler { id: hover; enabled: root.interactive }

    Item {
        id: body
        visible: root.hasContent
        width: root.implicitWidth
        height: root.implicitHeight
        y: Animations.motionEnabled && root.hovered ? -Effects.hoverTranslate : 0
        scale: Animations.motionEnabled && root.pressed ? Effects.pressScaleWide : 1
        Behavior on y { NumberAnimation { duration: Animations.move(Animations.hover); easing.type: Animations.easing } }
        Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }

        Rectangle {
            anchors.fill: parent
            radius: root.styleName === "capsule" ? height / 2 : Metrics.radiusLg
            color: root.styleName === "minimal" ? Colors.surface : Colors.panelFor("widgets")
            border.width: root.styleName === "card" || (root.styleName === "minimal" && root.hovered) ? Metrics.borderWidth : 0
            border.color: Colors.panelBorder
            opacity: root.styleName === "minimal" ? (root.hovered ? 1 : 0) : 1
            Behavior on opacity { NumberAnimation { duration: Animations.hover } }
        }

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: Metrics.spaceMd * root.scaleFactor
            // Minimal widgets sit directly on the wallpaper; a soft shadow keeps them readable.
            layer.enabled: root.styleName === "minimal" && root.hasContent
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Colors.textHalo
                shadowBlur: 0.5
                shadowVerticalOffset: Effects.shadowOffsetSm
            }

            Repeater {
                id: entryRepeater
                model: root.entries
                onItemAdded: root.recount()
                onItemRemoved: Qt.callLater(root.recount)
                delegate: Loader {
                    id: loader
                    required property var modelData
                    readonly property bool showing: item !== null && item.hasData !== false
                    source: WidgetRegistry.source(modelData.type)
                    visible: showing
                    onShowingChanged: root.recount()
                    Layout.alignment: Qt.AlignVCenter
                    onLoaded: {
                        item.instance = Qt.binding(() => loader.modelData)
                        item.scaleFactor = Qt.binding(() => root.scaleFactor)
                        item.sizeClass = Qt.binding(() => root.isGroup ? "small" : loader.modelData.size)
                        item.hovered = Qt.binding(() => root.hovered)
                        item.alignment = Qt.binding(() => root.item ? root.item.anchorX : "right")
                        item.inGroup = Qt.binding(() => root.isGroup)
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        onPressedChanged: root.pressed = pressed
                        cursorShape: WidgetRegistry.type(loader.modelData.type)
                            && WidgetRegistry.type(loader.modelData.type).action.length ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const entry = WidgetRegistry.type(loader.modelData.type)
                            if (!entry || !entry.action.length) return
                            // Open below the widget, or above it in the lower half of the screen.
                            const topLeft = root.mapToItem(null, 0, 0)
                            const left = root.screenOrigin.x + topLeft.x
                            const top = root.screenOrigin.y + topLeft.y
                            const screenHeight = root.QsWindow.window && root.QsWindow.window.screen ? root.QsWindow.window.screen.height : 0
                            const lower = screenHeight > 0 && top + root.height / 2 > screenHeight / 2
                            // The rect the widget occupies, so the panel grows
                            // out of it rather than appearing beside it.
                            const origin = { originX: left, originY: top, originWidth: root.width, originHeight: root.height }
                            // `actionArgs` is how a widget says *where* in the
                            // panel it means - Settings opens on a page, not
                            // at the top of a list of twenty.
                            PanelService.toggle(entry.action, Object.assign(origin, lower
                                ? { anchorX: left + root.width / 2, anchorBottom: top - Metrics.spaceSm }
                                : { anchorX: left + root.width / 2, anchorTop: top + root.height + Metrics.spaceSm },
                                entry.actionArgs || {}))
                        }
                    }
                }
            }
        }
    }
}
