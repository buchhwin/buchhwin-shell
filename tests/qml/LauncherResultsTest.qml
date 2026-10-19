import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/ResultsLogic.js" as R

// The launcher's result rows: the order of the apps mode, and the keys the
// rows are kept by. The list used to be a plain array for the ListView, and
// every keystroke built every row again; keyed, a result that is still there
// keeps its row - which only works if its key stays the same while the
// query grows around it.
ShellRoot {
    function app(id, title) { return { kind: "app", title: title, appId: id } }

    Component.onCompleted: {
        // ---- the apps mode's order ---------------------------------------------
        const calc = { kind: "calculator", key: "calculator", title: "4" }
        const address = { kind: "web", key: "web:open", title: "Open readme.md" }
        const apps = [app("ghostwriter", "ghostwriter"), app("kate", "Kate"), app("okular", "Okular")]
        const commands = [{ kind: "command", key: "command:Settings", title: "Settings" }]
        T.eq(R.appsMode([], address, false, apps, commands).map(R.keyOf),
             ["app:ghostwriter", "web:open", "command:Settings", "app:kate", "app:okular"],
             "a bare host comes after the best app, so Enter starts the app")
        T.eq(R.appsMode([], address, true, apps, commands).map(R.keyOf),
             ["web:open", "app:ghostwriter", "command:Settings", "app:kate", "app:okular"],
             "an address beyond doubt still comes first")
        T.eq(R.appsMode([], address, false, [], []).map(R.keyOf), ["web:open"],
             "with no app to match, the address is all there is")
        T.eq(R.appsMode([calc], null, false, apps.slice(0, 1), []).map(R.keyOf), ["calculator", "app:ghostwriter"],
             "the calculator's answer leads, no address")
        T.eq(R.appsMode([calc], address, true, apps.slice(0, 1), []).map(R.keyOf),
             ["calculator", "web:open", "app:ghostwriter"], "and a leading address comes after it")

        // ---- keys --------------------------------------------------------------
        T.eq(R.keyOf(app("org.kde.kate", "Kate")), "app:org.kde.kate", "an app by its id")
        T.eq(R.keyOf({ kind: "file", key: "file:/home/sample/a.txt", title: "a.txt" }), "file:/home/sample/a.txt",
             "the provider's key first")
        T.eq(R.keyOf({ kind: "settings", title: "Wallpaper" }), "settings:Wallpaper", "else kind and title")
        T.eq([R.keyOf(null), R.keyOf("x")], ["", ""], "nothing to key")

        const twice = R.keyed([{ kind: "file", title: "a.txt" }, { kind: "file", title: "a.txt" }, app("kate", "Kate")])
        T.eq(twice.keys, ["file:a.txt", "file:a.txt#1", "app:kate"], "a key that comes twice is counted")
        T.eq(Object.keys(twice.byKey).length, 3, "and every row is in the table")
        T.eq(twice.byKey["app:kate"].title, "Kate", "the table hands back the result itself")

        // Typing on: "k" → "ka" → "kat". The rows that stay keep their keys,
        // the calculator and the web rows keep theirs while their titles move.
        const first = R.keyed([app("kate", "Kate"), app("konsole", "Konsole"), app("okular", "Okular"),
                               { kind: "web", key: "web:search", title: "Search for “k”" }])
        const second = R.keyed([app("kate", "Kate"), app("kalgebra", "KAlgebra"),
                                { kind: "web", key: "web:search", title: "Search for “ka”" }])
        T.eq(second.keys.filter(key => first.keys.indexOf(key) >= 0), ["app:kate", "web:search"],
             "what is still there keeps its key")
        T.eq(second.byKey["web:search"].title, "Search for “ka”", "and shows the new result")
        T.eq(R.keyed(undefined), { keys: [], byKey: {} }, "no results")

        T.finish("LauncherResultsTest")
    }
}
