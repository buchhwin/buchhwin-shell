.pragma library

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
// empty list, which is what a new key should do.
// "folder" is the fourth, and the reason subfolders exist at all: a rotation
// that stays inside one group rather than wandering through everything.
var SOURCES = ["all", "favourites", "chosen", "folder"]

function source(value) {
    return SOURCES.indexOf(value) >= 0 ? value : "all"
}

// settings.json: `wallpaper.favouritesOnly` became `wallpaper.slideshowSource`
// with three values instead of two. Run on the document as it is read, the way
// the power settings' own migration is, so nothing depends on a write landing
// first. A document that already has the new key is left alone.
function migrate(document) {
    if (!document || typeof document !== "object") return document
    const wallpaper = document.wallpaper
    if (!wallpaper || typeof wallpaper !== "object") return document
    if (wallpaper.favouritesOnly === undefined) return document
    const next = {}
    for (const key of Object.keys(wallpaper))
        if (key !== "favouritesOnly") next[key] = wallpaper[key]
    if (next.slideshowSource === undefined)
        next.slideshowSource = wallpaper.favouritesOnly === true ? "favourites" : "all"
    const result = Object.assign({}, document)
    result.wallpaper = next
    return result
}

function emptyState() {
    return { version: 1, screens: {}, favourites: [], slideshow: [] }
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

// Wallpaper for one screen: its own choice if the file is still available.
function pathFor(state, screen, fallback, available) {
    const own = state.screens[screen]
    return own && (!available || available.indexOf(own) >= 0) ? own : fallback
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

// Basename without the extension, for the picker's labels and its filter.
function displayName(path) {
    const file = String(path || "").split("/").pop()
    return file.replace(/\.(png|jpe?g|webp)$/i, "")
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
        if (needle.length && displayName(path).toLowerCase().indexOf(needle) < 0) return false
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
    if ((favourites || []).length) result.push({ key: FAVOURITES, label: "Favourites" })
    for (const name of groups(images, folder)) result.push({ key: name, label: name })
    return result
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
