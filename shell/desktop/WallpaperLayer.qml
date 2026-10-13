import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.theme
import qs.services

// Desktop background per screen with a short cross-fade between images.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData
        screen: modelData
        color: Colors.background
        exclusiveZone: -1
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "buchhwin-wallpaper"
        WlrLayershell.layer: WlrLayer.Background

        property bool showFirst: true
        // Decode at the screen's real pixel count. The old "logical size x 2"
        // was 33 % wider than the panel at scale 1.5 and twice as wide at
        // scale 1, so the cross-fade blended far more pixels than it showed.
        readonly property real pixelRatio: Math.max(1, modelData.devicePixelRatio)
        readonly property int textureWidth: Math.ceil(window.width * pixelRatio)
        readonly property int textureHeight: Math.ceil(window.height * pixelRatio)
        readonly property string targetPath: WallpaperService.currentFor(modelData.name)
        onTargetPathChanged: apply(targetPath)

        function apply(path) {
            const target = showFirst ? second : first
            if (target.source.toString() === "file://" + path) return
            target.source = path.length ? "file://" + path : ""
        }

        Component.onCompleted: first.source = targetPath.length ? "file://" + targetPath : ""

        // After a cross-fade the hidden image is let go: an Image keeps its
        // decoded texture as long as it has a source, which on a 4K screen is
        // 33 MB per image and per screen, held for a picture nobody sees.
        // `apply()` compares sources, so the next change loads it again,
        // asynchronously, and the fade still starts on Ready. Only once the
        // fade has ended and the opacity really is 0: a fade that is reversed
        // half-way (two changes in quick succession) restarts the Behavior
        // without reporting a stop, and the opacity check keeps a visible
        // image whole should it ever stop early.
        function release(image) {
            if (image.opacity === 0 && image.source.toString().length) image.source = ""
        }

        Image {
            id: first
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: window.textureWidth
            sourceSize.height: window.textureHeight
            asynchronous: true
            cache: false
            opacity: window.showFirst ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    id: firstFade
                    duration: Animations.enabled ? Animations.workspace * 3 : 0
                    easing.type: Animations.easing
                    onRunningChanged: if (!running) window.release(first)
                }
            }
            onStatusChanged: if (status === Image.Ready && !window.showFirst) window.showFirst = true
        }

        Image {
            id: second
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: window.textureWidth
            sourceSize.height: window.textureHeight
            asynchronous: true
            cache: false
            opacity: window.showFirst ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    id: secondFade
                    duration: Animations.enabled ? Animations.workspace * 3 : 0
                    easing.type: Animations.easing
                    onRunningChanged: if (!running) window.release(second)
                }
            }
            onStatusChanged: if (status === Image.Ready && window.showFirst) window.showFirst = false
        }
    }
}
