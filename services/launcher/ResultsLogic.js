.pragma library

// The launcher's result list: the order of the apps mode, and the key each
// row is known by from one keystroke to the next.

// The apps mode mixes everything: a sum's answer, an address, the apps and a
// few commands. `lead` is what goes before everything (the calculator's row),
// `addressLeads` whether the typed address is one beyond doubt.
//
// A typed address used to come before every app, on the reasoning that
// nothing else can be meant by "example.org/page" - but "readme.md",
// "notes.py" and "photo.jpg" are addresses by that measure too, and Enter
// opened a browser tab on https://readme.md. A bare host now comes after the
// best app, so the app is what Enter starts; with a scheme, a port or a path
// it is still first. With no app to match, it leads either way.
//
// `extras` are the few rows of the other sources a query reaches - open
// windows, VS Code's folders, recent files, each already cut to its handful:
// after the commands and before the rest of the apps, so the best app stays
// what Enter starts and the long tail of apps does not bury them.
function appsMode(lead, address, addressLeads, apps, commands, extras) {
    const head = (lead || []).slice()
    if (address && addressLeads) head.push(address)
    const list = apps || []
    return head.concat(list.slice(0, 1), address && !addressLeads ? [address] : [],
                       commands || [], extras || [], list.slice(1))
}

// What a row is, not where it stands: an app by its id, anything else by the
// key its provider gave it (the calculator's one row, "web:open", a file by
// its path) or else by its kind and title.
function keyOf(result) {
    if (!result || typeof result !== "object") return ""
    if (result.key !== undefined && String(result.key).length) return String(result.key)
    if (result.appId !== undefined && String(result.appId).length) return "app:" + result.appId
    return String(result.kind || "") + ":" + String(result.title || "")
}

// → { keys, byKey }. The launcher's list runs on the keys: plain strings,
// which Quickshell's ScriptModel compares by value (pitfall 76), so a row
// whose result is still there after a keystroke is kept and shows the new
// result in place, where every row of the list used to be built again
// (~170 objects per key). A key that comes twice gets a count after it, so
// every row has one of its own.
function keyed(results) {
    const keys = []
    const byKey = {}
    const seen = {}
    for (const result of results || []) {
        const base = keyOf(result)
        const count = seen[base] || 0
        seen[base] = count + 1
        const key = count ? base + "#" + count : base
        keys.push(key)
        byKey[key] = result
    }
    return { keys: keys, byKey: byKey }
}
