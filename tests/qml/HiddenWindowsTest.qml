import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/hypr/HiddenWindows.js" as H

ShellRoot {
    Component.onCompleted: {
        T.ok(H.classes.indexOf("xwaylandvideobridge") >= 0, "xwaylandvideobridge is hidden")
        T.eq(H.workspace, "special:buchhwin-hidden", "hidden special workspace")
        T.eq([H.isHiddenClass("xwaylandvideobridge"), H.isHiddenClass("XWaylandVideoBridge"), H.isHiddenClass("kitty"), H.isHiddenClass(""), H.isHiddenClass(null)],
             [true, true, false, false, false], "class matching is exact and case-insensitive")
        T.eq(H.isHiddenClient({ class: "xwaylandvideobridge", workspace: { id: 1, name: "1" } }), true, "hidden by class")
        T.eq(H.isHiddenClient({ class: "", initialClass: "xwaylandvideobridge" }), true, "hidden by initial class")
        T.eq(H.isHiddenClient({ class: "kitty", workspace: { id: -99, name: "special:buchhwin-hidden" } }), true, "hidden by workspace")
        T.eq(H.isHiddenClient({ class: "kitty", workspace: { id: -98, name: "special:scratch" } }), false, "other special workspaces stay")
        T.eq(H.isHiddenClient(null), false, "missing client")
        T.eq(H.visibleCount([{ appId: "kitty", ipcClass: "" }, { appId: "xwaylandvideobridge", ipcClass: "" }, { appId: "", ipcClass: "xwaylandvideobridge" }]), 1, "workspace window count")
        T.eq(H.visibleCount(null), 0, "no windows")
        T.finish("HiddenWindowsTest")
    }
}
