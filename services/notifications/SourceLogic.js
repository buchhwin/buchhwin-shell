.pragma library

// Where a notification comes from when its app name does not say it: a
// browser. Chromium (Brave, Chrome, Chromium) sends every site's and every
// installed web app's notifications as itself - app name "Brave", the
// browser's desktop entry - so Teams and Outlook were one "Brave" group with
// one rule between them (Outlook could not be muted while Teams stayed
// urgent), and every card began with "teams.microsoft.com" because that is
// where Chromium puts the site when the server cannot take it as a hint.
// The server now takes it as one (x-kde-origin-name, which Plasma reads the
// same way), and a browser's notifications are told apart by it: grouped,
// counted and ruled per site, named and drawn as the installed web app when
// there is one. Unit tested (NotificationSourceTest).

var ORIGIN_HINT = "x-kde-origin-name"

// Senders that speak for many sites, by desktop entry or by app name (lower
// case). Anything else that sends an origin keeps its own name and only
// shows the origin beside it (a KDE app's feed item, say).
var BROWSERS = ["brave", "brave-browser", "brave-browser-stable", "brave-browser-beta", "com.brave.browser",
                "google-chrome", "google-chrome-stable", "google chrome", "chrome", "chromium", "chromium-browser",
                "org.chromium.chromium", "microsoft-edge", "microsoft-edge-stable", "microsoft edge",
                "vivaldi", "vivaldi-stable", "opera", "firefox", "org.mozilla.firefox", "librewolf"]

// The web apps this desk lives in, by every host they answer on (Microsoft
// moves them between domains), with what their installed entry is called.
// A site not listed here is told apart by its host all the same; this only
// gives the two that matter a name before anything of theirs is installed,
// and keeps Teams one group whichever of its domains a message came from.
var WEB_APPS = [
    { id: "teams", name: "Microsoft Teams", entry: /\bteams\b/i,
      hosts: ["teams.microsoft.com", "teams.cloud.microsoft", "teams.live.com"] },
    { id: "outlook", name: "Outlook", entry: /\boutlook\b/i,
      hosts: ["outlook.office.com", "outlook.office365.com", "outlook.cloud.microsoft", "outlook.live.com"] }
]

function lower(value) {
    return String(value === undefined || value === null ? "" : value).trim().toLowerCase()
}

// A hint as text, "" when the sender did not send it. Quickshell hands the
// hints the server asked for as a plain map.
function hint(notification, name) {
    const hints = notification ? notification.hints : null
    if (!hints || typeof hints !== "object") return ""
    const value = hints[name]
    return value === undefined || value === null ? "" : String(value)
}

// Whether a notification speaks for a site rather than for itself. Unit tested.
function isBrowser(notification) {
    if (!notification) return false
    const entry = lower(notification.desktopEntry).replace(/\.desktop$/, "")
    return BROWSERS.indexOf(entry) >= 0 || BROWSERS.indexOf(lower(notification.appName)) >= 0
}

// The host an origin names: "teams.microsoft.com" for "teams.microsoft.com",
// "https://Teams.Microsoft.com/v2/" or "teams.microsoft.com:443", without a
// leading "www.". "" for anything that is no host (an extension's name, a
// file path, words). Unit tested.
function originHost(text) {
    let value = lower(text)
    value = value.replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
    value = value.split(/[\/?#]/)[0]
    value = value.replace(/^[^@]*@/, "").replace(/:\d+$/, "").replace(/^www\./, "")
    if (!value.length || value.length > 253 || /[\s:@\\"'<>]/.test(value)) return ""
    // A host has a dot or is localhost; a name like "Bitwarden" is neither.
    return value.indexOf(".") > 0 || value === "localhost" ? value : ""
}

// The listed web app a host belongs to, or null: the host itself or one
// under it (eu.teams.microsoft.com). Unit tested.
function webApp(host) {
    const name = lower(host)
    if (!name.length) return null
    for (const app of WEB_APPS) {
        if (app.hosts.some(item => name === item || name.endsWith("." + item))) return app
    }
    return null
}
function webAppById(id) {
    return WEB_APPS.find(app => app.id === id) || null
}

// What a browser's notification is keyed by after the browser's own name:
// the listed web app's id, else the site's host; "" for anything that is not
// a browser's site notification. Unit tested.
function site(notification) {
    if (!isBrowser(notification)) return ""
    const host = originHost(hint(notification, ORIGIN_HINT))
    if (!host.length) return ""
    const app = webApp(host)
    return app ? app.id : host
}

// The origin another sender named, shown beside its own name; "" for a
// browser's (whose site is its name instead) and for none. Unit tested.
function originNote(notification) {
    if (!notification || isBrowser(notification)) return ""
    return originHost(hint(notification, ORIGIN_HINT))
}

// The name a site key reads as without the history to ask: "brave:teams" is
// "Microsoft Teams", "brave:github.com" is "github.com", and any other key
// the app's name with a capital, as before. Unit tested.
function nameForKey(key) {
    const text = String(key || "")
    if (text === "__system") return "System"
    const colon = text.indexOf(":")
    if (colon > 0) {
        const rest = text.slice(colon + 1)
        const app = webAppById(rest)
        return app ? app.name : rest
    }
    return text.length ? text.charAt(0).toUpperCase() + text.slice(1) : "System"
}

// What a card and a group say a notification is from: the installed web
// app's own name (`entryName`, from the caller's desktop entries), else the
// listed web app's, else the site's host; the app's name for everyone else.
// Unit tested.
function label(notification, entryName) {
    const own = String((notification && notification.appName) || "").trim()
    const key = site(notification)
    if (!key.length) return own
    if (entryName && String(entryName).trim().length) return String(entryName).trim()
    const app = webAppById(key)
    return app ? app.name : key
}

// The installed web app among desktop entries (objects with id, name,
// execString, startupClass, icon): a browser's --app-id entry whose name
// says what it is, the sending browser's own first (a Teams installed from
// Chrome as well as from Brave). null when it is not installed. Unit tested.
function findEntry(entries, app, browser) {
    if (!app) return null
    const own = lower(browser).split(/[^a-z]/)[0]
    let fallback = null
    for (const entry of entries || []) {
        if (!entry) continue
        const exec = String(entry.execString || "")
        if (exec.indexOf("--app-id=") < 0 || !app.entry.test(String(entry.name || ""))) continue
        if (!own.length || lower(exec).indexOf(own) >= 0) return entry
        if (!fallback) fallback = entry
    }
    return fallback
}

// "0x5f3a..." for a window's address as Quickshell hands it (no 0x), "" for
// anything else.
function windowAddress(value) {
    const text = lower(value).replace(/^0x/, "")
    return /^[0-9a-f]+$/.test(text) ? "0x" + text : ""
}

// The address of a web app's window among `windows` ({ address, appId }):
// Wayland names a Chromium web app after its entry (brave-<id>-Default),
// XWayland after its StartupWMClass (crx_<id>). "" when none is open. Unit
// tested.
function windowFor(windows, entry) {
    if (!entry) return ""
    const names = [lower(entry.id).replace(/\.desktop$/, ""), lower(entry.startupClass)].filter(name => name.length)
    for (const window of windows || []) {
        if (window && names.indexOf(lower(window.appId)) >= 0) {
            const address = windowAddress(window.address)
            if (address.length) return address
        }
    }
    return ""
}

// The stored rules after the one-time split of a browser's rule (version 2):
// a "brave" rule from before applied to Teams and Outlook alike, so each of
// the two takes it over unless it has one of its own. The browser's own rule
// stays, for what it sends without a site; any other site starts without a
// rule (NotificationLogic.ruleFor goes by the site's key alone). `version` is
// the stored one; the result says which it is now. The same object when
// nothing changes. Unit tested.
var RULES_VERSION = 2
function migrateRules(rules, version) {
    const stored = rules || {}
    if (Number(version) >= RULES_VERSION) return { rules: stored, version: Number(version) }
    let next = stored
    for (const key of Object.keys(stored)) {
        if (key.indexOf(":") >= 0 || BROWSERS.indexOf(key) < 0) continue
        for (const app of WEB_APPS) {
            const split = key + ":" + app.id
            if (next[split] !== undefined) continue
            if (next === stored) next = Object.assign({}, stored)
            next[split] = stored[key]
        }
    }
    return { rules: next, version: RULES_VERSION }
}
