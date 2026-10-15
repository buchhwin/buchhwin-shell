import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.theme
import qs.services
import qs.shell.components
import "../../services/color/ColorLogic.js" as Logic

// Picking a colour off the screen: one surface per monitor showing that
// monitor's frozen frame, a loupe that follows the pointer, and the colour
// under it in a badge beside the loupe.
//
// The frozen frame is shown rather than left transparent, so what is sampled
// and what is seen cannot drift apart - a live screen under a sampled capture
// disagrees the moment anything on it animates, and then the swatch lies.
Variants {
    model: ColorPickerService.active ? Quickshell.screens : []

    PanelWindow {
        id: window
        required property var modelData

        // This monitor's frame, by name. Until the helper has answered there
        // is nothing to show and nothing to sample.
        readonly property var frame: {
            for (const item of ColorPickerService.frames)
                if (item.name === modelData.name) return item
            return null
        }

        screen: modelData
        visible: ColorPickerService.active
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "buchhwin-colorPicker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // **`Keys` only attaches to an `Item`, and a `PanelWindow` is not
        // one.** It used to sit on the window, where QML refused it and said
        // so on every single open - `Could not attach Keys property to ... is
        // not an Item` - so Escape and Enter never arrived and the only way
        // out of the picker was to pick something. A focused item inside the
        // window is where they belong; the surface already takes the keyboard
        // exclusively, so nothing competes for them.
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: ColorPickerService.close()
            Keys.onReturnPressed: ColorPickerService.pick()
            Keys.onEnterPressed: ColorPickerService.pick()
        }

        Image {
            id: frozen
            anchors.fill: parent
            visible: window.frame !== null
            source: window.frame ? "file://" + window.frame.file : ""
            fillMode: Image.PreserveAspectCrop
            // The frame is this screen's own pixels; decoding it at anything
            // else would show a colour the helper never sampled.
            sourceSize.width: Math.ceil(window.width * Math.max(1, window.modelData.devicePixelRatio))
            sourceSize.height: Math.ceil(window.height * Math.max(1, window.modelData.devicePixelRatio))
            asynchronous: false
            cache: false
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPositionChanged: mouse => window.sampleAt(mouse.x, mouse.y)
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) ColorPickerService.close()
                else {
                    window.sampleAt(mouse.x, mouse.y)
                    ColorPickerService.pick()
                }
            }
        }

        // The pointer is in this surface's own coordinates; the helper answers
        // global ones, so the frame's own place on the desktop is added.
        function sampleAt(x, y) {
            if (!frame) return
            ColorPickerService.sample(frame.x + x, frame.y + y)
        }
        Component.onCompleted: if (frame) ColorPickerService.sample(frame.x + width / 2, frame.y + height / 2)

        // Loupe and badge sit above the pointer, and below it when there is no
        // room above: near the top edge both used to leave the screen.
        readonly property bool loupeAbove: pointer.mouseY - Metrics.spaceLg - loupe.height
            - Metrics.spaceSm - hexBadge.height >= Metrics.screenMargin

        // ---- the loupe -------------------------------------------------
        // The frozen frame again, scaled up and cut to a circle, shifted so
        // the sampled pixel sits under the crosshair in its middle.
        Item {
            id: loupe
            visible: window.frame !== null && pointer.containsMouse
            width: Metrics.colorLoupeSize
            height: width
            x: pointer.mouseX - width / 2
            y: window.loupeAbove ? pointer.mouseY - height - Metrics.spaceLg : pointer.mouseY + Metrics.spaceLg

            // A Rectangle's `clip` cuts its square, never its radius (pitfall
            // 4), so the zoomed pixels showed as a square inside the ring.
            // `clip` here only trims the zoomed frame to the loupe, and the
            // mask below rounds it, the way RoundedImage does. The layer is
            // the loupe's size: a mask on the Image itself would need a
            // texture `zoom` times the screen.
            Item {
                id: zoomed
                anchors.fill: parent
                clip: true
                visible: false
                layer.enabled: true

                // Behind the frame where the loupe reaches past a screen edge.
                Rectangle { anchors.fill: parent; color: Colors.surface1 }

                Image {
                    readonly property real zoom: Metrics.colorLoupeZoom
                    width: frozen.width * zoom
                    height: frozen.height * zoom
                    x: -pointer.mouseX * zoom + loupe.width / 2
                    y: -pointer.mouseY * zoom + loupe.height / 2
                    source: frozen.source
                    // Nearest neighbour: a loupe is for seeing which pixel you
                    // are on, and a smoothed one invents colours between them.
                    // The layer keeps it that way (layer.smooth is off).
                    smooth: false
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: frozen.sourceSize.width
                    sourceSize.height: frozen.sourceSize.height
                    asynchronous: false
                    cache: false
                }
            }

            Rectangle {
                id: loupeMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
                layer.smooth: true
            }

            MultiEffect {
                anchors.fill: parent
                source: zoomed
                maskEnabled: true
                maskSource: loupeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // The ring, over the masked frame.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Metrics.focusBorderWidth
                border.color: Colors.border
            }

            // The pixel under the crosshair, outlined so it is findable
            // whatever colour it is.
            Rectangle {
                anchors.centerIn: parent
                width: Metrics.colorLoupeZoom
                height: width
                color: "transparent"
                border.width: Metrics.borderWidth
                // `Colors.overviewText` never existed - the token is
                // `scrimText` - so this was `undefined` and the log said
                // "Unable to assign [undefined] to QColor" on every open.
                // A loupe ring over a frozen screenshot is text on a
                // scrim as far as contrast goes.
                border.color: Colors.scrimText
            }
        }

        // The colour under the pointer, its hex, and what to do next. On an
        // opaque surface: it floats over a frozen screenshot, and the 7 %
        // card tint it had let whatever was below show through the words.
        Rectangle {
            id: hexBadge
            visible: loupe.visible && ColorPickerService.hovered.length > 0
            x: Math.max(Metrics.screenMargin,
                Math.min(window.width - width - Metrics.screenMargin, pointer.mouseX - width / 2))
            y: window.loupeAbove ? loupe.y - height - Metrics.spaceSm : loupe.y + loupe.height + Metrics.spaceSm
            implicitWidth: badge.implicitWidth + Metrics.spaceMd * 2
            implicitHeight: badge.implicitHeight + Metrics.spaceSm * 2
            radius: Metrics.radiusInner
            color: Colors.solidSurface
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            Row {
                id: badge
                anchors.centerIn: parent
                spacing: Metrics.spaceSm
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.iconMd
                    height: width
                    radius: Metrics.radiusInner
                    color: ColorPickerService.hovered.length ? ColorPickerService.hovered : Colors.surface2
                    border.width: Metrics.borderWidth
                    border.color: Colors.border
                }
                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ColorPickerService.hovered.toUpperCase()
                    font.features: { "tnum": 1 }
                }
                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Click or Enter copies · Esc cancels"
                    role: "small"
                    muted: true
                }
            }
        }
    }
}
