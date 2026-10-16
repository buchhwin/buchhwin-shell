import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/wallpaper/WallpaperLogic.js" as W

ShellRoot {
    id: root
    property int waits: 0
    property int imageLists: 0
    // A wallpaper folder in the sandbox with two images in it. Their bytes do
    // not matter: the folder is read by name.
    readonly property string wallFolder: Paths.cacheDir + "/wallpaper-test"
    FileView { id: imageA; path: root.wallFolder + "/a.png"; printErrors: false }
    FileView { id: imageB; path: root.wallFolder + "/b.png"; printErrors: false }
    // The service's state file, as it was written.
    FileView { id: written; path: Paths.configDir + "/wallpapers.json"; blockLoading: true; printErrors: false }
    property var writtenState: null
    // The accent from the wallpaper follows every image below, and none of
    // them is one it can read.
    readonly property string accentSource: AdaptiveService.accentSource

    Connections {
        target: WallpaperService
        function onImagesChanged() { root.imageLists += 1 }
    }

    Component.onCompleted: {
        const images = ["/w/a.png", "/w/b.jpg", "/w/c.webp"]
        T.eq(W.parseState("{broken"), W.emptyState(), "broken file")
        const parsed = W.parseState(JSON.stringify({ version: 1, screens: { "DP-1": "/w/b.jpg", "bad name": "/w/a.png", "eDP-1": "relative.png" },
                                                     favourites: ["/w/a.png", "/w/a.png", "/etc/passwd"] }))
        T.eq(parsed.screens, { "DP-1": "/w/b.jpg" }, "invalid screens and paths dropped")
        T.eq(parsed.favourites, ["/w/a.png"], "favourites deduplicated and filtered")
        let state = W.withScreen(W.emptyState(), "DP-1", "/w/c.webp")
        T.eq(W.pathFor(state, "DP-1", "/w/a.png", images), "/w/c.webp", "own wallpaper per screen")
        T.eq(W.pathFor(state, "eDP-1", "/w/a.png", images), "/w/a.png", "other screens use the shared one")
        T.eq(W.pathFor(state, "DP-1", "/w/a.png", ["/w/a.png"]), "/w/a.png", "missing file falls back")
        T.eq(W.withScreen(state, "DP-1", "").screens, {}, "override removed")
        T.eq(W.currentPath("/w/s.png", "/w/b.jpg", images, "", ""), "/w/s.png", "the slideshow's image wins")
        T.eq(W.currentPath("", "/w/b.jpg", images, "", ""), "/w/b.jpg", "a listed configured image needs no check")
        T.eq(W.currentPath("", "/x/far.png", images, "", ""), "", "an unlisted one shows nothing until checked")
        T.eq(W.currentPath("", "/x/far.png", images, "/x/far.png", ""), "/x/far.png", "checked and there")
        T.eq(W.currentPath("", "/x/far.png", images, "/x/far.png", "/x/far.png"), images[0], "checked and missing: the first image")
        T.eq(W.currentPath("", "/x/far.png", [], "/x/far.png", "/x/far.png"), "", "missing and an empty folder: none")
        T.eq(W.currentPath("", "/x/far.png", images, "/x/old.png", ""), "", "an answer for another path does not count")
        T.eq(W.currentPath("", "", images, "", ""), images[0], "nothing configured: the first image")
        state = W.toggleFavourite(W.toggleFavourite(state, "/w/b.jpg"), "/w/c.webp")
        T.eq(state.favourites, ["/w/b.jpg", "/w/c.webp"], "favourites added")
        T.eq(W.toggleFavourite(state, "/w/b.jpg").favourites, ["/w/c.webp"], "favourite removed")
        T.eq(W.pool(images, state, "favourites"), ["/w/b.jpg", "/w/c.webp"], "the favourites source takes the favourites")
        T.eq(W.pool(images, W.emptyState(), "favourites"), images, "with none marked it falls back to every image")
        T.eq(W.pool(images, state, "all"), images, "and the all source is every image")
        T.eq(W.pool(images, state, "nonsense"), images, "a source nobody knows is every image")
        T.eq(W.source("chosen"), "chosen", "a known source is kept")
        T.eq(W.source(true), "all", "and the old boolean is not one")

        // The slideshow's own list, beside the favourites and not the same.
        let chosen = W.toggleSlideshow(state, "/w/a.png")
        T.eq(chosen.slideshow, ["/w/a.png"], "an image is put in the slideshow")
        T.eq(chosen.favourites, state.favourites, "without touching the favourites")
        T.eq(W.toggleSlideshow(chosen, "/w/a.png").slideshow, [], "and taken back out")
        T.eq(W.toggleSlideshow(chosen, "/etc/passwd").slideshow, ["/w/a.png"], "a path that is not an image is refused")
        chosen = W.toggleSlideshow(chosen, "/w/c.webp")
        T.eq(W.pool(images, chosen, "chosen"), ["/w/a.png", "/w/c.webp"], "the chosen source takes exactly those")
        T.eq(W.pool(images, W.emptyState(), "chosen"), images, "an empty choice falls back to every image")
        T.eq(W.slideshowCount(images, chosen), 2, "and the count is what the folder still has")
        // An image the user chose and then moved away is not in the rotation
        // and must not be counted into it either.
        T.eq(W.pool(["/w/c.webp"], chosen, "chosen"), ["/w/c.webp"], "one that left the folder is dropped")
        T.eq(W.slideshowCount(["/w/c.webp"], chosen), 1, "and not counted")
        T.eq(W.slideshowCount(images, W.emptyState()), 0, "nothing chosen is nothing counted")
        T.eq(W.poolIsFallback(images, chosen, "chosen"), false, "a choice that has images is not a fallback")
        T.eq(W.poolIsFallback(images, W.emptyState(), "chosen"), true, "an empty one is, and the UI says so")
        T.eq(W.poolIsFallback(images, W.emptyState(), "all"), false, "every image is never a fallback")

        // A slideshow list survives a round trip through the file, at
        // version 1: a bump would discard everyone's favourites.
        T.eq(W.parseState(JSON.stringify(chosen)).slideshow, ["/w/a.png", "/w/c.webp"], "the list is stored and read back")
        T.eq(W.parseState(JSON.stringify({ version: 1, screens: {}, favourites: [] })).slideshow, [],
             "a file written before the list existed reads as an empty one")
        T.eq(W.parseState(JSON.stringify({ version: 1, screens: {}, favourites: [], slideshow: ["x", "/w/a.png", "/w/a.png"] })).slideshow,
             ["/w/a.png"], "and one with rubbish in it is filtered and deduplicated")
        const folder = ["/w/alps.jpg", "/w/desert.png", "/w/night.webp", "/w/sea.jpeg"]
        const marks = ["/w/night.webp", "/w/alps.jpg"]
        T.eq(W.displayName("/w/desert color1.png"), "desert color1", "label is the basename without the extension")
        T.eq(W.pickerItems(folder, marks, "").map(item => item.name),
             ["alps", "night", "desert", "sea"], "favourites first, each group in folder order")
        T.eq(W.pickerItems(folder, marks, "").map(item => item.favourite),
             [true, true, false, false], "favourites are marked")
        T.eq(W.pickerItems(folder, marks, "e").map(item => item.name),
             ["desert", "sea"], "the query filters on the file name")
        T.eq(W.pickerItems(folder, marks, "a").map(item => item.name),
             ["alps", "sea"], "a filtered grid still lists favourites first")
        T.eq(W.pickerItems(folder, marks, "  NIGHT ").map(item => item.name), ["night"], "the query ignores case and padding")
        T.eq(W.pickerItems(folder, [], "zzz").length, 0, "a query that matches nothing")
        T.eq(W.pickerItems([], marks, "").length, 0, "an empty folder")

        T.ok(W.hoverSelects(false, false), "a resting grid selects under the pointer")
        T.ok(!W.hoverSelects(true, false), "a wheel glide does not select what passes the pointer")
        T.ok(!W.hoverSelects(false, true), "a drag or fling does not either")
        T.eq(W.moveIndex(0, 1, 7, 3), 1, "right moves one on")
        T.eq(W.moveIndex(6, 1, 7, 3), 6, "right stops at the last image")
        T.eq(W.moveIndex(0, -1, 7, 3), 0, "left stops at the first image")
        T.eq(W.moveIndex(1, 3, 7, 3), 4, "down moves one row")
        T.eq(W.moveIndex(5, 3, 7, 3), 5, "down stays put without a full row below")
        T.eq(W.moveIndex(4, -3, 7, 3), 1, "up moves one row")
        T.eq(W.moveIndex(1, -3, 7, 3), 1, "up stays put in the first row")
        T.eq(W.moveIndex(0, 1, 0, 3), 0, "an empty grid stays at zero")

        // The settings migration: two values became three, read on load so
        // nothing depends on a write landing first.
        T.eq(W.migrate({ wallpaper: { favouritesOnly: true, slideshow: true } }).wallpaper,
             { slideshow: true, slideshowSource: "favourites" }, "favourites-only becomes the favourites source")
        T.eq(W.migrate({ wallpaper: { favouritesOnly: false } }).wallpaper,
             { slideshowSource: "all" }, "and off becomes every image")
        T.eq(W.migrate({ wallpaper: { slideshowSource: "chosen", favouritesOnly: true } }).wallpaper,
             { slideshowSource: "chosen" }, "a document that already chose keeps its choice")
        T.eq(W.migrate({ wallpaper: { folder: "~/Pictures" } }).wallpaper, { folder: "~/Pictures" },
             "one that never had the boolean is left alone")
        T.eq(W.migrate({ appearance: {} }), { appearance: {} }, "and so is one with no wallpaper section")
        T.eq(W.migrate(null), null, "nothing at all migrates to nothing at all")

        // ---- subfolders as groups -----------------------------------------

        const home = "/home/x/Pictures/Desktop"
        const flat = home + "/one.png"
        const inNature = home + "/nature/hills.png"
        const deeper = home + "/nature/winter/ice.png"

        T.eq(W.groupOf(flat, home), "", "an image in the folder itself is in no group")
        T.eq(W.groupOf(inNature, home), "nature", "one in a subfolder takes its name")
        T.eq(W.groupOf(deeper, home), "nature", "and one deeper belongs to the group you can see")
        T.eq(W.groupOf(flat, home + "/"), "", "a trailing slash on the folder changes nothing")
        T.eq(W.groupOf("/somewhere/else/x.png", home), "", "a path outside the folder is in no group")
        T.eq(W.groupOf(null, home), "", "and nor is nothing")
        T.eq(W.groupOf(flat, ""), "", "without a folder nothing can be grouped")

        const shelf = [flat, inNature, home + "/abstract/a.png", home + "/nature/lake.png"]
        T.eq(W.groups(shelf, home), ["abstract", "nature"], "the groups are the subfolders that hold something, by name")
        T.eq(W.groups([flat], home), [], "a folder with no subfolders has no groups")
        T.eq(W.groups([], home), [], "and neither has an empty one")

        // The chips. "All" is always there; favourites only when there are
        // any, because a chip that selects nothing looks broken.
        T.eq(W.pickerFilters(shelf, [], home).map(f => f.key), ["", "abstract", "nature"], "no favourites, no favourites chip")
        T.eq(W.pickerFilters(shelf, [flat], home).map(f => f.key), ["", W.FAVOURITES, "abstract", "nature"],
             "with favourites it comes first, before the folders")
        T.eq(W.pickerFilters(shelf, [flat], home)[0].label, "All", "and everything is the first chip")
        // The key keeps its old spelling, only the label is US English like the
        // rest of the interface.
        T.eq(W.pickerFilters(shelf, [flat], home)[1].label, "Favorites", "the starred chip reads Favorites")
        T.eq(W.pickerFilters([], [], home).length, 1, "nothing to group is one chip, which the picker then hides")

        // Filtering. The grid stays one rectangle; only what is in it changes.
        const paths = list => list.map(item => item.path)
        T.eq(paths(W.pickerItems(shelf, [], "", "", home)).length, 4, "no filter is everything")
        T.eq(paths(W.pickerItems(shelf, [], "", "nature", home)), [inNature, home + "/nature/lake.png"],
             "a folder chip shows that folder")
        T.eq(paths(W.pickerItems(shelf, [], "", "abstract", home)), [home + "/abstract/a.png"], "and so does another")
        T.eq(paths(W.pickerItems(shelf, [flat, inNature], "", W.FAVOURITES, home)), [flat, inNature],
             "the favourites chip shows the starred ones wherever they live")
        T.eq(paths(W.pickerItems(shelf, [], "", "nothing-like-this", home)), [], "a folder that is not there shows nothing")

        // The search and the chips narrow together rather than replacing one
        // another - a filter you cannot see the effect of is a filter you
        // fight with.
        T.eq(paths(W.pickerItems(shelf, [], "lake", "nature", home)), [home + "/nature/lake.png"],
             "the search narrows inside the chosen folder")
        T.eq(paths(W.pickerItems(shelf, [], "lake", "abstract", home)), [], "and finds nothing where there is nothing")

        // Favourites still come first inside a filter, and every item says
        // which group it is in so the grid could show it if it ever wants to.
        T.eq(paths(W.pickerItems(shelf, [home + "/nature/lake.png"], "", "nature", home)),
             [home + "/nature/lake.png", inNature], "a starred one leads its folder")
        T.eq(W.pickerItems(shelf, [], "", "", home).map(item => item.group),
             ["", "nature", "abstract", "nature"], "every item carries its group")

        // Called the old way - four arguments, no folder - it behaves exactly
        // as it did, which is what keeps every other caller honest.
        T.eq(paths(W.pickerItems(shelf, [], "")).length, 4, "no folder given is no grouping and no filtering")

        // ---- the picker's last chip ---------------------------------------
        // Kept in wallpapers.json, at version 1, and read as everything when a
        // file from before it has none.
        T.eq(W.emptyState().pickerFilter, "", "nothing remembered is everything")
        T.eq(W.parseState(JSON.stringify({ version: 1, screens: {}, favourites: [] })).pickerFilter, "",
             "a file written before the chip was kept reads as everything")
        T.eq(W.parseState(JSON.stringify({ version: 1, pickerFilter: "nature" })).pickerFilter, "nature",
             "a folder chip is read back")
        T.eq(W.parseState(JSON.stringify({ version: 1, pickerFilter: W.FAVOURITES })).pickerFilter, W.FAVOURITES,
             "and so is the favourites chip")
        T.eq(W.parseState(JSON.stringify({ version: 2, pickerFilter: "nature" })).pickerFilter, "",
             "another version is thrown away whole, the chip with it")
        T.eq([W.pickerFilterKey("a/b"), W.pickerFilterKey(".."), W.pickerFilterKey("."), W.pickerFilterKey(7),
              W.pickerFilterKey("x\u0000y"), W.pickerFilterKey(null), W.pickerFilterKey("x".repeat(256))],
             ["", "", "", "", "", "", ""], "a path, . or .., a number, a NUL or an overlong name is no chip")
        T.eq(W.pickerFilterKey("Über mich #2"), "Über mich #2", "any folder name is")
        const remembered = W.withPickerFilter(state, "nature")
        T.eq(remembered.pickerFilter, "nature", "a chip is remembered")
        T.eq([remembered.favourites, remembered.screens], [state.favourites, state.screens], "without touching the rest")
        T.eq(W.toggleFavourite(remembered, "/w/a.png").pickerFilter, "nature", "marking a favourite keeps the chip")
        T.eq(W.withScreen(remembered, "DP-1", "/w/a.png").pickerFilter, "nature", "and so does a screen's own wallpaper")
        T.eq(W.withPickerFilter(remembered, "").pickerFilter, "", "clicking All remembers everything")

        // Opening: the remembered chip while it is offered, else everything.
        const chips = W.pickerFilters(shelf, [flat], home)
        T.eq(W.openingFilter("nature", chips), "nature", "the picker opens on the folder chosen last")
        T.eq(W.openingFilter(W.FAVOURITES, chips), W.FAVOURITES, "or on the favourites")
        T.eq(W.openingFilter("gone", chips), "", "a folder that is gone opens on everything")
        T.eq(W.openingFilter(W.FAVOURITES, W.pickerFilters(shelf, [], home)), "",
             "and so does the favourites chip with nothing starred")
        T.eq(W.openingFilter("", chips), "", "everything opens on everything")

        // While it is open: the chips change as the folder is read, and as
        // folders come and go.
        T.eq(W.filterAfterChange("nature", chips, ""), "nature", "a chip still offered stays")
        T.eq(W.filterAfterChange("nature", W.pickerFilters([flat], [], home), ""), "",
             "one that went falls back to everything")
        T.eq(W.filterAfterChange("", W.pickerFilters([flat], [], home), "nature"), "",
             "the remembered chip waits while its folder is not read yet")
        T.eq(W.filterAfterChange("", chips, "nature"), "nature", "and is shown once it is offered")
        T.eq(W.filterAfterChange("abstract", chips, ""), "abstract", "nothing awaited leaves the chosen chip alone")
        T.ok(W.offersFilter(chips, "") && W.offersFilter(chips, "abstract") && !W.offersFilter(chips, "gone")
             && !W.offersFilter(null, "nature"), "offersFilter: everything always, a folder only while it is a chip")

        // ---- a rotation that stays inside one folder ----------------------

        const anyState = { favourites: [], slideshow: [], screens: {} }
        T.eq(W.source("folder"), "folder", "one folder is a source the slideshow knows")
        T.eq(W.pool(shelf, anyState, "folder", home, "nature"),
             [inNature, home + "/nature/lake.png"], "and it rotates only through that folder")
        T.eq(W.pool(shelf, anyState, "folder", home, ""), [flat], "the wallpaper folder itself is a choice too")
        T.eq(W.poolIsFallback(shelf, anyState, "folder", home, "nature"), false, "a folder with images does not fall back")

        // A folder that has emptied out falls back to everything rather than
        // showing nothing for a turn - the same rule the other sources have -
        // and the page says so instead of leaving it to be wondered about.
        T.eq(W.pool(shelf, anyState, "folder", home, "gone").length, 4, "an empty folder falls back to every image")
        T.eq(W.poolIsFallback(shelf, anyState, "folder", home, "gone"), true, "and says that is what it did")
        T.eq(W.poolIsFallback(shelf, anyState, "all", home, ""), false, "everything never falls back")

        // The folder: the pictures directory from user-dirs.dirs, so a German
        // system gets ~/Bilder/Desktop rather than a ~/Pictures that is not there.
        const dirs = '# written by xdg-user-dirs-update\nXDG_DESKTOP_DIR="$HOME/Schreibtisch"\nXDG_PICTURES_DIR="$HOME/Bilder"\n'
        T.eq(W.picturesDir(dirs, "/home/u"), "/home/u/Bilder", "pictures directory from $HOME")
        T.eq(W.picturesDir('XDG_PICTURES_DIR="/data/pics"', "/home/u"), "/data/pics", "an absolute pictures directory")
        T.eq([W.picturesDir("", "/home/u"), W.picturesDir('XDG_PICTURES_DIR="$(rm -rf ~)"', "/home/u"),
              W.picturesDir('XDG_PICTURES_DIR="$HOME"', "/home/u")], ["", "", ""], "missing, shell code or bare home is no answer")
        T.eq(W.defaultFolder("/home/u/Bilder", "/home/u"), "/home/u/Bilder/Desktop", "default follows the pictures directory")
        T.eq(W.defaultFolder("", "/home/u"), "/home/u/Pictures/Desktop", "and falls back to ~/Pictures")
        T.eq([W.contractHome("/home/u/Bilder/Desktop", "/home/u"), W.contractHome("/home/uu/x", "/home/u"),
              W.contractHome("/srv/w", "/home/u")], ["~/Bilder/Desktop", "/home/uu/x", "/srv/w"], "home contracted only at a boundary")
        T.eq(W.folderUrl("/home/u/Bilder/Desktop"), "file:///home/u/Bilder/Desktop", "a plain folder url")
        T.eq(W.folderUrl("/home/u/a#b/x?y/50%2F/Über mich"), "file:///home/u/a%23b/x%3Fy/50%252F/%C3%9Cber%20mich",
             "#, ?, % and the rest encoded per segment")
        T.eq(W.folderUrl(""), "", "no folder, no url")

        // Thumbnails: the helper's answer, and the url a tile loads.
        const answer = JSON.stringify({ thumbs: { "/w/a.png": "/c/0a.jpg", "/w/b.jpg": "/c/1b.jpg",
                                                  "relative.png": "/c/2c.jpg", "/w/c.webp": "../x.jpg",
                                                  "/w/d.png": 7, "/w/e.png": "/c/3d.png" } })
        T.eq(W.parseThumbs(answer), { "/w/a.png": "/c/0a.jpg", "/w/b.jpg": "/c/1b.jpg" },
             "only image paths mapped to absolute .jpg files are kept")
        T.eq(W.parseThumbs('{"thumbs": {}}'), {}, "a run that made nothing is an empty map")
        T.eq([W.parseThumbs(""), W.parseThumbs("{broken"), W.parseThumbs('{"thumbs": []}'), W.parseThumbs("{}")],
             [null, null, null, null], "no answer, a broken one or the wrong shape keeps what is there")
        const thumbs = { "/w/a.png": "/home/u/.cache/buchhwin-shell/wallpaper-thumbs/0a.jpg", "/w/h.png": "/home/a#b/c.jpg" }
        T.eq(W.thumbUrl(thumbs, "/w/a.png"), "file:///home/u/.cache/buchhwin-shell/wallpaper-thumbs/0a.jpg",
             "an image with a thumbnail gets its url")
        T.eq(W.thumbUrl(thumbs, "/w/h.png"), "file:///home/a%23b/c.jpg", "encoded like a folder url")
        T.eq([W.thumbUrl(thumbs, "/w/none.png"), W.thumbUrl({}, "/w/a.png"), W.thumbUrl(null, "/w/a.png"),
              W.thumbUrl(thumbs, "constructor")], ["", "", "", ""], "none yet is \"\", so the tile loads the image")
        T.eq(W.recentFolders(" ~/a, ~/b,,~/a "), ["~/a", "~/b"], "recent folders trimmed and unique")
        T.eq(W.addRecentFolder("~/a,~/b", "~/b"), "~/b,~/a", "a reused folder moves to the front")
        T.eq(W.addRecentFolder("~/1,~/2,~/3,~/4,~/5", "~/6").split(",").length, 5, "at most five")
        T.eq(W.addRecentFolder("~/a", "~/x,y"), "~/a", "a comma would split the list, so it is not stored")

        // ---- WallpaperService in the sandbox: a configured image that is gone
        imageA.setText("a\n")
        imageB.setText("b\n")
        SettingsService.setAll({ "wallpaper.folder": root.wallFolder, "wallpaper.path": root.wallFolder + "/gone.png",
                                 "appearance.accentFromWallpaper": true, "appearance.accent": "#50e2cb" })
        missing.start()
    }

    // The configured file is not there: the desktop gets the folder's first
    // image rather than a path that draws nothing.
    Timer {
        id: missing
        interval: 50
        repeat: true
        onTriggered: {
            root.waits += 1
            const there = WallpaperService.images.length === 2 && WallpaperService.configuredMissing
            if (!there && root.waits < 100) return
            stop()
            T.eq(WallpaperService.images, [root.wallFolder + "/a.png", root.wallFolder + "/b.png"], "the folder's two images")
            T.ok(WallpaperService.configuredMissing, "the configured image is known to be gone")
            T.eq(WallpaperService.current, root.wallFolder + "/a.png", "and the first image of the folder is the wallpaper")
            SettingsService.set("wallpaper.path", root.wallFolder + "/b.png")
            T.eq(WallpaperService.current, root.wallFolder + "/b.png", "an image the folder lists is taken at once")
            // The same list again is not a new one.
            const lists = root.imageLists
            WallpaperService.refresh()
            T.eq(root.imageLists, lists, "reading the same folder again does not hand out a new list")
            // A file outside the folder is asked for; this one is there.
            const outside = Quickshell.shellPath("config/builtin-profiles/buchhwin/saturn.txt")
            SettingsService.set("wallpaper.path", outside)
            T.eq(WallpaperService.current, "", "a file outside the folder shows nothing until it was asked for")
            root.waits = 0
            outsideFile.start()
        }
    }

    Timer {
        id: outsideFile
        interval: 1500
        onTriggered: {
            T.ok(!WallpaperService.configuredMissing, "one that is there stays the wallpaper after it was asked")
            T.eq(WallpaperService.current, Quickshell.shellPath("config/builtin-profiles/buchhwin/saturn.txt"), "as it was")
            T.eq(root.accentSource, WallpaperService.current, "the accent was asked for each wallpaper")
            T.eq(SettingsService.value("appearance.accent"), "#50e2cb",
                 "and an image that is gone or cannot be read keeps the accent rather than turning it blue")
            ownWrite.start()
        }
    }

    // wallpapers.json is watched, and the watch reads back every write of the
    // service's own (pitfall 77): that text is the state it holds, and parsed
    // again it handed out a new state that re-ran every binding on it.
    Timer {
        id: ownWrite
        interval: 50
        onTriggered: {
            WallpaperService.toggleFavourite(root.wallFolder + "/a.png")
            root.writtenState = WallpaperService.state
            T.eq(WallpaperService.favourites, [root.wallFolder + "/a.png"], "a favourite is marked")
            readBack.start()
        }
    }

    Timer {
        id: readBack
        interval: 400
        onTriggered: {
            written.reload()
            T.ok(WallpaperService.state === root.writtenState, "the watch reading the write back hands out no new state")
            WallpaperService.load()
            T.ok(WallpaperService.state === root.writtenState, "and neither does reading it again")
            T.eq(WallpaperService.fileText, written.text(), "the service knows the file as it wrote it")
            chipWrite.start()
        }
    }

    // The picker's last chip goes into the same file, beside the favourites,
    // and the chip already shown is no reason to write it again.
    Timer {
        id: chipWrite
        interval: 50
        onTriggered: {
            WallpaperService.setPickerFilter("nature")
            T.eq(WallpaperService.pickerFilter, "nature", "the picker's chip is remembered")
            T.eq(WallpaperService.favourites, [root.wallFolder + "/a.png"], "and the favourites stay")
            root.writtenState = WallpaperService.state
            WallpaperService.setPickerFilter("nature")
            T.ok(WallpaperService.state === root.writtenState, "the same chip again writes nothing")
            chipRead.start()
        }
    }

    // A FileView of its own, given its path only now: `written` above does not
    // read the file again on a second reload() after the atomic replace.
    property string chipPath: ""
    FileView { id: chipFile; path: root.chipPath; blockLoading: true; printErrors: false }

    Timer {
        id: chipRead
        interval: 400
        onTriggered: {
            root.chipPath = Paths.configDir + "/wallpapers.json"
            const stored = W.parseState(chipFile.text())
            T.eq([stored.pickerFilter, stored.favourites], ["nature", [root.wallFolder + "/a.png"]],
                 "wallpapers.json holds the chip next to the favourites")
            T.finish("WallpaperTest")
        }
    }
}
