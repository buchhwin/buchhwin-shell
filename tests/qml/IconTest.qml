import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/IconLogic.js" as I

ShellRoot {
    Component.onCompleted: {
        const theme = ["kitty", "application-x-executable"]
        const lookup = name => theme.indexOf(name) >= 0 ? "image://icon/" + name : ""
        T.eq(I.source("kitty", lookup), "image://icon/kitty", "available icon")
        T.eq(I.source("hwinfo", lookup), "image://icon/application-x-executable", "missing icon uses the generic icon")
        T.eq(I.source(["", null, "hwinfo", "kitty"], lookup), "image://icon/kitty", "first available candidate")
        T.eq(I.source(["/opt/app/icon.png", "kitty"], lookup), "file:///opt/app/icon.png", "absolute paths load as files")
        T.eq(I.source("/opt/a #1/icon?.png", lookup), "file:///opt/a%20%231/icon%3F.png", "an absolute path is encoded")
        T.eq(I.source(undefined, lookup), "image://icon/application-x-executable", "no name")
        T.eq(I.source("hwinfo", name => ""), "", "nothing available")
        const asked = []
        I.source(["kitty", "other"], name => { asked.push(name); return "image://icon/" + name })
        T.eq(asked, ["kitty"], "stops at the first hit")
        // The names looked up ahead of the first launcher open.
        T.eq(I.pending(["kitty", "/opt/app/icon.png", "", null, "kitty", ["firefox", "web"]], {}),
             ["application-x-executable", "kitty", "firefox", "web"],
             "each name once, the generic icon first, no file paths")
        T.eq(I.pending(["kitty", "firefox"], { "application-x-executable": true, kitty: true }), ["firefox"],
             "names already asked are not asked again")
        T.eq(I.pending(undefined, undefined), ["application-x-executable"], "no apps: the generic icon")
        T.finish("IconTest")
    }
}
