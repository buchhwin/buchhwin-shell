import qs.services
import qs.shell.components

// The name the settings pages use for the shared CardSection. Kept so the
// pages do not have to change; new code outside settings uses CardSection.
CardSection {
    id: section
    // A setting path of this section, whose scope is said in the title's "i"
    // after the section's own hint: the mode's own ("Kept for this mode
    // (Docked)"), or the same in every profile. It used to be a line of its
    // own under the description, and with the descriptions it made the pages a
    // wall of small print. Empty, or a setting of the profile, says nothing.
    property string scope: ""
    hintNote: !section.scope.length ? "" : LayoutService.scopeNote(section.scope)
}
