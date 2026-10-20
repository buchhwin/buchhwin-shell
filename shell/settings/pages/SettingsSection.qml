import qs.services
import qs.shell.components
import "../../../services/settings/ScopeLogic.js" as Scope
import "../../../services/profile/ProfileLogic.js" as Profile

// The name the settings pages use for the shared CardSection. Kept so the
// pages do not have to change; new code outside settings uses CardSection.
CardSection {
    id: section
    // A setting path of this section, whose scope is said in the title's "i"
    // after the section's own hint: the mode's own ("Kept for this mode
    // (Docked)"), or the same in every profile. It used to be a line of its
    // own under the description, and with the descriptions it made the pages a
    // wall of small print. Empty, or a setting of the profile, says nothing.
    // LayoutService only for a setting a mode owns: the others need no name.
    property string scope: ""
    hintNote: !section.scope.length ? ""
        : Scope.note(section.scope, Profile.isModeScoped(section.scope)
            ? Profile.label(LayoutService.activeMode, LayoutService.templates) : "")
}
