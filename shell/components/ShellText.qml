import QtQuick
import qs.theme

// Text with theme defaults. role: body, caption, small, label (upper-case
// section label), title, headline, pageTitle, display.
Text {
    property string role: "body"
    property bool muted: false

    color: muted || role === "caption" || role === "label" ? Colors.mutedText : Colors.text
    font.family: Typography.family
    font.pixelSize: role === "caption" || role === "label" ? Typography.captionSize
        : role === "small" ? Typography.smallSize
        : role === "bodyLarge" ? Typography.bodyLargeSize
        : role === "title" ? Typography.titleSize
        : role === "headline" ? Typography.headlineSize
        : role === "pageTitle" ? Typography.pageTitleSize
        : role === "display" ? Typography.displaySize
        : Typography.bodySize
    // A card's title in medium: at regular a list's name ("Networks",
    // "Output") was the rows' own text a few pixels bigger and read as one
    // more row. Headlines stay regular; they lead on size alone.
    font.weight: role === "headline" || role === "pageTitle" ? Typography.regular
        : role === "display" ? Typography.light
        : role === "title" || role === "label" ? Typography.medium
        : Typography.regular
    font.letterSpacing: role === "label" ? Typography.captionTracking : 0
    font.capitalization: role === "label" ? Font.AllUppercase : Font.MixedCase
    elide: Text.ElideRight
    textFormat: Text.PlainText
    renderType: Typography.renderType
}
