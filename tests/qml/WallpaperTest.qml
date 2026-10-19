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
    // Where a wallpaper is handed to Qt: the desktop and an overview card.
    FileView { id: layerSource; path: Quickshell.shellPath("shell/desktop/WallpaperLayer.qml"); blockLoading: true }
    FileView { id: overviewSource; path: Quickshell.shellPath("shell/overview/Overview.qml"); blockLoading: true }
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
        // ---- a screen's own wallpaper at a start ---------------------------
        // wallpapers.json and the folder are read in steps; until both are in
        // a screen's own choice is not known, nor whether it is there.
        const own = W.withScreen(W.emptyState(), "DP-1", "/w/c.webp")
        T.eq(W.pathFor(own, "DP-1", "/w/a.png", [], false, true), "",
             "an own choice the folder has not listed yet waits instead of showing the shared one first")
        T.eq(W.pathFor(own, "DP-1", "/w/a.png", images, false, true), "/w/c.webp", "and is taken once it is listed")
        T.eq(W.pathFor(own, "DP-1", "/w/a.png", ["/w/a.png"], true, true), "/w/a.png",
             "with the folder read, one that is not there falls back")
        T.eq(W.pathFor(own, "eDP-1", "/w/a.png", [], false, true), "/w/a.png",
             "a screen known to have none takes the shared one at once")
        T.eq([W.pathFor(own, "DP-1", "/w/a.png", images, true, false), W.pathFor(W.emptyState(), "eDP-1", "/w/a.png", images, true, false)],
             ["", ""], "before wallpapers.json is read nobody knows, so nothing yet")
        T.eq(W.pathFor(own, "DP-1", "/w/a.png", images), "/w/c.webp", "called as before, it is as before")

        // ---- names --------------------------------------------------------
        T.eq(W.displayName("/w/Desert_Color1.jpg"), "Desert Color1", "underscores read as spaces, as Settings shows it")
        T.eq([W.displayName("/w/night-sky--2.png"), W.displayName("/w/_x_.webp"), W.displayName("/w/___.png")],
             ["night sky 2", "x", "___"], "dashes too, runs collapse, a name of nothing but those keeps its stem")
        T.eq(W.baseName("/w/Desert_Color1.jpg"), "Desert_Color1", "the file's own stem is still there")
        T.eq(W.pickerItems(["/w/Desert_Color1.jpg", "/w/sea.png"], [], "desert_c").map(item => item.name), ["Desert Color1"],
             "the search finds the file by its own name")
        T.eq(W.pickerItems(["/w/Desert_Color1.jpg", "/w/sea.png"], [], "desert c").map(item => item.name), ["Desert Color1"],
             "and by its label")
        T.eq(W.screenChoices(["DP-8", "eDP-1", "DP-10"], name => ({ "eDP-1": 3, "DP-8": 1, "DP-10": 2 })[name]),
             [{ value: "", label: "All displays" }, { value: "DP-8", label: "1 \u00b7 DP-8" },
              { value: "DP-10", label: "2 \u00b7 DP-10" }, { value: "eDP-1", label: "3 \u00b7 eDP-1" }],
             "the displays numbered and ordered as Settings > Displays numbers them")
        T.eq(W.screenChoices(["B", "A"], () => 0).map(item => item.label), ["All displays", "B", "A"],
             "without numbers the bare names, in their order")
        T.eq(W.screenChoices([], null), [{ value: "", label: "All displays" }], "no screens is all displays")

        // ---- the desktop's url ----------------------------------------------
        // The layer loads W.folderUrl(path): a "#", "?" or "%25" in a file
        // name is part of the name, not a fragment, a query or an escape.
        T.eq([W.folderUrl("/w/wall #1.png"), W.folderUrl("/w/what?.png"), W.folderUrl("/w/50%25 off.png")],
             ["file:///w/wall%20%231.png", "file:///w/what%3F.png", "file:///w/50%2525%20off.png"],
             "a wallpaper's own name is encoded, as the picker's tiles are")
        // "file://" and the bare path was what the desktop loaded, and such a
        // picture showed only the background colour there.
        T.ok(layerSource.text().indexOf("Logic.folderUrl(path)") >= 0 && layerSource.text().indexOf("\"file://\"") < 0,
             "the desktop loads its pictures through folderUrl")
        T.ok(overviewSource.text().indexOf("WallpaperLogic.folderUrl(WallpaperService.currentFor(") >= 0,
             "and so does an overview card without a thumbnail")

        // ---- which folder a FolderListModel lists ---------------------------
        T.ok(W.listsFolder("file:///home/u/Bilder/Desktop", "/home/u/Bilder/Desktop"), "the folder asked for")
        T.ok(W.listsFolder("file:///home/u/%C3%9Cber%20mich%20%232", "/home/u/Über mich #2")
             && W.listsFolder("file:///home/u/Über mich %232", "/home/u/Über mich #2"), "encoded or handed back half decoded")
        T.ok(W.listsFolder("file:///home/u/w/", "/home/u/w") && W.listsFolder("file:///home/u/w", "/home/u/w/"), "a trailing slash either side")
        T.ok(!W.listsFolder("file:///home/u", "/home/u/Bilder/Desktop"), "not the working directory Qt went to instead")
        T.ok(!W.listsFolder("file:///home/u", "") && !W.listsFolder("", "/w") && !W.listsFolder("file:///w%E0", "/w"),
             "nor anything when no folder is asked for, none is listed or the url is broken")
        T.eq(["/w/nature", "/w/__MACOSX", "/w/.hidden", "/w/a/"].map(W.isGroupFolder), [true, false, false, true],
             "a zip's __MACOSX and hidden folders are never groups")

        // ---- the desktop's decode -------------------------------------------
        // Qt scales the picture to cover the screen (max of the two ratios,
        // rounded) and keeps the centred screen-sized part of it; probed
        // offscreen with the shipped settings: 2820x1200 decoded before,
        // exactly 1920x1200 with this clip.
        const laptop = W.decodeGeometry([5640, 2400], 1920, 1200)
        T.eq([laptop.width, laptop.height, laptop.clip], [2820, 1200, { x: 450, y: 0, width: 1920, height: 1200 }],
             "a 2.35:1 picture on the 1920x1200 panel: scaled to cover, and only its centre kept")
        T.eq(W.decodeGeometry([5640, 2400], 3840, 2160).clip, { x: 618, y: 0, width: 3840, height: 2160 }, "on a 4K screen")
        T.eq(W.decodeGeometry([5641, 2401], 1920, 1200).clip, { x: 449, y: 0, width: 1920, height: 1200 },
             "Qt rounds the scaled 2819.3 to 2819")
        T.eq(W.decodeGeometry([5639, 2399], 1920, 1200).clip.x, 450, "and 2820.7 to 2821")
        T.eq(W.decodeGeometry([6000, 3750], 3840, 2160).clip, { x: 0, y: 120, width: 3840, height: 2160 },
             "a 16:10 picture on a 16:9 screen is cut at the top and bottom")
        const portrait = W.decodeGeometry([5640, 2400], 1440, 2560)
        T.eq([portrait.width, portrait.height, portrait.clip], [5640, 2400, { x: 2145, y: 0, width: 1350, height: 2400 }],
             "a portrait screen taller than the picture: not enlarged on decode, the screen's shape cut from it")
        const small = W.decodeGeometry([1600, 1000], 1920, 1200)
        T.eq([small.width, small.height, small.clip], [1600, 1000, { x: 0, y: 0, width: 1600, height: 1000 }],
             "a picture smaller than the screen is decoded as it is")
        T.eq(W.decodeGeometry([1920, 1200], 1920, 1200).clip, { x: 0, y: 0, width: 1920, height: 1200 }, "one of the screen's own size")
        const plain = W.decodeGeometry(null, 1920, 1200)
        T.eq([plain.width, plain.height, plain.clip, plain.natural], [1920, 1200, null, null], "without a size, the screen's size as before")
        T.eq([W.decodeGeometry([0, 10], 1920, 1200).clip, W.decodeGeometry([10.5, 10], 1920, 1200).clip,
              W.decodeGeometry("big", 1920, 1200).clip, W.decodeGeometry([5640, 2400], 0, 0).clip], [null, null, null, null],
             "a size that is no size, or no screen yet, is no clip")
        T.eq([laptop.natural, laptop.screen], [[5640, 2400], [1920, 1200]], "and it says what it was worked out from")
        // A size that is wrong (a file replaced in place, until the next run
        // says so) keeps the clip inside what Qt decodes: Qt scales the real
        // picture to at least the size asked for. Past its edge it was black.
        const qtScaled = (real, asked) => {
            const ratio = Math.max(asked[0] / real[0], asked[1] / real[1])
            return [Math.round(real[0] * ratio), Math.round(real[1] * ratio)]
        }
        const inside = (geometry, real) => {
            const scaled = qtScaled(real, [geometry.width, geometry.height])
            const clip = geometry.clip
            return clip.x >= 0 && clip.y >= 0 && clip.x + clip.width <= scaled[0] && clip.y + clip.height <= scaled[1]
        }
        T.ok([[[6000, 3000], [6000, 3750]], [[5640, 2400], [3000, 4000]], [[1600, 1000], [6000, 3750]], [[6000, 3750], [1600, 1000]],
              [[3000, 4000], [5640, 2400]], [[5640, 2400], [5640, 2400]]]
             .every(pair => [[1920, 1200], [3840, 2160], [1440, 2560]].every(screen =>
                 inside(W.decodeGeometry(pair[0], screen[0], screen[1]), pair[1]))),
             "a wrong size never puts the clip past the picture")

        // Decoded again only when it has to be.
        T.ok(!W.needsRedecode(laptop, W.decodeGeometry([5640, 2400], 1920, 1200)), "the same is the same")
        T.ok(W.needsRedecode(laptop, W.decodeGeometry([5640, 2400], 2560, 1600)), "another mode decodes again")
        T.ok(W.needsRedecode(laptop, W.decodeGeometry([6000, 3750], 1920, 1200)), "and so does a file replaced in place")
        T.ok(!W.needsRedecode(plain, laptop), "a size only learnt now is no reason for a second decode at a start")
        T.ok(!W.needsRedecode(laptop, plain), "nor is a size forgotten")
        T.ok(W.needsRedecode(plain, W.decodeGeometry(null, 1200, 1920)), "but a turned screen is")
        T.ok(!W.needsRedecode(null, laptop) && !W.needsRedecode(laptop, null), "nothing shown or wanted is nothing to do")

        // The sizes: the helper's answer and the file the service keeps.
        T.eq(W.parseThumbSizes(JSON.stringify({ thumbs: {}, sizes: { "/w/a.png": [6000, 3750], "/w/b.jpg": [1, 2, 3],
                                                                    "x.png": [10, 10], "/w/c.png": [0, 5], "/w/d.png": [2.5, 4],
                                                                    "/w/e.png": "6000x3750", "/w/f.png": [70000, 10] } })),
             { "/w/a.png": [6000, 3750] }, "only image paths with two whole sizes are kept")
        T.eq([W.parseThumbSizes(JSON.stringify({ thumbs: {} })), W.parseThumbSizes("{broken"), W.parseThumbSizes("")],
             [null, null, null], "an answer without sizes keeps the sizes there are")
        T.eq(W.parseSizes({}), {}, "an empty map is a map")
        T.eq(W.sizesText({ "/w/b.png": [2, 1], "/w/a.png": [4, 3] }), '{"/w/a.png":[4,3],"/w/b.png":[2,1]}\n',
             "the file is sorted, so the same sizes are the same text")
        T.eq(W.sizesText(null), "{}\n", "and no sizes are an empty map")

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
            sizesWrite.start()
        }
    }

    // The pictures' sizes for the desktop's decode: taken from a run, kept
    // in the cache for the next start, and written only when they change.
    property string sizesPath: ""
    FileView { id: sizesBack; path: root.sizesPath; blockLoading: true; printErrors: false }
    Timer {
        id: sizesWrite
        interval: 50
        onTriggered: {
            T.ok(WallpaperService.sizesRead, "the sizes file has answered (or is not there) by now")
            const found = {}
            found[root.wallFolder + "/b.png"] = [6000, 3750]
            found[root.wallFolder + "/a.png"] = [5640, 2400]
            WallpaperService.takeSizes(found)
            T.eq(WallpaperService.sizeOf(root.wallFolder + "/a.png"), [5640, 2400], "a run's sizes are taken")
            T.eq([WallpaperService.sizeOf(root.wallFolder + "/gone.png"), WallpaperService.sizeOf("constructor")], [null, null],
                 "an image without one has none")
            T.eq(WallpaperService.sizesStored, W.sizesText(found), "and written to the cache, sorted")
            const before = WallpaperService.sizes
            WallpaperService.takeSizes(JSON.parse(JSON.stringify(found)))
            T.ok(WallpaperService.sizes === before, "the same sizes again change nothing")
            sizesRead.start()
        }
    }
    // Against what was written last: the folder's own thumbnail run may land
    // in between, with sizes of its own.
    Timer {
        id: sizesRead
        interval: 400
        onTriggered: {
            root.sizesPath = Paths.cacheDir + "/wallpaper-sizes.json"
            T.eq(sizesBack.text(), WallpaperService.sizesStored, "the cache holds what was written")
            T.finish("WallpaperTest")
        }
    }
}
