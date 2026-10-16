import QtQuick
import qs.shell.components
import "../../../services/settings/SettingsFieldLogic.js" as Fields

// A settings field for one stored value. It shows the value as stored
// whenever it is not being typed into, and hands a value on with Return or
// by leaving the field - not with every keystroke: the custom search address
// was written to settings.json, and was in effect, one character at a time.
//
// Escape puts back what the field had (ShellTextField), and nothing empties
// the setting on the way out: a field left empty gets the stored value back
// rather than storing nothing. One Escape used to erase the custom search
// address, and Escape then a click elsewhere the recording folder. Return on
// an empty field is the way to store "" where that means something (the
// default folder).
//
// `storedText` is also what SettingsPanel compares a draft against
// (SettingsFieldLogic.holdsDraft): text equal to it keeps no page loaded.
ShellTextField {
    id: field
    property string storedText: ""
    // The page checks and stores the value, or refuses it and says why; the
    // field then shows what was stored, which may be tidier than what was
    // typed (trimmed, a short hex written out).
    signal commit(string value)

    Component.onCompleted: text = storedText
    onStoredTextChanged: if (!inputActiveFocus || !edited) text = storedText
    onAccepted: settle(text)
    onInputActiveFocusChanged: if (!inputActiveFocus) leave()

    // The focus went: Escape (ShellTextField puts the text the field had
    // back), Tab, a click elsewhere, the panel closing.
    function leave() {
        const action = Fields.leaveAction(field.text, field.storedText)
        if (action === "restore") {
            field.text = field.storedText
            field.edited = false
        } else if (action === "commit") {
            field.settle(field.text)
        } else {
            field.edited = false
        }
    }

    function settle(value) {
        field.commit(value)
        // Taken: nothing is left to keep. Refused: the text stays, marked by
        // the page. Left with Tab or a click it still counts as a draft until
        // it is fixed or emptied; after Return it does not, because
        // ShellTextField clears `edited` before the page sees the value.
        if (field.text === field.storedText) field.edited = false
    }
}
