.pragma library

// Web search and "open this address" for the launcher.
//
// The search engines are a fixed list plus one the user writes themselves;
// `%s` in a template is the query, URL-encoded. Nothing here runs a process or
// reaches the network: the launcher hands the address to the session's default
// browser, the same way every other link in the shell does.

var engines = [
    { value: "duckduckgo", label: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s" },
    { value: "google", label: "Google", url: "https://www.google.com/search?q=%s" },
    { value: "startpage", label: "Startpage", url: "https://www.startpage.com/sp/search?query=%s" },
    { value: "wikipedia", label: "Wikipedia", url: "https://en.wikipedia.org/w/index.php?search=%s" },
    { value: "custom", label: "Custom …", url: "" }
]

function engine(value) {
    return engines.find(entry => entry.value === String(value || "")) || engines[0]
}

function engineLabel(value, custom) {
    const found = engine(value)
    if (found.value !== "custom") return found.label
    const host = hostOf(custom)
    return host.length ? host : "Custom"
}

// The address a query goes to, or "" when there is nothing to search for.
function searchUrl(query, engineValue, custom) {
    const text = String(query || "").trim()
    if (!text.length) return ""
    const found = engine(engineValue)
    const template = found.value === "custom" ? String(custom || "").trim() : found.url
    if (!template.length || template.indexOf("%s") < 0) return ""
    if (!/^https?:\/\//i.test(template)) return ""
    return template.replace("%s", encodeURIComponent(text))
}

// A custom template is only usable when it is an http(s) address with a %s in
// it; the settings page says so rather than failing silently later.
function customError(template) {
    const text = String(template || "").trim()
    if (!text.length) return ""
    if (!/^https?:\/\//i.test(text)) return "The address has to start with http:// or https://"
    if (text.indexOf("%s") < 0) return "Put %s where the search term belongs"
    return ""
}

// Hosts without a dot (localhost, a machine name) are not guessed at: only
// what is unmistakably an address is offered as one.
var ADDRESS = /^(https?:\/\/\S+|[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?(\/\S*)?)$/i
var SCHEME = /^[a-z][a-z0-9+.-]*:\/\//i

function looksLikeAddress(text) {
    const value = String(text || "").trim()
    if (!value.length || /\s/.test(value)) return false
    if (SCHEME.test(value)) return /^https?:\/\//i.test(value)
    return ADDRESS.test(value)
}

// The address to open for something that looks like one.
function addressUrl(text) {
    const value = String(text || "").trim()
    if (!looksLikeAddress(value)) return ""
    return SCHEME.test(value) ? value : "https://" + value
}

function hostOf(url) {
    const match = /^https?:\/\/([^/?#]+)/i.exec(String(url || "").trim())
    return match ? match[1] : ""
}
