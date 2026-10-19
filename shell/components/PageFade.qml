import QtQuick
import qs.theme

// Fades what a panel shows in again when its page changes while it is open:
// the control center's overview and its network page, the session menu and
// its question, Settings' pages, the start menu's Home and All apps, the
// tour's steps. The card's height glides between the two (ShellPanel), and
// the content used to swap inside it in a single frame. Full motion only, and
// only once the panel is open (`live`): the first page comes in with the
// panel's own fade.
//
//     Loader { id: pageLoader; ...
//         PageFade { target: pageLoader; key: root.page; live: root.openProgress === 1 } }
//
// The animation sets `from` as it starts, so the new page is never drawn at
// full strength first.
NumberAnimation {
    // What the page is: a fade starts whenever this changes.
    property var key
    // Off while the panel opens and closes.
    property bool live: true
    property: "opacity"
    from: 0
    to: 1
    duration: Animations.navigation
    easing.type: Animations.easingEnter
    onKeyChanged: if (live && Animations.motionEnabled && target) restart()
}
