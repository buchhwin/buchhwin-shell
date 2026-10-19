pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import QtQml
import Qt.labs.folderlistmodel
import qs.theme
import "wallpaper/WallpaperLogic.js" as Logic

// Wallpaper selection and slideshow. The folder is watched by
// FolderListModel, so no polling is needed. Per-monitor choices, favourites,
// the slideshow's own list and the picker's last chip live in
// ~/.config/buchhwin-shell/wallpapers.json.
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
    // A wallpaper for each theme (WallpaperLogic.themePath): the light or the
    // dark one where it is set, the shared one otherwise. The theme is
    // Colors.dark, so "Automatic" (by the hours or by the sun) swaps the
    // picture as it swaps the panels.
    readonly property bool themePair: SettingsService.value("wallpaper.themePair") === true
    readonly property string lightPath: SettingsService.expandHome(String(SettingsService.value("wallpaper.lightPath") || ""))
    readonly property string darkPath: SettingsService.expandHome(String(SettingsService.value("wallpaper.darkPath") || ""))
    readonly property string configuredPath: Logic.themePath(themePair, Colors.dark, lightPath, darkPath,
                                                             SettingsService.expandHome(SettingsService.value("wallpaper.path")))
    // "light", "dark" or "shared": which of the three is on the desktop.
    readonly property string themeSide: Logic.themeSide(themePair, Colors.dark, lightPath, darkPath)
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
    // The picker's last chip ("" everything, Logic.FAVOURITES or a subfolder's
    // name), kept here with the favourites so it is the same in every profile
    // (WallpaperLogic, "the picker's last chip").
    readonly property string pickerFilter: state.pickerFilter || ""
    property string slideshowPath: ""
    readonly property string current: Logic.currentPath(slideshow ? slideshowPath : "", configuredPath, images,
                                                        checkedPath, missingPath)

    // The configured image when it is not there (a profile from another
    // machine, a file moved away): handed to the desktop as it was, it drew
    // nothing, and after a restart only the background colour showed. Then the
    // folder's first image is the wallpaper, or none.
    //
    // An image the folder lists is there; any other is asked once with
    // `test -f` - when the path changes, and when the folder's list does (an
    // image added or moved away) - never per frame. Until it answers the
    // desktop shows nothing rather than a path that may not exist
    // (Logic.currentPath): a new path is asked about at once, so a start or a
    // profile switch waits milliseconds.
    property string missingPath: ""
    property string checkedPath: ""
    readonly property bool configuredMissing: configuredPath.length > 0 && missingPath === configuredPath
    onConfiguredPathChanged: checkConfigured()
    // The folder's list is debounced: it changes in bursts while files move,
    // and the path is already known meanwhile.
    Timer { id: existsDelay; interval: 1000; onTriggered: root.checkConfigured() }

    function checkConfigured() {
        if (!configuredPath.length || images.indexOf(configuredPath) >= 0) {
            missingPath = ""
            checkedPath = configuredPath
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
            if (path === root.configuredPath) {
                root.missingPath = code === 1 ? path : ""
                root.checkedPath = path
            }
            if (again) {
                again = false
                Qt.callLater(root.checkConfigured)
            }
        }
    }

    // screen: "" for all monitors (also clears per-monitor choices). With a
    // wallpaper for each theme it is the one of the theme in use.
    function setWallpaper(path, screen) {
        if (screen && screen.length) {
            saveState(Logic.withScreen(state, screen, path))
            return
        }
        SettingsService.set(Logic.pickKey(themePair, Colors.dark), path)
        slideshowPath = ""
        if (Object.keys(state.screens).length) {
            let next = state
            for (const name of Object.keys(state.screens)) next = Logic.withScreen(next, name, "")
            saveState(next)
        }
    }

    // Nothing for a moment at a start (Logic.pathFor): until wallpapers.json
    // has been read it is not known whether a screen has a wallpaper of its
    // own, and until the folder has, whether that one is there.
    function currentFor(screen) { return Logic.pathFor(state, screen, current, images, imagesReady, stateLoaded) }
    // One side of the pair, from Settings > Wallpaper: `dark` true for the
    // dark theme's. An empty path lets that side show the shared wallpaper.
    function themeWallpaper(dark) { return dark ? darkPath : lightPath }
    function setThemeWallpaper(dark, path) {
        return SettingsService.set(Logic.pickKey(true, dark), String(path || ""))
    }
    function hasOwn(screen) { return state.screens[screen] !== undefined }
    function resetScreen(screen) { saveState(Logic.withScreen(state, screen, "")) }
    function isFavourite(path) { return state.favourites.indexOf(path) >= 0 }
    function toggleFavourite(path) { saveState(Logic.toggleFavourite(state, path)) }
    function isInSlideshow(path) { return state.slideshow.indexOf(path) >= 0 }
    function toggleSlideshow(path) { saveState(Logic.toggleSlideshow(state, path)) }
    // Written only when it changes: a click on the chip already shown is no
    // reason to rewrite the file.
    function setPickerFilter(key) {
        const next = Logic.withPickerFilter(state, key)
        if (next.pickerFilter !== pickerFilter) saveState(next)
    }

    function saveState(next) {
        state = next
        fileText = JSON.stringify(next, null, 2) + "\n"
        stateFile.setText(fileText)
    }

    // wallpapers.json as last read or written. The watch reads back every
    // write of our own (docs/testing.md, pitfall 77), and that text is what
    // `state` already holds: parsed again, a new `state` re-ran the pool, the
    // favourites, every tile's marks and every screen's currentFor() once
    // more per click. Another program's write is a different text and loads.
    property string fileText: ""

    function load() {
        const text = stateFile.text()
        // Our own write coming back (see fileText), also before the first
        // read: without a file at start, the first read is of that write.
        if (fileText.length && text === fileText) {
            stateLoaded = true
            return
        }
        // An empty read during a file replacement keeps the current state.
        if (stateLoaded && !text.trim().length) return
        fileText = text
        state = Logic.parseState(text)
        stateLoaded = true
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
        onLoaded: root.load()
        // No file yet is an empty state, and a known one: the screens wait
        // for it (currentFor).
        onLoadFailed: root.stateLoaded = true
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
        // kdialog through launch-app.sh, for the session's environment (the
        // Plasma look and icons); a scope keeps its stdout, which is the answer.
        command: [Paths.script("launch-app.sh"), "org.kde.kdialog", "kdialog", "--title", "Wallpaper folder", "--getexistingdirectory", root.folder]
        stdout: StdioCollector {
            onStreamFinished: { const path = text.trim(); if (path.length) root.setFolder(path) }
        }
    }

    Process {
        id: importProc
        stderr: ErrorLog { label: "WallpaperService.importProc" }
        command: ["sh", "-c", "mkdir -p \"$1\" && \"$2\" org.kde.kdialog kdialog --title 'Add wallpapers' --multiple --separate-output --getopenfilename \"$HOME\" 'Images (*.png *.jpg *.jpeg *.webp)' | while IFS= read -r file; do [ -f \"$file\" ] && cp -n -- \"$file\" \"$1\"/; done", "sh", root.folder, Paths.script("launch-app.sh")]
    }

    readonly property var imageFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]

    // Whether the folder has been read once: the folder itself, its
    // subfolders, and each subfolder's own list - or 2 s, for a folder that
    // never answers (one that is not there stays empty). Until then a
    // screen's own wallpaper is not known to be there (currentFor).
    property bool imagesReady: false
    function checkReady() {
        if (imagesReady || !folder.length) return
        if (folderModel.status !== FolderListModel.Ready || !Logic.listsFolder(folderModel.folder, folder)) return
        if (subfolderModel.status !== FolderListModel.Ready || !Logic.listsFolder(subfolderModel.folder, folder)) return
        if (subfolders.every(path => subfolderImages[path] !== undefined)) imagesReady = true
    }
    Timer {
        interval: 2000
        running: root.folder.length > 0 && !root.imagesReady
        onTriggered: root.imagesReady = true
    }

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
        // A model that lists another folder than the one asked for lists the
        // working directory: FolderListModel goes there when its folder is
        // empty or missing as it is made - at every start, before
        // user-dirs.dirs is read - and a model per folder of the home
        // directory followed. A zip's __MACOSX holds only hidden "._" files
        // and never makes a chip; it was a thread and a watch of its own.
        if (Logic.listsFolder(subfolderModel.folder, root.folder))
            for (let i = 0; i < subfolderModel.count; ++i) {
                const path = subfolderModel.get(i, "filePath")
                if (Logic.isGroupFolder(path)) found.push(path)
            }
        // Only when it actually changed: assigning the same list would restart
        // every Repeater below and with it every scan.
        if (found.length !== subfolders.length || found.some((path, i) => path !== subfolders[i]))
            subfolders = found
        root.refresh()
        root.checkReady()
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
                // Not the working directory's, for a subfolder gone before
                // its model was made (rebuildSubfolders).
                if (Logic.listsFolder(inner.folder, watcher.modelData))
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
        // Not the working directory's images (rebuildSubfolders).
        if (Logic.listsFolder(folderModel.folder, root.folder))
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
        checkReady()
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
    // Twice the picker's sourceWidth, and wider than the overview card's 480.
    // A tile still decodes it at its own sourceWidth: Qt multiplies sourceSize
    // by the devicePixelRatio for an SVG or a PDF only, not for a picture
    // (offscreen at scale 2 the decode came out the same size), so at a
    // devicePixelRatio of 2 (the 1.667 4K screens, pitfall 49) the picker's
    // tiles are drawn from 260 pixels. The Settings grid's tiles are smaller
    // than the picker's.
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
            const sized = found ? Logic.parseThumbSizes(output) : null
            if (sized) root.takeSizes(sized)
            if (root.thumbsQueued) {
                root.thumbsQueued = false
                Qt.callLater(root.makeThumbs)
            }
        }
        stdout: StdioCollector { onStreamFinished: { thumbProc.output = text; thumbProc.outputDone = true; thumbProc.finish() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; finish() }
    }

    // ---- the pictures' sizes ---------------------------------------------------
    // image -> [width, height], for the desktop's decode (WallpaperLogic, "the
    // picture's size and the desktop's decode"): the helper reads each
    // picture's size with its thumbnail. Kept in the cache between starts,
    // because the desktop decodes its first picture long before the first
    // run is in; a size that turns out wrong after a run (a file replaced in
    // place) is decoded again (WallpaperLayer). `sizesRead` once the cache
    // file has answered.
    property var sizes: ({})
    property bool sizesRead: false
    property string sizesStored: ""
    function sizeOf(path) {
        return Object.prototype.hasOwnProperty.call(sizes, path) ? sizes[path] : null
    }
    function takeSizes(found) {
        const text = Logic.sizesText(found)
        if (text === Logic.sizesText(sizes)) return
        sizes = Logic.parseSizes(found) || ({})
        // One write per run at most, and never from the file's own read.
        if (text !== sizesStored) {
            sizesStored = text
            sizesFile.setText(text)
        }
    }
    FileView {
        id: sizesFile
        path: Paths.cacheDir + "/wallpaper-sizes.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.sizesStored = text()
            let stored = null
            try { stored = Logic.parseSizes(JSON.parse(text())) } catch (error) { stored = null }
            // A run that finished first knows better.
            if (stored && !Object.keys(root.sizes).length) root.sizes = stored
            root.sizesRead = true
        }
        onLoadFailed: root.sizesRead = true
    }

    Timer {
        interval: root.intervalMinutes * 60000
        running: root.slideshow && root.pool.length > 1
        repeat: true
        onTriggered: root.next(1)
    }
}
