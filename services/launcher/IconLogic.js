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
        if (name.startsWith("/")) return "file://" + name
        const found = lookup(name)
        if (found) return String(found)
    }
    return String(lookup(fallbackName) || "")
}
