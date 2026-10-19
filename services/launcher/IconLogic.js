.pragma library

// Image source for app icons (desktop entries, windows). `lookup(name)` returns
// the theme icon URL or "" when the icon theme lacks the name
// (Quickshell.iconPath(name, true)). Checking before loading avoids the icon
// provider warning "Could not load icon NAME?fallback=…", which appears when
// neither the icon nor its fallback exists in the searched themes, e.g. for a
// shell started without QT_QPA_PLATFORMTHEME=kde (only hicolor is searched).

var fallbackName = "application-x-executable"

// names: one name or candidates in order; absolute paths (Icon=/…) load as files.
// Returns "" when nothing, not even the generic icon, is available.
function source(names, lookup) {
    const candidates = Array.isArray(names) ? names : [names]
    for (const raw of candidates) {
        const name = String(raw || "").trim()
        if (!name.length) continue
        // Encoded as WallpaperLogic.folderUrl does: a "#" or "?" in a path
        // would end the file name in a url.
        if (name.startsWith("/")) return "file://" + name.split("/").map(encodeURIComponent).join("/")
        const found = lookup(name)
        if (found) return String(found)
    }
    return String(lookup(fallbackName) || "")
}

// The names worth looking up ahead (LauncherService's idle warm-up): every
// app's icon names once, in order, without the absolute paths (a file is no
// lookup) and without the ones in `done`. The generic icon goes first: every
// app whose icon is missing ends there.
function pending(names, done) {
    const asked = done || {}
    const seen = {}
    const out = []
    const add = raw => {
        const name = String(raw || "").trim()
        if (!name.length || name.startsWith("/") || seen[name] || asked[name]) return
        seen[name] = true
        out.push(name)
    }
    add(fallbackName)
    for (const entry of names || []) {
        if (Array.isArray(entry)) entry.forEach(add)
        else add(entry)
    }
    return out
}
