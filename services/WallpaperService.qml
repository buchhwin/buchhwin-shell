pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import QtQml
import Qt.labs.folderlistmodel
import qs.theme
import "wallpaper/WallpaperLogic.js" as Logic

// Wallpaper selection and slideshow. The folder is watched by
// FolderListModel, so no polling is needed. Per-monitor choices and
// favourites live in ~/.config/buchhwin-shell/wallpapers.json.
Singleton {
    id: root
    readonly property string configuredFolder: SettingsService.value("wallpaper.folder")
    // Until user-dirs.dirs has been read (or found missing) the default is not
    // known: guessing ~/Pictures first made a German session scan the wrong
    // folder and flash its first image before ~/Bilder arrived.
    readonly property string folder: configuredFolder.length ? SettingsService.expandHome(configuredFolder)
        : userDirsRead ? Logic.defaultFolder(picturesDir, Paths.home) : ""
    property bool userDirsRead: false
    readonly property bool folderIsDefault: !configuredFolder.length
    readonly property var recentFolders: Logic.recentFolders(SettingsService.value("wallpaper.recentFolders"))
        .filter(path => SettingsService.expandHome(path) !== folder)
    property string picturesDir: ""
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
        : configuredPath.length && !configuredMissing ? configuredPath
        : images.length ? images[0] : ""

    // The configured image when it is not there (a profile from another
    // machine, a file moved away): handed to the desktop as it was, it drew
    // nothing, and after a restart only the background colour showed. Then the
    // folder's first image is the wallpaper, or none.
    //
    // Taken to be there until it is shown not to be, so a start does not wait
    // for the answer before the first picture. An image the folder lists is
    // there; any other is asked once with `test -f` - when the path changes,
    // and when the folder's list does (an image added or moved away) - never
    // per frame.
    property string missingPath: ""
    readonly property bool configuredMissing: configuredPath.length > 0 && missingPath === configuredPath
    onConfiguredPathChanged: existsDelay.restart()
    // Debounced: at a start the path and the folder's list arrive a moment
    // apart, and the list alone often answers.
    Timer { id: existsDelay; interval: 1000; onTriggered: root.checkConfigured() }

    function checkConfigured() {
        if (!configuredPath.length || images.indexOf(configuredPath) >= 0) {
            missingPath = ""
            return
        }
        if (existsProc.running) { existsProc.again = true; return }
        existsProc.path = configuredPath
        existsProc.command = ["test", "-f", configuredPath]
        existsProc.running = true
    }

    Process {
        id: existsProc
        stderr: ErrorLog { label: "WallpaperService.existsProc" }
        property string path: ""
        property bool again: false
        // 1 is test's "no"; anything else (it could not run) keeps the path.
        onExited: code => {
            if (path === root.configuredPath) root.missingPath = code === 1 ? path : ""
            if (again) {
                again = false
                Qt.callLater(root.checkConfigured)
            }
        }
    }

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
    function toggleSlideshow(path) { saveState(Logic.toggleSlideshow(state, path)) }

    function saveState(next) {
        state = next
        stateFile.setText(JSON.stringify(next, null, 2) + "\n")
    }

    // Copies chosen images into the wallpaper folder (KDE file dialog).
    function importImages() {
        if (!importProc.running) importProc.running = true
    }

    // Another folder, from the KDE folder dialog or from the recent list.
    // The subfolder the slideshow was narrowed to belongs to the old folder,
    // so it is let go; the FolderListModels follow `folder` on their own.
    function chooseFolder() {
        if (!chooseProc.running) chooseProc.running = true
    }
    function setFolder(path) {
        const value = Logic.contractHome(String(path || "").trim(), Paths.home)
        if (!value.length || value === "~") return false
        const recent = Logic.addRecentFolder(SettingsService.value("wallpaper.recentFolders"),
                                             Logic.contractHome(folder, Paths.home))
        return SettingsService.setAll({ "wallpaper.folder": value, "wallpaper.slideshowFolder": "",
                                        "wallpaper.recentFolders": Logic.addRecentFolder(recent, value) })
    }
    function useDefaultFolder() {
        SettingsService.setAll({ "wallpaper.folder": "", "wallpaper.slideshowFolder": "" })
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

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Paths.home + "/.config") + "/user-dirs.dirs"
        printErrors: false
        watchChanges: true
        onLoaded: { root.picturesDir = Logic.picturesDir(text(), Paths.home); root.userDirsRead = true }
        onLoadFailed: root.userDirsRead = true
        onFileChanged: reload()
    }

    Process {
        id: chooseProc
        stderr: ErrorLog { label: "WallpaperService.chooseProc" }
        command: ["kdialog", "--title", "Wallpaper folder", "--getexistingdirectory", root.folder]
        stdout: StdioCollector {
            onStreamFinished: { const path = text.trim(); if (path.length) root.setFolder(path) }
        }
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
        folder: Logic.folderUrl(root.folder)
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
        folder: Logic.folderUrl(root.folder)
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
                folder: Logic.folderUrl(watcher.modelData)
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
        // Only when it changed, like the subfolders above: a folder is read
        // in steps and each one calls this, and a new list - the same paths
        // or not - recomputes the pool and the groups, rebuilds the picker's
        // grid and restarts the thumbnail run's wait.
        if (result.length !== images.length || result.some((path, i) => path !== images[i]))
            images = result
    }

    // ---- thumbnails ------------------------------------------------------------
    // The picker's and Settings' tiles load a small JPEG instead of the image.
    // Qt cannot decode a PNG at a reduced size: the user's 6000x3750 PNGs
    // (~4 MB) cost 140-340 ms per tile (measured with PIL), and the picker took
    // about a second until its last tile was there. Measured in Qt on 15.10.
    // (offscreen, sourceSize.width 260): 160-180 ms for such a PNG, 1-2 ms for
    // its 520x325 thumbnail (16-33 KB). scripts/wallpaper-thumbs.py
    // makes each thumbnail once, named by path, mtime, size and width; a run
    // over a folder it has seen only stats and hashes, so it runs whenever the
    // set of images changes and the first one starts shortly after the folder
    // is read - before anyone opens the picker.
    readonly property string thumbDir: Paths.cacheDir + "/wallpaper-thumbs"
    // Twice the picker's sourceWidth: Qt multiplies sourceSize by the integer
    // devicePixelRatio (2 on the 1.667 4K screens, pitfall 49), so this is the
    // width a tile decoded the original at. The Settings grid's tiles are
    // smaller than the picker's.
    readonly property int thumbWidth: Metrics.wallpaperPickerTile * 2
    // image -> thumbnail file, from the last run that finished.
    property var thumbs: ({})
    property bool thumbsQueued: false
    // The image list the last run was started with: the picker re-reads the
    // folder as it opens, and the same list again is not a reason to run.
    property string thumbsRunFor: ""

    // A file url, or "" while the image has none (the tile loads the image).
    function thumbFor(path) { return Logic.thumbUrl(thumbs, path) }

    // Debounced: a folder is read in steps (the folder, then each subfolder),
    // and copying ten images in is ten count changes. The configured image is
    // looked for again too (`checkConfigured`).
    onImagesChanged: { thumbDelay.restart(); existsDelay.restart() }
    Timer { id: thumbDelay; interval: 2000; onTriggered: root.makeThumbs() }

    // One run at a time; a change during a run is picked up after it.
    function makeThumbs() {
        if (thumbProc.running) { thumbsQueued = true; return }
        const key = JSON.stringify(images)
        if (key === thumbsRunFor) return
        thumbsRunFor = key
        if (!images.length) { thumbs = ({}); return }
        // Niced: the first run over a new folder decodes every image.
        thumbProc.command = ["nice", "-n", "10", "python3", Paths.script("wallpaper-thumbs.py"),
                             "--cache", thumbDir, "--width", String(thumbWidth), "--"].concat(images)
        thumbProc.running = true
    }

    Process {
        id: thumbProc
        stderr: ErrorLog { label: "WallpaperService.thumbProc" }
        // Read once the output and the exit are both in, in whichever order
        // they arrive. A run that failed keeps the thumbnails there are and
        // is tried again on the next change, even to the same list.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function finish() {
            if (!outputDone || exitCode < 0) return
            const found = exitCode === 0 ? Logic.parseThumbs(output) : null
            if (found) root.thumbs = found
            else root.thumbsRunFor = ""
            if (root.thumbsQueued) {
                root.thumbsQueued = false
                Qt.callLater(root.makeThumbs)
            }
        }
        stdout: StdioCollector { onStreamFinished: { thumbProc.output = text; thumbProc.outputDone = true; thumbProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }

    Timer {
        interval: root.intervalMinutes * 60000
        running: root.slideshow && root.pool.length > 1
        repeat: true
        onTriggered: root.next(1)
    }
}
