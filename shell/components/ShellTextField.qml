import QtQuick
import QtQuick.Layouts
import qs.theme

// One UI input: a filled capsule with an icon, placeholder and optional busy
// indicator. Focus shows the focus ring every other control shows.
Rectangle {
    id: root
    property alias text: input.text
    // Typed into since the last Return: a value the field has not handed on
    // yet. Settings keeps a page loaded while one of its fields says so.
    property bool edited: false
    // What Escape goes back to while the field has the focus: the text it
    // had when it got it, or when Return last handed it on. A search field
    // gets the focus empty, so Escape still clears it; a settings field gets
    // its stored value back. Escape used to clear every field, and a field
    // that writes as it changes (the custom search address) or as it loses
    // the focus (the recordings folder) stored the empty text.
    property string savedText: ""
    objectName: "shellTextField"
    property alias echoMode: input.echoMode
    readonly property alias inputActiveFocus: input.activeFocus
    property string icon: ""
    property string placeholder: ""
    property bool busy: false
    // Tab / Shift+Tab move between fields that opt in (forms).
    property bool focusOnTab: false
    property bool selectAllOnFocus: false
    // The hero field of a panel (the launcher): taller, card-shaped and set in
    // the title size, but the same material as every other field.
    property bool large: false
    // Whether keyboard focus draws the accent outline. Off for a field that
    // is the only input on its surface and holds the focus for as long as the
    // surface is open (the launcher): an outline that never goes away marks
    // nothing and reads as a stuck border. The fill still lightens on focus.
    property bool focusOutline: true
    // What is typed is not a value the field can take (a date that is not
    // one): a danger outline, and focus still draws the ring every field
    // draws. The forms used to set the border by hand, each with its own
    // copy of the focus colours and a grey outline no other field has.
    property bool error: false
    // Dimmed, and then it takes neither the focus nor a key nor a click, like
    // ShellButton's and ShellToggle's `enabledState`.
    property bool enabledState: true
    property string accessibleName: ""
    signal accepted()
    signal escapePressed()
    // Delete with an empty field (TextInput would swallow the key otherwise).
    signal deleteOnEmpty()
    // First refusal on every key, before the field itself handles it. A panel
    // that drives a list from its search field (the launcher) needs Return and
    // the arrows before TextInput takes them.
    signal keyPressed(var event)

    // Back to `savedText`; false when the text is there already, and the
    // Escape is then the owner's.
    function revert() {
        if (input.text === root.savedText) return false
        input.text = root.savedText
        root.edited = false
        return true
    }

    // Focus a panel hands the field as it opens is quiet: no ring (below).
    property bool quietFocus: false
    function focusInput(reason) {
        // Or the quiet flag outlived a focus that never came, and the next
        // Tab into the field drew no ring.
        if (!root.enabledState) return
        quietFocus = reason === undefined
        input.forceActiveFocus(reason === undefined ? Qt.OtherFocusReason : reason)
    }

    implicitHeight: large ? Metrics.controlHeight + Metrics.spaceLg : Metrics.controlHeight
    radius: large ? Metrics.radiusCard : Metrics.pillRadius(height)
    color: input.activeFocus ? Colors.controlFillHover : Colors.controlFill
    opacity: enabledState ? 1 : Effects.disabledOpacity
    border.width: Metrics.borderWidth
    border.color: error ? Colors.danger : large ? Colors.border : "transparent"
    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }

    // Not for the focus a panel hands its search field as it opens: the field
    // holds it all along, and a ring there marks nothing (it was reported as
    // a stuck border on the launcher). Tabbed or clicked into, it shows.
    FocusRing { active: input.activeFocus && root.focusOutline && !root.quietFocus; controlRadius: root.radius }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Metrics.spaceLg
        anchors.rightMargin: Metrics.spaceLg
        spacing: Metrics.spaceSm
        ShellIcon {
            visible: root.icon.length > 0
            glyph: root.icon
            size: root.large ? Metrics.iconMd : Metrics.iconSm
            color: root.large ? Colors.accentForeground : Colors.mutedText
        }
        TextInput {
            id: input
            Layout.fillWidth: true
            color: Colors.text
            selectionColor: Colors.accentSoft
            font.family: Typography.family
            font.pixelSize: root.large ? Typography.titleSize : Typography.bodySize
            selectedTextColor: Colors.text
            clip: true
            // A disabled item gives up the focus and is given none: no key,
            // no click, no caret.
            enabled: root.enabledState
            activeFocusOnTab: root.focusOnTab
            // The field is named by its row (SettingRow), by the caller, or
            // by what its placeholder asks for.
            Accessible.role: Accessible.EditableText
            Accessible.name: root.accessibleName || root.placeholder
            onActiveFocusChanged: {
                if (!activeFocus) {
                    root.quietFocus = false
                    // Escape only comes with the focus, so the copy goes with
                    // it: the field may hold a passphrase, and the dialogs that
                    // empty theirs as they close (drive unlock, Wi-Fi) would
                    // otherwise leave it here.
                    root.savedText = ""
                    return
                }
                root.savedText = text
                if (root.selectAllOnFocus) selectAll()
            }
            onAccepted: {
                // Taken first: the owner's handler can close the panel and
                // the field with it (pitfall 20).
                const field = root
                field.edited = false
                field.accepted()
                // After the handler, which may have emptied the field for the
                // next entry (Add shortcut): Escape keeps what is there now.
                // Not when the handler took the focus away (above).
                if (field && field.inputActiveFocus) field.savedText = field.text
            }
            onTextEdited: root.edited = true
            Keys.onPressed: event => root.keyPressed(event)
            Keys.onDeletePressed: event => {
                if (text.length) { event.accepted = false; return }
                root.deleteOnEmpty()
            }
            // Escape puts back what was there (savedText); only an Escape
            // with nothing to put back is the field's owner's, and goes on.
            // Both used to happen in one press, so a dialog that closes "when
            // the field is empty" closed on the draft it had just cleared.
            Keys.onEscapePressed: event => {
                if (root.revert()) return
                event.accepted = false
                root.escapePressed()
            }
            ShellText {
                visible: parent.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                // The size of what is typed in its place, or the text grew
                // on the first keystroke (the emoji field: 15 px, then 17).
                font.pixelSize: input.font.pixelSize
                // Read like text (4.5:1); subtleText is for marks, not words.
                color: Colors.mutedText
            }
        }
        ShellIcon {
            visible: root.busy
            glyph: Icons.refresh
            size: Metrics.iconSm
            color: Colors.mutedText
            RotationAnimation on rotation {
                running: root.busy && root.visible && Animations.motionEnabled
                from: 0
                to: 360
                loops: Animation.Infinite
                duration: Animations.spinner
            }
        }
    }
}
