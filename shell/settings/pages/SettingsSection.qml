import qs.shell.components

// The name the settings pages use for the shared CardSection. Kept so the
// pages do not have to change; new code outside settings uses CardSection.
CardSection {
    id: section
    // A setting path of this section, whose scope is said under its
    // description: the mode's own, or the same in every profile (ScopeNote).
    // Empty, or a setting of the profile, says nothing.
    property string scope: ""

    ScopeNote { path: section.scope }
}
