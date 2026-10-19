import QtQuick
import QtQuick.Layouts
import qs.services
import qs.shell.components
import "../../../services/settings/ScopeLogic.js" as Scope
import "../../../services/profile/ProfileLogic.js" as Profile

// One line that says where the setting at `path` is kept: "Kept for this mode
// (Docked)" or "The same in every profile". A setting that belongs to the
// profile, as most do, says nothing, and the line takes no room. A blur set in
// Docked was gone in Laptop and a lid action set in one profile was there in
// the other, with nothing on the page to say why. SettingsSection shows one
// under its description (`scope`); a page can put one beside a single
// control too.
ShellText {
    id: root
    property string path: ""
    Layout.fillWidth: true
    // LayoutService only for a setting a mode owns: the others need no name.
    text: !root.path.length ? ""
        : Scope.note(root.path, Profile.isModeScoped(root.path)
            ? Profile.label(LayoutService.activeMode, LayoutService.templates) : "")
    visible: text.length > 0
    role: "caption"
    wrapMode: Text.Wrap
}
