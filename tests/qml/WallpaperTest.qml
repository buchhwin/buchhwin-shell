import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/wallpaper/WallpaperLogic.js" as W

ShellRoot {
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

        T.finish("WallpaperTest")
    }
}
