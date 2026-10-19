import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.theme
import qs.services
import "../../services/wallpaper/WallpaperLogic.js" as Logic

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
        // Decode for the screen's real pixel count. The old "logical size x 2"
        // was 33 % wider than the panel at scale 1.5 and twice as wide at
        // scale 1, so the cross-fade blended far more pixels than it showed.
        // And only the part the screen shows: with the screen's size alone
        // PreserveAspectCrop decodes the picture to *cover* it and keeps what
        // the crop cuts off - 2820x1200 for 1920x1200 with a 2.35:1 picture,
        // upscaled past the file on a portrait screen. Knowing the picture's
        // own size (WallpaperService.sizeOf), each image is decoded to
        // exactly the screen's part (WallpaperLogic.decodeGeometry); without
        // it, as before.
        //
        // The screen's `devicePixelRatio` is Wayland's whole-number output
        // scale (2 at 1.667), while the surface itself is drawn at the
        // fractional one. At 2 a 2304x1296 screen asked for 4608x2592 - 47 MB
        // instead of 33 per 4K screen, in memory and on the GPU, upscaled
        // from the file only to be scaled down again by the compositor.
        // The surface covers the whole screen, so its pixels are the mode's
        // (turned for a rotated screen). Quickshell's own Hyprland monitor
        // reports no scale under Hyprland 0.56, DisplayService has the mode.
        readonly property var liveMonitor: DisplayService.monitors.find(item => item.name === modelData.name) || null
        readonly property bool turned: liveMonitor !== null && liveMonitor.transform % 2 === 1
        readonly property real pixelRatio: Math.max(1, modelData.devicePixelRatio)
        readonly property int textureWidth: liveMonitor && liveMonitor.width > 0
            ? (turned ? liveMonitor.height : liveMonitor.width) : Math.ceil(window.width * pixelRatio)
        readonly property int textureHeight: liveMonitor && liveMonitor.height > 0
            ? (turned ? liveMonitor.width : liveMonitor.height) : Math.ceil(window.height * pixelRatio)
        readonly property string targetPath: WallpaperService.currentFor(modelData.name)
        onTargetPathChanged: if (sized) apply(targetPath)
        // The first picture waits for the mode and for the pictures' sizes
        // kept from the last run (at most 2 s): a size that arrives after the
        // load decodes the image again, a second decode at login.
        readonly property bool sized: (liveMonitor !== null && WallpaperService.sizesRead) || sizeWait.expired
        onSizedChanged: if (sized && !first.path.length && !second.path.length) load(first, targetPath)
        Timer {
            id: sizeWait
            property bool expired: false
            running: true
            interval: 2000
            onTriggered: expired = true
        }

        // Into the hidden image; the cross-fade starts once it is Ready.
        // `again` decodes a picture that is there already once more (refit).
        function apply(path, again) {
            const target = showFirst ? second : first
            if (!again && target.path === path) {
                // A change undone during the fade: the picture is still in
                // the image fading out, so it fades back in.
                if (path.length && target.status === Image.Ready) showFirst = target === first
                return
            }
            load(target, path)
        }

        // The source as an encoded url: a "#", "?" or "%41" in a file name
        // read as a fragment, a query or an escape, and the desktop showed
        // only its background colour for a picture the picker offered. The
        // source goes first, so a new size never decodes the old picture
        // once more; then the size and the clip for this screen.
        function load(image, path) {
            image.source = ""
            image.path = path
            image.geometry = path.length ? Logic.decodeGeometry(WallpaperService.sizeOf(path), textureWidth, textureHeight) : null
            image.source = Logic.folderUrl(path)
        }

        // The screen's pixels changed (a new mode, a rotation, the mode that
        // came after the 2 s wait), or the picture's size turned out to be
        // another than the one it was decoded for (Logic.needsRedecode):
        // decoded again into the hidden image and faded over. Reloaded where
        // it is, an Image shows nothing until the new decode is in.
        // Not while another picture is on its way in: that one is checked
        // when it is Ready, and decoding this one again into the same image
        // would throw the change away.
        function refit() {
            const shown = showFirst ? first : second
            if (!sized || !shown.path.length || shown.path !== targetPath || !shown.geometry || shown.status !== Image.Ready) return
            const wanted = Logic.decodeGeometry(WallpaperService.sizeOf(shown.path), textureWidth, textureHeight)
            if (Logic.needsRedecode(shown.geometry, wanted)) apply(shown.path, true)
        }
        // Once per turn for the width and the height of one change, and per
        // screen: a timer of each window's own.
        Timer { id: refitSoon; interval: 0; onTriggered: window.refit() }
        onTextureWidthChanged: refitSoon.restart()
        onTextureHeightChanged: refitSoon.restart()
        Connections {
            target: WallpaperService
            function onSizesChanged() { refitSoon.restart() }
        }

        Component.onCompleted: if (sized) load(first, targetPath)

        // After a cross-fade the hidden image is let go: an Image keeps its
        // decoded texture as long as it has a source, which on a 4K screen is
        // 33 MB per image and per screen, held for a picture nobody sees.
        // `apply()` compares paths, so the next change loads it again,
        // asynchronously, and the fade still starts on Ready. Only once the
        // fade has ended and the opacity really is 0: a fade that is reversed
        // half-way (two changes in quick succession) restarts the Behavior
        // without reporting a stop, and the opacity check keeps a visible
        // image whole should it ever stop early.
        function release(image) {
            if (image.opacity === 0 && image.path.length) {
                image.source = ""
                image.path = ""
                image.geometry = null
            }
        }

        Image {
            id: first
            // The picture it holds and how it was decoded (`load`).
            property string path: ""
            property var geometry: null
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: geometry ? geometry.width : window.textureWidth
            sourceSize.height: geometry ? geometry.height : window.textureHeight
            sourceClipRect: geometry && geometry.clip
                ? Qt.rect(geometry.clip.x, geometry.clip.y, geometry.clip.width, geometry.clip.height) : Qt.rect(0, 0, 0, 0)
            asynchronous: true
            // Shared: two screens of the same size showing the same picture
            // decode it once. A released image leaves Qt's cache soon after.
            cache: true
            opacity: window.showFirst ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    id: firstFade
                    duration: Animations.enabled ? Animations.workspace * 3 : 0
                    easing.type: Animations.easing
                    onRunningChanged: if (!running) window.release(first)
                }
            }
            onStatusChanged: if (status === Image.Ready) { if (!window.showFirst) window.showFirst = true; refitSoon.restart() }
        }

        Image {
            id: second
            property string path: ""
            property var geometry: null
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: geometry ? geometry.width : window.textureWidth
            sourceSize.height: geometry ? geometry.height : window.textureHeight
            sourceClipRect: geometry && geometry.clip
                ? Qt.rect(geometry.clip.x, geometry.clip.y, geometry.clip.width, geometry.clip.height) : Qt.rect(0, 0, 0, 0)
            asynchronous: true
            cache: true
            opacity: window.showFirst ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    id: secondFade
                    duration: Animations.enabled ? Animations.workspace * 3 : 0
                    easing.type: Animations.easing
                    onRunningChanged: if (!running) window.release(second)
                }
            }
            onStatusChanged: if (status === Image.Ready) { if (window.showFirst) window.showFirst = false; refitSoon.restart() }
        }
    }
}
