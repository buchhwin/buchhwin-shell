.pragma library
.import "../system/UserDirsLogic.js" as UserDirs

// Per-monitor wallpapers, favourites and the slideshow's own list
// (wallpapers.json). Unit tested.
//
// Favourites used to do two jobs: "starred in the picker" and "what the
// slideshow uses". They are two questions - a wallpaper can be a favourite
// without belonging in a rotation - so the slideshow has its own list beside
// them and `wallpaper.slideshowSource` says which of the three it takes.
//
// The file stays at version 1. `parseState` throws away anything with another
// version, so a bump to carry a new key would discard every existing user's
// favourites and per-screen choices; a key that is simply absent reads as an
// empty list, which is what a new key should do. The picker's last chip
// (`pickerFilter`) came that way and reads as "" - everything - when absent.
// "folder" is the fourth, and the reason subfolders exist at all: a rotation
// that stays inside one group rather than wandering through everything.
var SOURCES = ["all", "favourites", "chosen", "folder"]

function source(value) {
    return SOURCES.indexOf(value) >= 0 ? value : "all"
}

function emptyState() {
    return { version: 1, screens: {}, favourites: [], slideshow: [], pickerFilter: "" }
}

function isImagePath(path) {
    return typeof path === "string" && path.startsWith("/") && /\.(png|jpe?g|webp)$/i.test(path)
}

function parseState(text) {
    let data = null
    try { data = JSON.parse(text) } catch (error) { return emptyState() }
    if (!data || data.version !== 1) return emptyState()
    const state = emptyState()
    if (data.screens && typeof data.screens === "object")
        for (const name of Object.keys(data.screens))
            if (/^[A-Za-z0-9_.-]+$/.test(name) && isImagePath(data.screens[name])) state.screens[name] = data.screens[name]
    if (Array.isArray(data.favourites)) {
        const seen = {}
        state.favourites = data.favourites.filter(path => isImagePath(path) && !seen[path] && (seen[path] = true))
    }
    if (Array.isArray(data.slideshow)) {
        const seen = {}
        state.slideshow = data.slideshow.filter(path => isImagePath(path) && !seen[path] && (seen[path] = true))
    }
    state.pickerFilter = pickerFilterKey(data.pickerFilter)
    return state
}

function withScreen(state, screen, path) {
    const next = parseState(JSON.stringify(state))
    if (path) next.screens[screen] = path
    else delete next.screens[screen]
    return next
}

function toggleFavourite(state, path) {
    const next = parseState(JSON.stringify(state))
    const index = next.favourites.indexOf(path)
    if (index >= 0) next.favourites.splice(index, 1)
    else if (isImagePath(path)) next.favourites.push(path)
    return next
}

// The same for the slideshow's own list.
function toggleSlideshow(state, path) {
    const next = parseState(JSON.stringify(state))
    const index = next.slideshow.indexOf(path)
    if (index >= 0) next.slideshow.splice(index, 1)
    else if (isImagePath(path)) next.slideshow.push(path)
    return next
}

// How many of the chosen images are still in the folder. An image the user
// picked and then moved away is not in the rotation and must not be counted
// into it, or the footer says seven and the slideshow shows six.
function slideshowCount(images, state) {
    const list = state && Array.isArray(state.slideshow) ? state.slideshow : []
    return (images || []).filter(path => list.indexOf(path) >= 0).length
}

// The shared wallpaper. The slideshow's image wins; then the configured one -
// but only once it is known to be there: an image the folder lists is, any
// other waits for its `test -f` (checkedPath) and shows nothing meanwhile, a
// few milliseconds at a start. Handed to the desktop before the answer, a
// configured file that is not there (a profile from another machine) drew
// nothing for the debounce's second and logged "Cannot open". A missing one
// gives way to the folder's first image.
function currentPath(slideshowPath, configuredPath, images, checkedPath, missingPath) {
    if (slideshowPath) return slideshowPath
    const list = images || []
    if (configuredPath) {
        if (list.indexOf(configuredPath) >= 0) return configuredPath
        if (checkedPath !== configuredPath) return ""
        if (missingPath !== configuredPath) return configuredPath
    }
    return list.length ? list[0] : ""
}

// The configured wallpaper for the theme. Settings > Wallpaper "A wallpaper
// for each theme" (`wallpaper.themePair`, off by default) keeps one for the
// light theme and one for the dark (`wallpaper.lightPath`, `darkPath`); a
// side that has none yet shows the shared one (`wallpaper.path`), so turning
// the pair on changes nothing until a picture is picked for a side. Only the
// shown one is decoded: the other is read at the switch, through the
// desktop's cross-fade.
function themePath(pairOn, dark, lightPath, darkPath, path) {
    const shared = typeof path === "string" ? path : ""
    if (pairOn !== true) return shared
    const own = dark === true ? darkPath : lightPath
    return typeof own === "string" && own.length ? own : shared
}

// Which picture `themePath` gives: "light", "dark" or "shared" (the pair off,
// or the theme's side empty). For Settings and the IPC, which name no file.
function themeSide(pairOn, dark, lightPath, darkPath) {
    if (pairOn !== true) return "shared"
    const own = dark === true ? darkPath : lightPath
    return typeof own === "string" && own.length ? (dark === true ? "dark" : "light") : "shared"
}

// The setting a picked wallpaper goes into: with the pair on, the side of the
// theme in use - picking in the dark theme sets the dark one -, else the
// shared one.
function pickKey(pairOn, dark) {
    if (pairOn !== true) return "wallpaper.path"
    return dark === true ? "wallpaper.darkPath" : "wallpaper.lightPath"
}

// Wallpaper for one screen: its own choice if the file is still available.
//
// At a start wallpapers.json and the folder are read in steps. Until
// `stateRead` (left out: true) it is not known whether the screen has a
// choice of its own, and until `settled` (the folder read, left out: true)
// not whether its own one is there: "" meanwhile - nothing yet, as
// `currentPath` answers before its check - spares the desktop a first decode
// of the shared picture and a cross-fade to the screen's own one a moment
// later. A screen known to have no choice of its own takes the shared one at
// once.
function pathFor(state, screen, fallback, available, settled, stateRead) {
    const own = state.screens[screen]
    if (stateRead === false) return ""
    if (own && (!available || available.indexOf(own) >= 0)) return own
    if (own && settled === false) return ""
    return fallback
}

// Images the slideshow rotates through, for one of the three sources. In every
// case the folder decides what exists: a path that has left it is dropped
// rather than handed to the slideshow, which would show nothing for one turn.
//
// An empty result falls back to every image. That fallback is old and it
// stays, but the UI now says so instead of leaving the user to wonder why a
// rotation they narrowed to nothing shows everything.
function pool(images, state, which, folder, group) {
    const all = images || []
    const picked = source(which)
    if (picked === "all") return all
    if (picked === "folder") {
        const kept = all.filter(path => groupOf(path, folder) === String(group || ""))
        return kept.length ? kept : all
    }
    const list = picked === "favourites"
        ? (state && Array.isArray(state.favourites) ? state.favourites : [])
        : (state && Array.isArray(state.slideshow) ? state.slideshow : [])
    const kept = all.filter(path => list.indexOf(path) >= 0)
    return kept.length ? kept : all
}

// Whether `pool` had to fall back, so the UI can say so.
function poolIsFallback(images, state, which, folder, group) {
    const picked = source(which)
    if (picked === "all") return false
    if (picked === "folder")
        return (images || []).filter(p => groupOf(p, folder) === String(group || "")).length === 0
    return pool(images, state, picked).length === (images || []).length
        && ((picked === "favourites"
             ? (images || []).filter(p => (state.favourites || []).indexOf(p) >= 0)
             : (images || []).filter(p => (state.slideshow || []).indexOf(p) >= 0)).length === 0)
}

// ---- folders -------------------------------------------------------------

// The name of the subfolder an image sits in, relative to the wallpaper
// folder, or "" for one sitting directly in it.
//
// Only one level: `root/nature/hills.png` is "nature", and so is
// `root/nature/winter/ice.png` - a picture two folders deep belongs to the
// group you can see, not to one you would have to go looking for. The scan is
// one level deep as well, so the second case does not arise today; the rule is
// here so that it cannot arrive by accident later.
function groupOf(path, folder) {
    const full = String(path || "")
    const base = String(folder || "").replace(/\/+$/, "")
    if (!base.length || full.indexOf(base + "/") !== 0) return ""
    const rest = full.slice(base.length + 1)
    const cut = rest.indexOf("/")
    return cut < 0 ? "" : rest.slice(0, cut)
}

// The groups the picker offers, in the order it offers them: every subfolder
// that actually holds an image, sorted by name. Named rather than counted,
// because a folder the user made and then emptied is not a group any more -
// and a chip that selects nothing is a chip that looks broken.
function groups(images, folder) {
    const found = []
    for (const path of images || []) {
        const name = groupOf(path, folder)
        if (name.length && found.indexOf(name) < 0) found.push(name)
    }
    return found.sort((a, b) => a.localeCompare(b))
}

// Basename without the extension: what the picker's search matches.
function baseName(path) {
    const file = String(path || "").split("/").pop()
    return file.replace(/\.(png|jpe?g|webp)$/i, "")
}

// The label of a wallpaper: the basename with underscores and dashes as
// spaces, "Desert_Color1.png" as "Desert Color1" - the picker showed the
// file's stem and Settings the same file prettified, two names for one
// picture. A name that is nothing but those keeps its stem.
function displayName(path) {
    const stem = baseName(path)
    const pretty = stem.replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim()
    return pretty.length ? pretty : stem
}

// The picker's grid: favourites first, then the rest of the folder, each group
// keeping the folder's order. `query` filters on the file name. Unit tested.
//
// `filter` narrows it to one group: "" is everything, "*favourites" is the
// starred ones, anything else is a subfolder's name. It is a *filter* and not
// a grouping with headings on purpose - the grid stays one rectangle, so the
// arrow keys keep working on a single run of cells and nothing has to learn
// where a group ends.
//
// `folder` is only needed to work out which group a path is in, so leaving it
// out (as everything did before there were groups) simply shows everything.
function pickerItems(images, favourites, query, filter, folder) {
    const marks = favourites || []
    const needle = String(query || "").trim().toLowerCase()
    const want = String(filter || "")
    const list = (images || []).filter(path => {
        // The label and the file's own name: "desert_c" still finds the
        // file the label calls "Desert Color1".
        if (needle.length && displayName(path).toLowerCase().indexOf(needle) < 0
                && baseName(path).toLowerCase().indexOf(needle) < 0) return false
        if (!want.length) return true
        if (want === FAVOURITES) return marks.indexOf(path) >= 0
        return groupOf(path, folder) === want
    })
    const starred = list.filter(path => marks.indexOf(path) >= 0)
    const rest = list.filter(path => marks.indexOf(path) < 0)
    return starred.concat(rest).map(path => ({ path: path, name: displayName(path),
                                               favourite: marks.indexOf(path) >= 0,
                                               group: groupOf(path, folder) }))
}

// The favourites chip is not a folder, and a folder could be called
// "favourites", so it is spelled with a character a path cannot contain.
var FAVOURITES = "*favourites"

// The chips above the grid: everything, the starred ones when there are any,
// then one per subfolder. `key` is what `pickerItems` takes as its filter.
function pickerFilters(images, favourites, folder) {
    const result = [{ key: "", label: "All" }]
    if ((favourites || []).length) result.push({ key: FAVOURITES, label: "Favorites" })
    for (const name of groups(images, folder)) result.push({ key: name, label: name })
    return result
}

// ---- the picker's last chip --------------------------------------------------
// The picker opens on the chip chosen last: a folder of wallpapers one keeps
// going back to is where it opens, not one click away again after every open.
// It is kept in wallpapers.json beside the favourites, not in settings.json:
// it is the same in every profile - a profile switch saves and restores
// settings.json, and must not move the picker to another folder - and a chip
// click is not a settings change for the undo history.

// A stored chip: "", FAVOURITES or one folder name (no "/", no NUL - nothing
// a subfolder's name can hold); anything else reads as everything.
function pickerFilterKey(value) {
    const key = typeof value === "string" ? value : ""
    if (key === FAVOURITES) return key
    return key.length <= 255 && !/[\/\x00]/.test(key) && key !== "." && key !== ".." ? key : ""
}

function withPickerFilter(state, key) {
    const next = parseState(JSON.stringify(state))
    next.pickerFilter = pickerFilterKey(key)
    return next
}

// Whether the picker offers a chip right now; everything ("") always is.
function offersFilter(filters, key) {
    const want = String(key || "")
    return !want.length || (filters || []).some(entry => !!entry && entry.key === want)
}

// The chip the picker opens on: the remembered one while it is offered,
// everything otherwise - a folder that emptied out or went with the wallpaper
// folder is not a place to open on.
function openingFilter(remembered, filters) {
    return offersFilter(filters, remembered) ? String(remembered || "") : ""
}

// The chip once the chips have changed while the picker is open. `awaited` is
// a remembered chip the open could not show yet (at a start the folder and its
// subfolders are read in steps, after the first open): it is taken as soon as
// it is offered. Otherwise the chip shown stays while it is offered, and one
// that went (a folder emptied, renamed, or the wallpaper folder changed in
// Settings) falls back to everything rather than to an empty grid.
function filterAfterChange(current, filters, awaited) {
    const waiting = String(awaited || "")
    if (waiting.length && offersFilter(filters, waiting)) return waiting
    return offersFilter(filters, current) ? String(current || "") : ""
}

// Index after moving `delta` places in a grid of `columns`. Left and right walk
// the whole list, up and down move by a row and stop at the ends, so the
// selection never jumps to the far side. Unit tested.
function moveIndex(index, delta, count, columns) {
    if (count <= 0) return 0
    const cols = Math.max(1, columns)
    const current = Math.max(0, Math.min(count - 1, index))
    if (delta === -1 || delta === 1) return Math.max(0, Math.min(count - 1, current + delta))
    const target = current + (delta / Math.abs(delta)) * cols
    return target < 0 || target >= count ? current : target
}

// Whether the pointer over a tile selects it. Not while the grid is moving -
// a wheel glide, a fling, a drag: Qt delivers hover again on every frame
// something moves under a resting pointer, so each tile gliding past it was
// "entered", and the selection went along with the scroll. The next real
// move of the pointer selects once the grid is still.
function hoverSelects(scrolling, moving) {
    return !scrolling && !moving
}

// ---- the folder --------------------------------------------------------------
// ~/.config/user-dirs.dirs → the pictures directory, "" when it does not say
// (services/system/UserDirsLogic.js reads the file's syntax).
function picturesDir(text, home) {
    return UserDirs.userDir(text, "PICTURES", home)
}

// The folder when the setting is empty: "Desktop" inside the pictures
// directory, which is ~/Bilder on a German system - the old fixed default,
// ~/Pictures/Desktop, did not exist there.
function defaultFolder(pictures, home) {
    return (pictures || String(home || "") + "/Pictures") + "/Desktop"
}

// A local path as a file: url for FolderListModel. Each segment is encoded:
// a folder named "a#b", "x?y" or "50%2F" read as a fragment, a query or an
// escape, and the picker showed nothing. Works for a file just the same (the
// tiles' images).
function folderUrl(path) {
    const value = String(path || "")
    if (!value.length) return ""
    return "file://" + value.split("/").map(encodeURIComponent).join("/")
}

// Whether a FolderListModel lists `path`: its `folder` reads back the url it
// was given, except where Qt put it in the working directory instead - which
// it does for a folder that is empty or missing as the model is made (at a
// start, before user-dirs.dirs is read: the home directory's pictures, and a
// model for each of its folders). Compared decoded, as the model may hand the
// url back with "Ü" or a space unescaped.
function listsFolder(modelFolder, path) {
    const plain = value => value.length > 1 ? value.replace(/\/+$/, "") : value
    const want = plain(String(path || ""))
    if (!want.length) return false
    let have = ""
    try { have = decodeURIComponent(String(modelFolder || "")) } catch (error) { return false }
    return have.indexOf("file://") === 0 && plain(have.slice(7)) === want
}

// Whether a subfolder can be a group (a chip): not a hidden one, and not the
// __MACOSX a zip leaves behind, which holds only hidden "._" files.
function isGroupFolder(path) {
    const name = String(path || "").replace(/\/+$/, "").split("/").pop()
    return name.length > 0 && name.charAt(0) !== "." && name !== "__MACOSX"
}

// ---- thumbnails ----------------------------------------------------------------
// scripts/wallpaper-thumbs.py answers {"thumbs": {image: thumbnail}}. Anything
// else is null (keep what is there); an entry that is not an image path mapped
// to an absolute .jpg is dropped, since it becomes an Image url.
function parseThumbs(text) {
    let data = null
    try { data = JSON.parse(String(text || "")) } catch (error) { return null }
    const thumbs = data && data.thumbs
    if (!thumbs || typeof thumbs !== "object" || Array.isArray(thumbs)) return null
    const result = {}
    for (const path of Object.keys(thumbs)) {
        const thumb = thumbs[path]
        if (isImagePath(path) && typeof thumb === "string" && /^\/.+\.jpg$/.test(thumb)) result[path] = thumb
    }
    return result
}

// The thumbnail's url for an image, "" while it has none; encoded like
// folderUrl, because the cache lives under a home that may hold a "#".
function thumbUrl(thumbs, path) {
    const thumb = thumbs && Object.prototype.hasOwnProperty.call(thumbs, path) ? thumbs[path] : ""
    return thumb ? folderUrl(thumb) : ""
}

// ---- the picture's size and the desktop's decode ------------------------------
// The desktop decodes a wallpaper for its screen. Image's `sourceSize` with
// PreserveAspectCrop alone scales the picture to *cover* the screen and keeps
// what the crop cuts off: the 5640x2400 JPEG came out 2820x1200 on the
// 1920x1200 panel (13.5 MB instead of 9.2), 5076x2160 on a 4K screen and
// 6016x2560 on a portrait 1440x2560 one, larger than the file itself - in RAM
// and again on the GPU. Knowing the picture's own size, `sourceClipRect`
// keeps only the screen's part of the scaled picture, and a picture smaller
// than the screen is not enlarged on decode: the GPU scales it.

// {"sizes": {image: [width, height]}} from scripts/wallpaper-thumbs.py, or
// a sizes file the service kept: { image: [width, height] } for image paths
// with two whole sizes; null when it is no such map (keep what is there).
function parseSizes(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null
    const result = {}
    for (const path of Object.keys(value)) {
        const size = value[path]
        if (!isImagePath(path) || !Array.isArray(size) || size.length !== 2) continue
        const width = Number(size[0]), height = Number(size[1])
        if (Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0
                && width <= 65535 && height <= 65535)
            result[path] = [width, height]
    }
    return result
}

// The helper's answer: its "sizes", or null while it gives none (a run that
// failed, or a helper from before sizes).
function parseThumbSizes(text) {
    let data = null
    try { data = JSON.parse(String(text || "")) } catch (error) { return null }
    return data && typeof data === "object" ? parseSizes(data.sizes) : null
}

// A sizes map as the file keeps it: sorted, so the same sizes are the same
// text and an unchanged run writes nothing.
function sizesText(sizes) {
    const map = parseSizes(sizes) || {}
    const sorted = {}
    for (const path of Object.keys(map).sort()) sorted[path] = map[path]
    return JSON.stringify(sorted) + "\n"
}

// How the desktop decodes a picture of `natural` [width, height] for a screen
// of `screenWidth` x `screenHeight` pixels: { width, height } for
// `sourceSize`, `clip` (x, y, width, height in the scaled picture's pixels,
// which is what sourceClipRect means once sourceSize scales) or null, and
// what it was worked out from (`natural`, `screen`), so a later change can
// tell whether it is still right. Without a known size it is the screen's
// size, as before.
//
// Qt scales by max(sw / w, sh / h) of the size asked for and rounds (qRound),
// so asking for the picture's own cover size (sw x sh) decodes the same
// pixels as asking for the screen's - and keeps the clip inside the picture
// even when the size is wrong (a file replaced in place, until the next run
// says so): Qt then scales to at least sw x sh, and the clip lies within
// that. Asked for the screen's size with a wrong one, the clip ran past the
// picture's edge and that part came out black.
function decodeGeometry(natural, screenWidth, screenHeight) {
    const W = Math.max(0, Math.round(Number(screenWidth) || 0))
    const H = Math.max(0, Math.round(Number(screenHeight) || 0))
    const size = parseSizes({ "/x.png": natural })
    const known = size ? size["/x.png"] : null
    const plain = { width: W, height: H, clip: null, natural: null, screen: [W, H] }
    if (!known || W <= 0 || H <= 0) return plain
    const w = known[0], h = known[1]
    const ratio = Math.max(W / w, H / h)
    if (ratio < 1) {
        const scaledWidth = Math.round(w * ratio), scaledHeight = Math.round(h * ratio)
        const clipWidth = Math.min(W, scaledWidth), clipHeight = Math.min(H, scaledHeight)
        return { width: scaledWidth, height: scaledHeight, natural: [w, h], screen: [W, H],
                 clip: { x: Math.floor((scaledWidth - clipWidth) / 2), y: Math.floor((scaledHeight - clipHeight) / 2),
                         width: clipWidth, height: clipHeight } }
    }
    // Not larger than the file: the screen's shape cut from the picture as
    // it is, and scaled up where it is drawn.
    const clipWidth = Math.max(1, Math.min(w, Math.round(h * W / H)))
    const clipHeight = Math.max(1, Math.min(h, Math.round(w * H / W)))
    return { width: w, height: h, natural: [w, h], screen: [W, H],
             clip: { x: Math.floor((w - clipWidth) / 2), y: Math.floor((h - clipHeight) / 2),
                     width: clipWidth, height: clipHeight } }
}

// Whether the picture on screen, decoded as `shown`, has to be decoded again
// for `wanted` (both decodeGeometry): the screen's pixels changed, or the
// picture's size turned out to be another (a file replaced in place). A size
// that is only learnt now, for a picture decoded without one, is no reason:
// that would be a second decode at a start, for the few MB the crop saves.
function needsRedecode(shown, wanted) {
    if (!shown || !wanted) return false
    const same = (a, b) => !!a && !!b && a[0] === b[0] && a[1] === b[1]
    if (!same(shown.screen, wanted.screen)) return true
    return !!shown.natural && !!wanted.natural && !same(shown.natural, wanted.natural)
}

// ---- the displays ------------------------------------------------------------
// The "Set it on" choice: every display, then each one as Settings > Displays
// and its Identify overlay number them ("1 · eDP-1"), in that order; a screen
// without a number (0) keeps its bare name, last. `numberOf(name)` is
// DisplayService.displayNumber.
function screenChoices(names, numberOf) {
    const number = name => {
        const value = typeof numberOf === "function" ? Math.round(Number(numberOf(name))) : 0
        return isFinite(value) && value > 0 ? value : 0
    }
    const rank = screen => screen.number > 0 ? screen.number : Number.MAX_SAFE_INTEGER
    const screens = (names || []).map(name => String(name || "")).filter(name => name.length)
        .map(name => ({ name: name, number: number(name) }))
        .sort((a, b) => rank(a) - rank(b))
    return [{ value: "", label: "All displays" }].concat(screens.map(screen => ({
        value: screen.name, label: screen.number > 0 ? screen.number + " \u00b7 " + screen.name : screen.name })))
}

// "/home/a/x" → "~/x", so the setting survives a renamed home.
function contractHome(path, home) {
    const value = String(path || "")
    const base = String(home || "")
    if (base.length && value === base) return "~"
    return base.length && value.indexOf(base + "/") === 0 ? "~" + value.slice(base.length) : value
}

// The recently used folders, newest first, as the comma string
// SettingsService can store (a list would come back as {"0": ...}).
var RECENT_MAX = 5

function recentFolders(text) {
    const seen = {}
    return String(text || "").split(",").map(item => item.trim())
        .filter(item => item.length && !seen[item] && (seen[item] = true)).slice(0, RECENT_MAX)
}

function addRecentFolder(text, folder) {
    const value = String(folder || "").trim()
    if (!value.length || value.indexOf(",") >= 0) return recentFolders(text).join(",")
    return [value].concat(recentFolders(text).filter(item => item !== value)).slice(0, RECENT_MAX).join(",")
}
