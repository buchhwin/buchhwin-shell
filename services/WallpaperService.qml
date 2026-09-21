pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import QtQml
import Qt.labs.folderlistmodel
import "wallpaper/WallpaperLogic.js" as Logic

// Wallpaper selection and slideshow. The folder is watched by
// FolderListModel, so no polling is needed. Per-monitor choices and
// favourites live in ~/.config/buchhwin-shell/wallpapers.json.
Singleton {
    id: root
    readonly property string folder: SettingsService.expandHome(SettingsService.value("wallpaper.folder"))
    readonly property string configuredPath: SettingsService.expandHome(SettingsService.value("wallpaper.path"))
    readonly property bool slideshow: SettingsService.value("wallpaper.slideshow")
    readonly property int intervalMinutes: Math.max(1, SettingsService.value("wallpaper.intervalMinutes"))
    readonly property string order: SettingsService.value("wallpaper.order")
    readonly property string slideshowSource: SettingsService.value("wallpaper.slideshowSource")
    // How many of the chosen images are still in the folder, and whether the
    // rotation had to fall back to everything because the choice is empty.
    readonly property int slideshowCount: Logic.slideshowCount(images, state)
    // Which subfolder the rotation stays inside, when it is set to one. A
    // plain string, because SettingsService cannot store a list.
    readonly property string slideshowFolder: SettingsService.value("wallpaper.slideshowFolder")
    readonly property bool poolIsFallback: Logic.poolIsFallback(images, state, slideshowSource, folder, slideshowFolder)
    readonly property var groups: Logic.groups(images, folder)
    property var state: Logic.emptyState()
    property bool stateLoaded: false
    property var images: []
    readonly property var pool: Logic.pool(images, state, slideshowSource, folder, slideshowFolder)
    readonly property var favourites: state.favourites
    property string slideshowPath: ""
    readonly property string current: slideshow && slideshowPath.length ? slideshowPath
        : configuredPath.length ? configuredPath
        : images.length ? images[0] : ""

    // screen: "" for all monitors (also clears per-monitor choices).
    function setWallpaper(path, screen) {
        if (screen && screen.length) {
            saveState(Logic.withScreen(state, screen, path))
            return
        }
        SettingsService.set("wallpaper.path", path)
        slideshowPath = ""
        if (Object.keys(state.screens).length) {
            let next = state
            for (const name of Object.keys(state.screens)) next = Logic.withScreen(next, name, "")
            saveState(next)
        }
    }

    function currentFor(screen) { return Logic.pathFor(state, screen, current, images) }
    function hasOwn(screen) { return state.screens[screen] !== undefined }
    function resetScreen(screen) { saveState(Logic.withScreen(state, screen, "")) }
    function isFavourite(path) { return state.favourites.indexOf(path) >= 0 }
    function toggleFavourite(path) { saveState(Logic.toggleFavourite(state, path)) }
    function isInSlideshow(path) { return state.slideshow.indexOf(path) >= 0 }

    function saveState(next) {
        state = next
        stateFile.setText(JSON.stringify(next, null, 2) + "\n")
    }

    // Copies chosen images into the wallpaper folder (KDE file dialog).
    function importImages() {
        if (!importProc.running) importProc.running = true
    }

    function next(step) {
        const list = pool
        if (!list.length) return
        const base = current.length ? list.indexOf(current) : -1
        let index
        if (order === "random" && list.length > 1) {
            do { index = Math.floor(Math.random() * list.length) } while (index === base)
        } else {
            index = (base + (step || 1) + list.length) % list.length
        }
        if (slideshow) slideshowPath = list[index]
        else setWallpaper(list[index], "")
    }

    FileView {
        id: stateFile
        path: Paths.configDir + "/wallpapers.json"
        atomicWrites: true
        watchChanges: true
        printErrors: false
        // An empty read during a file replacement keeps the current state.
        onLoaded: if (text().trim().length || !root.stateLoaded) { root.state = Logic.parseState(text()); root.stateLoaded = true }
        onFileChanged: reload()
    }

    Process {
        id: importProc
        stderr: ErrorLog { label: "WallpaperService.importProc" }
        command: ["sh", "-c", "mkdir -p \"$1\" && kdialog --title 'Add wallpapers' --multiple --separate-output --getopenfilename \"$HOME\" 'Images (*.png *.jpg *.jpeg *.webp)' | while IFS= read -r file; do [ -f \"$file\" ] && cp -n -- \"$file\" \"$1\"/; done", "sh", root.folder]
    }

    readonly property var imageFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]

    // The wallpaper folder itself, and the subfolders it holds.
    //
    // One level deep, and one FolderListModel per folder rather than a `find`.
    // FolderListModel is not recursive, but it *watches* - a wallpaper added
    // or removed shows up without anything polling - and that is worth more
    // than reaching arbitrarily deep into a pictures folder. A subfolder is
    // how the user groups their wallpapers (the picker's chips are these
    // folders); a folder inside a folder is not a second level of grouping,
    // it is somewhere the picker does not look.
    FolderListModel {
        id: folderModel
        folder: root.folder.length ? "file://" + root.folder : ""
        nameFilters: root.imageFilters
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: if (status === FolderListModel.Ready) root.refresh()
        onCountChanged: root.refresh()
    }

    // The subfolders, watched the same way, so a new one appears as a chip
    // without a restart.
    FolderListModel {
        id: subfolderModel
        folder: root.folder.length ? "file://" + root.folder : ""
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        onStatusChanged: if (status === FolderListModel.Ready) root.rebuildSubfolders()
        onCountChanged: root.rebuildSubfolders()
    }

    property var subfolders: []
    function rebuildSubfolders() {
        const found = []
        for (let i = 0; i < subfolderModel.count; ++i) found.push(subfolderModel.get(i, "filePath"))
        // Only when it actually changed: assigning the same list would restart
        // every Repeater below and with it every scan.
        if (found.length !== subfolders.length || found.some((path, i) => path !== subfolders[i]))
            subfolders = found
        root.refresh()
    }

    // One model per subfolder, so they come and go with the folders
    // themselves.
    //
    // `Instantiator` and not `Repeater`: a Repeater creates its delegates into
    // a visual parent and this is a Singleton, which has none - it silently
    // made nothing at all, and the picker showed only the images sitting
    // directly in the folder.
    property var subfolderImages: ({})
    Instantiator {
        model: root.subfolders
        delegate: Item {
            id: watcher
            required property string modelData
            FolderListModel {
                id: inner
                folder: "file://" + watcher.modelData
                nameFilters: root.imageFilters
                showDirs: false
                sortField: FolderListModel.Name
                onStatusChanged: if (status === FolderListModel.Ready) watcher.collect()
                onCountChanged: watcher.collect()
            }
            function collect() {
                const found = []
                for (let i = 0; i < inner.count; ++i) found.push(inner.get(i, "filePath"))
                const next = Object.assign({}, root.subfolderImages)
                next[watcher.modelData] = found
                root.subfolderImages = next
            }
            Component.onDestruction: {
                const next = Object.assign({}, root.subfolderImages)
                delete next[watcher.modelData]
                root.subfolderImages = next
            }
        }
    }
    onSubfolderImagesChanged: refresh()

    // `images` is the union of everything scanned, and it has to stay that
    // way: `pathFor` and `pool` both filter against it, so an image the picker
    // offers but this list does not know would be chosen and then silently
    // fall back to something else.
    function refresh() {
        const result = []
        for (let i = 0; i < folderModel.count; ++i)
            result.push(folderModel.get(i, "filePath"))
        for (const name of subfolders)
            for (const path of subfolderImages[name] || []) result.push(path)
        images = result
    }

    Timer {
        interval: root.intervalMinutes * 60000
        running: root.slideshow && root.pool.length > 1
        repeat: true
        onTriggered: root.next(1)
    }
}
