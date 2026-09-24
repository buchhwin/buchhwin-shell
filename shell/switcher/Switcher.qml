import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.theme
import qs.services
import qs.shell.components
import "../../services/switcher/SwitcherLogic.js" as Logic

// Alt+Tab: a centred strip of windows in most-recently-used order with live
// previews. Hyprland drives it through `switcher next/previous/confirm`; keys
// that reach the overlay itself (Tab, arrows, Enter, Escape, releasing Alt)
// do the same, and a click focuses a card.
PanelWindow {
    id: window
    readonly property bool wanted: PanelService.active === "switcher" && SwitcherService.active
    property bool shown: false
    readonly property real cardHeight: Metrics.spaceSm * 2 + Metrics.switcherPreviewHeight + Metrics.switcherIconSize / 2
        + Metrics.spaceSm + title.implicitHeight

    function toplevelFor(address) {
        const key = Logic.normalizeAddress(address)
        return Hyprland.toplevels.values.find(item => Logic.normalizeAddress(item.address) === key) || null
    }

    screen: PanelService.screen
    visible: shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "buchhwin-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Shown only after a short delay so a quick Alt+Tab does not flash.
    onWantedChanged: {
        if (wanted) {
            hideTimer.stop()
            showTimer.restart()
        } else {
            showTimer.stop()
            if (shown) hideTimer.restart()
        }
    }

    Timer {
        id: showTimer
        interval: Animations.switcherShowDelay
        onTriggered: if (window.wanted) { Hyprland.refreshToplevels(); window.shown = true }
    }
    Timer { id: hideTimer; interval: Animations.popupClose + 20; onTriggered: if (!window.wanted) window.shown = false }

    // Title metrics for the card height.
    ShellText { id: title; visible: false; text: "Ag" }

    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: window.wanted && window.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: window.wanted ? Animations.popupOpen : Animations.popupClose; easing.type: window.wanted ? Animations.easingEnter : Animations.easingExit } }
    }

    MouseArea { anchors.fill: parent; onClicked: SwitcherService.cancel() }

    Item {
        anchors.fill: parent
        focus: window.wanted
        Keys.onPressed: event => {
            const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) back ? SwitcherService.previous() : SwitcherService.next()
            else if (event.key === Qt.Key_Right) SwitcherService.next()
            else if (event.key === Qt.Key_Left) SwitcherService.previous()
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) SwitcherService.confirm()
            else if (event.key === Qt.Key_Escape) SwitcherService.cancel()
            else return
            event.accepted = true
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
                SwitcherService.confirm()
                event.accepted = true
            }
        }
    }

    // The same elevation a ShellPanel casts, by hand: an invisible twin of the
    // strip behind a MultiEffect, masked so the shadow only falls outside it.
    Rectangle {
        id: stripShadow
        visible: false
        x: strip.x
        y: strip.y
        width: strip.width
        height: strip.height
        radius: strip.radius
        color: Colors.shadow
        layer.enabled: true
    }
    MultiEffect {
        source: stripShadow
        anchors.fill: stripShadow
        opacity: strip.opacity
        shadowEnabled: true
        shadowColor: Colors.shadow
        blurMax: Effects.elevation2Max
        shadowBlur: Effects.elevation2Blur
        shadowOpacity: Effects.elevation2Opacity
        shadowVerticalOffset: Effects.elevation2Offset
        maskEnabled: true
        maskSource: stripShadow
        maskInverted: true
    }

    Rectangle {
        id: strip
        readonly property real contentWidth: Math.max(1, SwitcherService.windows.length) * (Metrics.switcherCardWidth + Metrics.spaceSm) - Metrics.spaceSm
        anchors.centerIn: parent
        width: Math.min(contentWidth, window.width - Metrics.screenMargin * 4) + Metrics.spaceMd * 2
        height: window.cardHeight + Metrics.spaceMd * 2
        // The cards sit spaceMd in, not panelPadding, so the corner is
        // derived from that inset and runs parallel to theirs.
        radius: Metrics.panelRadius(Metrics.spaceMd)
        color: Colors.panelFor("switcher")
        border.width: Metrics.borderWidth
        border.color: Colors.panelBorder
        opacity: window.wanted && window.shown ? 1 : 0
        scale: Animations.motionEnabled ? (window.wanted ? 1 : Effects.hoverScaleFrom) : 1
        Behavior on opacity { NumberAnimation { duration: window.wanted ? Animations.popupOpen : Animations.popupClose; easing.type: window.wanted ? Animations.easingEnter : Animations.easingExit } }
        Behavior on scale { NumberAnimation { duration: Animations.popupOpen; easing.type: Animations.easingEnter } }

        // Clicks on the strip background do not cancel.
        MouseArea { anchors.fill: parent }

        EmptyState {
            anchors.centerIn: parent
            visible: !SwitcherService.loading && SwitcherService.windows.length === 0
            icon: Icons.window
            title: "No open windows"
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: Metrics.spaceMd
            orientation: ListView.Horizontal
            spacing: Metrics.spaceSm
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: window.shown ? SwitcherService.windows : []
            currentIndex: SwitcherService.selected
            // An invisible highlight keeps the selected card scrolled into view.
            highlight: Item {}
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: Metrics.switcherCardWidth
            preferredHighlightEnd: width - Metrics.switcherCardWidth
            highlightMoveDuration: Animations.navigation

            delegate: ShellCard {
                id: card
                required property var modelData
                required property int index
                readonly property bool isSelected: index === SwitcherService.selected
                readonly property var toplevel: window.shown ? window.toplevelFor(modelData.address) : null
                readonly property var entry: DesktopEntries.heuristicLookup(modelData.appClass)
                // Largest box with the window's aspect ratio inside the preview area.
                readonly property real aspect: modelData.width > 0 && modelData.height > 0 ? modelData.width / modelData.height : 16 / 10
                readonly property real boxWidth: Metrics.switcherCardWidth - Metrics.spaceSm * 2
                width: Metrics.switcherCardWidth
                height: window.cardHeight
                interactive: true
                hovered: hover.hovered
                pressed: cardMouse.pressed && cardMouse.containsMouse
                highlighted: isSelected

                HoverHandler { id: hover }

                Rectangle {
                    id: frame
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Metrics.spaceSm + (Metrics.switcherPreviewHeight - height) / 2
                    width: Math.min(card.boxWidth, Metrics.switcherPreviewHeight * card.aspect)
                    height: Math.min(Metrics.switcherPreviewHeight, card.boxWidth / card.aspect)
                    radius: Metrics.radiusInner
                    color: Colors.elevatedSurface
                    border.width: Metrics.borderWidth
                    border.color: Colors.border
                    clip: true

                    ScreencopyView {
                        id: preview
                        anchors.fill: parent
                        anchors.margins: Metrics.borderWidth
                        captureSource: card.toplevel ? card.toplevel.wayland : null
                        constraintSize: Qt.size(width, height)
                        live: window.wanted
                    }
                }

                Image {
                    id: icon
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Metrics.spaceSm + Metrics.switcherPreviewHeight - Metrics.switcherIconSize / 2
                    width: Metrics.switcherIconSize
                    height: Metrics.switcherIconSize
                    source: LauncherService.iconSource([card.entry ? card.entry.icon : "", card.modelData.appClass])
                    sourceSize.width: Metrics.switcherIconSize * 2
                    sourceSize.height: Metrics.switcherIconSize * 2
                    fillMode: Image.PreserveAspectFit
                    // Theme icons (image://icon) must load on the GUI thread.
                    asynchronous: !String(source).startsWith("image://")
                }

                Rectangle {
                    anchors.top: frame.top
                    anchors.right: frame.right
                    anchors.margins: Metrics.spaceXs
                    visible: card.modelData.workspaceName.length > 0
                    width: Math.max(height, badge.implicitWidth + Metrics.spaceSm)
                    height: badge.implicitHeight + Metrics.spaceXxs * 2
                    radius: Metrics.radiusPill
                    color: Colors.pill
                    border.width: Metrics.borderWidth
                    border.color: Colors.panelBorder
                    ShellText {
                        id: badge
                        anchors.centerIn: parent
                        text: card.modelData.workspaceName
                        role: "caption"
                        color: Colors.text
                    }
                }

                ShellText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Metrics.spaceSm
                    horizontalAlignment: Text.AlignHCenter
                    text: card.modelData.title || (card.entry ? card.entry.name : "") || card.modelData.appClass || "Window"
                    color: card.isSelected ? Colors.text : Colors.mutedText
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SwitcherService.activate(card.index)
                }
            }
        }
    }
}
