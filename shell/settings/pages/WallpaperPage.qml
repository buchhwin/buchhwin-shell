import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../../services/wallpaper/WallpaperLogic.js" as Logic

ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    // "" = all monitors, otherwise a screen name.
    property string target: ""
    readonly property string targetPath: target.length ? WallpaperService.currentFor(target) : WallpaperService.current
    // Every image, always: this is the grid the choices are made in, so it
      // must show what is not chosen too.
    readonly property var shownImages: WallpaperService.images

    GridLayout {
        Layout.fillWidth: true
        columns: width >= Metrics.wideWidth - Metrics.settingsSidebarWidth ? 2 : 1
        columnSpacing: Metrics.spaceLg
        rowSpacing: Metrics.spaceLg

        SettingsSection {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: "Current wallpaper"

            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                visible: Quickshell.screens.length > 1
                current: root.target
                options: [{ value: "", label: "All displays" }].concat(Quickshell.screens.map(screen => ({ value: screen.name, label: screen.name })))
                onSelected: value => root.target = value
            }

            // Masked, not clipped: `clip` cuts the bounding box and leaves the
            // radius alone, so the picture had square corners inside a rounded
            // frame. `RoundedImage` is in the repo for exactly this.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: width * 9 / 16
                radius: Metrics.radiusCard
                color: Colors.elevatedSurface
                RoundedImage {
                    anchors.fill: parent
                    radius: parent.radius
                    source: root.targetPath.length ? "file://" + root.targetPath : ""
                    sourceWidth: 640
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: caption.implicitHeight + Metrics.spaceMd * 2
                    color: Colors.scrimStrong
                    ShellText {
                        id: caption
                        anchors.fill: parent
                        anchors.margins: Metrics.spaceMd
                        text: root.targetPath.split("/").pop().replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ")
                            + (root.target.length && !WallpaperService.hasOwn(root.target) ? " · same as all displays" : "")
                        color: Colors.scrimText
                    }
                }
            }
            // A Flow, not a RowLayout: with a wide interface font the four
            // buttons are wider than the card, and a row would push the last
            // ones out of it instead of wrapping.
            Flow {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellButton { focusOnTab: true; icon: Icons.previous; text: "Previous"; compact: true; onClicked: WallpaperService.next(-1) }
                ShellButton { focusOnTab: true; icon: Icons.next; text: "Next"; compact: true; onClicked: WallpaperService.next(1) }
                ShellButton {
                    focusOnTab: true
                    visible: root.target.length > 0 && WallpaperService.hasOwn(root.target)
                    icon: Icons.reset; text: "Same as all"; compact: true
                    onClicked: WallpaperService.resetScreen(root.target)
                }
                ShellButton {
                    focusOnTab: true
                    icon: Icons.folder; text: "Open folder"; compact: true
                    onClicked: { Quickshell.execDetached(["xdg-open", WallpaperService.folder]); PanelService.close() }
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: "Slideshow"
            description: "Change the wallpaper automatically"

            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                label: "Slideshow"
                ShellToggle { focusOnTab: true; checked: WallpaperService.slideshow; onToggled: value => SettingsService.set("wallpaper.slideshow", value) }
            }
            SettingRow {
                label: "Interval"
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: String(WallpaperService.intervalMinutes)
                    options: [{ value: "5", label: "5 min" }, { value: "15", label: "15 min" }, { value: "30", label: "30 min" }, { value: "60", label: "60 min" }]
                    onSelected: value => SettingsService.set("wallpaper.intervalMinutes", parseInt(value))
                }
            }
            SettingRow {
                label: "Order"
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: WallpaperService.order
                    options: [{ value: "sequential", label: "In order" }, { value: "random", label: "Random" }]
                    onSelected: value => SettingsService.set("wallpaper.order", value)
                }
            }
            SettingRow {
                label: "Uses"
                SegmentedControl {
                    focusOnTab: true
                    Layout.fillWidth: true
                    current: WallpaperService.slideshowSource
                    options: [{ value: "all", label: "All images" },
                              { value: "favourites", label: "Favorites" },
                              { value: "chosen", label: "Chosen" }]
                        // Only offered where there is a folder to stay inside.
                        .concat(WallpaperService.groups.length ? [{ value: "folder", label: "One folder" }] : [])
                    onSelected: value => SettingsService.set("wallpaper.slideshowSource", value)
                }
            }
            SettingRow {
                visible: WallpaperService.slideshowSource === "folder"
                label: "Folder"
                hint: "The subfolders of the wallpaper folder. Make a folder, put wallpapers in it, and the rotation can stay inside it."
                ShellSelect {
                    focusOnTab: true
                    Layout.fillWidth: true
                    options: WallpaperService.groups.map(name => ({ value: name, label: name }))
                    current: WallpaperService.slideshowFolder
                    placeholder: "Pick a folder"
                    onSelected: value => SettingsService.set("wallpaper.slideshowFolder", value)
                }
            }
            ShellText {
                Layout.fillWidth: true
                visible: WallpaperService.slideshowSource === "folder"
                text: WallpaperService.poolIsFallback
                    ? "That folder has no images, so the slideshow uses every one."
                    : WallpaperService.pool.length + " images in " + (WallpaperService.slideshowFolder.length
                        ? WallpaperService.slideshowFolder : "the wallpaper folder itself")
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            // The fallback has always been there; it used to be silent, which
            // is why a rotation narrowed to nothing looked broken rather than
            // empty.
            ShellText {
                Layout.fillWidth: true
                visible: WallpaperService.slideshowSource === "chosen"
                text: WallpaperService.poolIsFallback
                    ? "Nothing chosen yet, so the slideshow uses every image. Tick images below."
                    : WallpaperService.slideshowCount + " of " + WallpaperService.images.length + " images in the slideshow"
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            ShellText {
                Layout.fillWidth: true
                visible: WallpaperService.slideshowSource === "favourites" && WallpaperService.poolIsFallback
                text: "No favorites yet, so the slideshow uses every image."
                role: "small"; muted: true; wrapMode: Text.Wrap
            }
            ShellText {
                Layout.fillWidth: true
                text: "Folder: " + WallpaperService.folder + " · " + WallpaperService.images.length + " images"
                // Wrap between words and elide in the middle of the path, so a
                // long folder name never breaks mid-word.
                role: "small"; muted: true; wrapMode: Text.Wrap
                elide: Text.ElideMiddle; maximumLineCount: 2
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Images"
        description: "All images in the folder · Star marks favorites · Ctrl+F stars the selected one"
            + (WallpaperService.slideshowSource === "chosen" ? " · Tick picks for the slideshow" : "")
            + (root.target.length ? " · Selection applies to " + root.target : "")

        RowLayout {
            ShellButton { focusOnTab: true; icon: Icons.add; text: "Add images …"; compact: true; onClicked: WallpaperService.importImages() }
        }

        // The picker has had a keyboard since it was built - arrows to move,
        // Enter to set, Ctrl+F to star - and this grid, which shows the same
        // images, had none: the star here could only be reached by resting a
        // pointer on a tile. Same gesture, same keys, so it stays one thing
        // to learn.
        //
        // The whole grid is **one** tab stop and the arrows move inside it,
        // which is this project's rule for a group of like controls. A stop
        // per tile would be as many stops as there are wallpapers on the way
        // to the next section. The handlers sit here and not on the page,
        // because the settings search field owns Up and Down for walking the
        // page list.
        GridLayout {
            id: grid
            Layout.fillWidth: true
            columns: Math.max(2, Math.floor(width / Metrics.wallpaperGridCell))
            columnSpacing: Metrics.spaceSm
            rowSpacing: Metrics.spaceSm

            activeFocusOnTab: root.shownImages.length > 0
            property int current: 0
            readonly property string currentPath: current >= 0 && current < root.shownImages.length
                ? root.shownImages[current] : ""

            function step(delta) {
                grid.current = Logic.moveIndex(grid.current, delta, root.shownImages.length, grid.columns)
            }

            // Arriving from Tab lands on the image the chosen display already
            // shows, not on the first of several hundred.
            onActiveFocusChanged: if (activeFocus) {
                const at = root.shownImages.indexOf(root.targetPath)
                if (at >= 0) grid.current = at
            }

            Keys.onLeftPressed: grid.step(-1)
            Keys.onRightPressed: grid.step(1)
            Keys.onUpPressed: grid.step(-grid.columns)
            Keys.onDownPressed: grid.step(grid.columns)
            Keys.onReturnPressed: if (grid.currentPath) WallpaperService.setWallpaper(grid.currentPath, root.target)
            Keys.onSpacePressed: if (grid.currentPath) WallpaperService.setWallpaper(grid.currentPath, root.target)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                    if (grid.currentPath) WallpaperService.toggleFavourite(grid.currentPath)
                    event.accepted = true
                }
            }

            Repeater {
                model: root.shownImages
                Rectangle {
                    id: thumb
                    required property string modelData
                    required property int index
                    readonly property bool active: modelData === root.targetPath
                    readonly property bool focused: grid.activeFocus && grid.current === index
                    Layout.fillWidth: true
                    implicitHeight: (grid.width / grid.columns) * 10 / 16
                    radius: Metrics.radiusInner
                    color: Colors.elevatedSurface
                    RoundedImage {
                        anchors.fill: parent
                        anchors.margins: thumb.active ? Metrics.focusBorderWidth + 1 : 0
                        // Concentric with the frame: a picture inset by the
                        // ring needs a radius smaller by the same amount, or
                        // the two curves cross.
                        radius: thumb.radius - anchors.margins
                        source: "file://" + thumb.modelData
                        sourceWidth: 320
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: thumb.active ? Metrics.focusBorderWidth + 1
                            : thumbMouse.containsMouse ? Metrics.borderWidth : 0
                        border.color: thumb.active ? Colors.accent : Colors.borderStrong
                    }
                    Rectangle {
                        visible: thumb.active
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Metrics.spaceSm
                        width: Metrics.iconMd + Metrics.spaceXs
                        height: width
                        radius: width / 2
                        color: Colors.accent
                        ShellIcon { anchors.centerIn: parent; glyph: Icons.check; size: Metrics.iconXs; color: Colors.accentText }
                    }
                    // The same ring the Displays page puts on a monitor tile:
                    // a grey border is not a focus indicator, and the keyboard
                    // needs to be as visible here as it is everywhere else.
                    FocusRing { active: thumb.focused; controlRadius: thumb.radius }

                    MouseArea {
                        id: thumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WallpaperService.setWallpaper(thumb.modelData, root.target)
                    }
                    Rectangle {
                        readonly property bool favourite: WallpaperService.isFavourite(thumb.modelData)
                        // Shown for the keyboard too, or Ctrl+F would be a key
                        // with nothing on screen to say what it did.
                        visible: favourite || thumb.focused || thumbMouse.containsMouse || starMouse.containsMouse
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: Metrics.spaceSm
                        width: Metrics.iconMd + Metrics.spaceXs
                        height: width
                        radius: width / 2
                        color: Colors.pill
                        ShellIcon { anchors.centerIn: parent; glyph: parent.favourite ? "󰓎" : "󰓒"; size: Metrics.iconXs; color: parent.favourite ? Colors.warning : Colors.text }
                        MouseArea {
                            id: starMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperService.toggleFavourite(thumb.modelData)
                        }
                    }
                    // The slideshow tick, only while the slideshow is taking a
                    // chosen list: a control for a question nobody is asking
                    // is a control in the way.
                    Rectangle {
                        readonly property bool picked: WallpaperService.isInSlideshow(thumb.modelData)
                        visible: WallpaperService.slideshowSource === "chosen"
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: Metrics.spaceSm
                        width: Metrics.iconMd + Metrics.spaceXs
                        height: width
                        radius: Metrics.radiusInner
                        color: picked ? Colors.accent : Colors.pill
                        ShellIcon {
                            anchors.centerIn: parent
                            glyph: Icons.check
                            size: Metrics.iconXs
                            color: parent.picked ? Colors.accentText : Colors.mutedText
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperService.toggleSlideshow(thumb.modelData)
                        }
                    }
                }
            }
        }
    }
}
