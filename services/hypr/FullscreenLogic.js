.pragma library

// Is a screen actually covered by a fullscreen window?
//
// The obvious answer - the workspace's `hasfullscreen` - is wrong twice over,
// and both ways have cost this project a bug:
//
//   1. It is true for the **maximized** state as well. That is already written
//      down in HyprlandService (`fullscreenActive`), where it used to silence
//      every notification popup over a merely maximized window.
//   2. A client that releases its *own* fullscreen does not land back at
//      "nothing" - Hyprland drops it to maximized. Measured in a nested
//      session with a real Wayland `set_fullscreen(false)`, which is the path
//      a video player in a browser takes when you leave fullscreen:
//
//        before            fullscreen=0  hasfullscreen=false
//        client requests   fullscreen=2  hasfullscreen=true
//        client releases   fullscreen=1  hasfullscreen=true   <- stuck
//
//      So anything that hides behind `hasfullscreen` hides for good. That is
//      the notch not coming back after leaving a YouTube video.
//
// The window itself knows the difference, and it knows it in Wayland terms:
// the client asked to be fullscreen and then asked not to be. Hyprland's own
// record would do too - its `fullscreen` is 0 none, 1 maximized, 2 fullscreen
// - but `lastIpcObject` is only filled by an explicit `refreshToplevels` and
// is empty otherwise, which was measured the hard way: `toplevels: 1` with an
// empty record through an entire fullscreen toggle. So the Wayland state it
// is, which is the honest source anyway.

// True when one of `windows` sits on workspace `workspaceId` and is really
// fullscreen. Each window is `{ workspace, fullscreen }` - plain values, so
// this is testable without a compositor.
//
// A window whose state has not arrived yet is not fullscreen: an unknown
// state must not hide the shell, because the shell coming back is the part
// nobody notices is missing until it is.
function hasFullscreenWindow(windows, workspaceId) {
    if (workspaceId === null || workspaceId === undefined) return false
    const wanted = Number(workspaceId)
    for (const window of windows || []) {
        if (!window || window.workspace === null || window.workspace === undefined) continue
        if (Number(window.workspace) !== wanted) continue
        if (window.fullscreen === true) return true
    }
    return false
}
