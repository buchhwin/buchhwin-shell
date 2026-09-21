import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/WebSearch.js" as W

// Web search and "open this address" for the launcher. No process, no network:
// what is tested is which address a query turns into.
ShellRoot {
    Component.onCompleted: {
        T.eq(W.engines.map(entry => entry.value),
             ["duckduckgo", "google", "startpage", "wikipedia", "custom"], "the engines offered")
        T.ok(W.engines.every(entry => entry.value === "custom" || entry.url.indexOf("%s") > 0),
             "every engine but the custom one has a place for the query")

        T.eq(W.searchUrl("cats", "duckduckgo", ""), "https://duckduckgo.com/?q=cats", "a plain query")
        T.eq(W.searchUrl("a b", "google", ""), "https://www.google.com/search?q=a%20b", "a space is encoded")
        T.eq(W.searchUrl("c++ & rust", "duckduckgo", ""), "https://duckduckgo.com/?q=c%2B%2B%20%26%20rust",
             "characters that would end the query are encoded")
        T.eq(W.searchUrl("  ", "duckduckgo", ""), "", "nothing to search for")
        T.eq(W.searchUrl("x", "unknown", ""), "https://duckduckgo.com/?q=x", "an unknown engine falls back to the first")

        T.eq(W.searchUrl("x", "custom", "https://s.example/?q=%s"), "https://s.example/?q=x", "a custom engine")
        T.eq(W.searchUrl("x", "custom", ""), "", "a custom engine without an address searches nothing")
        T.eq(W.searchUrl("x", "custom", "https://s.example/"), "", "…and neither does one without %s")
        T.eq(W.searchUrl("x", "custom", "file:///etc/passwd?q=%s"), "", "only http and https are opened")
        T.eq(W.searchUrl("x", "custom", "javascript:alert(1)%s"), "", "a script address is refused")

        T.eq(W.customError(""), "", "an empty address is not an error yet")
        T.ok(W.customError("example.org/?q=%s").length > 0, "an address without a scheme is refused")
        T.ok(W.customError("https://example.org/").length > 0, "an address without %s is refused")
        T.eq(W.customError("https://example.org/?q=%s"), "", "a usable address")

        // What counts as an address
        T.eq(["example.org", "example.org/path", "sub.example.org:8080/a?b=c", "https://example.org",
              "http://example.org/x"].map(W.looksLikeAddress), [true, true, true, true, true], "addresses")
        T.eq(["cats", "how to cook", "localhost", "1", "ftp://example.org", "a b.org",
              ""].map(W.looksLikeAddress), [false, false, false, false, false, false, false], "not addresses")
        T.eq(W.addressUrl("example.org"), "https://example.org", "a bare host gets https")
        T.eq(W.addressUrl("http://example.org"), "http://example.org", "an explicit scheme is kept")
        T.eq(W.addressUrl("cats"), "", "a word is not an address")

        T.eq(W.hostOf("https://sub.example.org/a/b"), "sub.example.org", "the host of an address")
        T.eq(W.hostOf("nonsense"), "", "no host")
        T.eq(W.engineLabel("google", ""), "Google", "the engine's name")
        T.eq(W.engineLabel("custom", "https://s.example/?q=%s"), "s.example", "a custom engine is named by its host")
        T.eq(W.engineLabel("custom", ""), "Custom", "…and “Custom” while it has none")

        T.finish("WebSearchTest")
    }
}
