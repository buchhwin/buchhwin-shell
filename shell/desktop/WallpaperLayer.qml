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

        Image {
            id: first
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: window.textureWidth
            sourceSize.height: window.textureHeight
            asynchronous: true
            cache: false
            opacity: window.showFirst ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Animations.enabled ? Animations.workspace * 3 : 0; easing.type: Animations.easing } }
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
            Behavior on opacity { NumberAnimation { duration: Animations.enabled ? Animations.workspace * 3 : 0; easing.type: Animations.easing } }
            onStatusChanged: if (status === Image.Ready && window.showFirst) window.showFirst = false
        }
    }
}
