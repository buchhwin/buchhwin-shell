import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dashboard/NotesLogic.js" as Logic

// The dashboard's notes: one plain text file in the state directory
// (notes.txt, the user's alone), saved a moment after the typing stops and at
// once when the dashboard closes. Read on the first open of a dashboard that
// carries it - not as the card is built with the dashboard at the start - and
// again on every open, so a note changed in an editor meanwhile is the one
// shown (unless the card still holds typing of its own, which is newer).
// NotesLogic has the rules.
CardSection {
    id: root
    // Whether the dashboard is open.
    property bool active: false
    property string fitClass: "small"
    // The cell's height, from the item that fills it: the note takes what
    // the title leaves, and scrolls inside that.
    property real cellHeight: 0
    // What the file held at the last read or write, newline and all.
    property string savedText: ""
    property bool read: false
    // A file that is there and cannot be read is not written over.
    property bool unreadable: false

    padding: Metrics.spaceLg

    function save() {
        saveTimer.stop()
        if (unreadable || !Logic.needsSave(area.text, savedText, read)) return
        savedText = Logic.toFile(area.text)
        file.setText(savedText)
    }

    // The first open reads the file by switching `preload` on (a FileView
    // that never read does nothing on reload(), pitfall 34); later ones read
    // it again unless there is typing to save.
    function load() {
        if (unreadable) return
        if (!read) file.preload = true
        else if (!Logic.needsSave(area.text, savedText, read)) file.reload()
    }
    onActiveChanged: {
        if (!active) save()
        else load()
    }
    // Added while the dashboard is open.
    Component.onCompleted: if (active) load()
    // A card taken off the dashboard keeps what was typed into it.
    Component.onDestruction: save()

    FileView {
        id: file
        path: Paths.stateDir + "/notes.txt"
        preload: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const text = file.text()
            if (Logic.takesRead(area.text, root.savedText, root.read)) {
                root.savedText = text
                if (area.text !== Logic.fromFile(text)) area.text = Logic.fromFile(text)
            }
            root.read = true
        }
        // Not there yet is an empty note; anything else is a file that is
        // there and is left alone (pitfall 132).
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.read = true
            else root.unreadable = true
        }
        onSaved: Quickshell.execDetached(["chmod", "600", "--", file.path])
    }
    Timer { id: saveTimer; interval: Logic.SAVE_DELAY_MS; onTriggered: root.save() }

    ShellText {
        id: heading
        Layout.fillWidth: true
        visible: root.fitClass !== "icon"
        text: "Notes"
        role: "title"
    }

    Flickable {
        id: view
        Layout.fillWidth: true
        // The rest of the cell, so a click anywhere below the last line
        // still lands in the note.
        Layout.preferredHeight: Math.max(Typography.bodySize * 2,
            root.cellHeight - root.padding * 2 - (heading.visible ? heading.implicitHeight + root.spacing : 0))
        contentWidth: width
        contentHeight: area.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollFeel { view: view }

        TextEdit {
            id: area
            width: view.width
            height: Math.max(implicitHeight, view.height)
            enabled: root.read && !root.unreadable
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            persistentSelection: false
            color: Colors.text
            selectionColor: Colors.accentSoft
            selectedTextColor: Colors.text
            font.family: Typography.family
            font.pixelSize: Typography.bodySize
            renderType: Typography.renderType
            Accessible.role: Accessible.EditableText
            Accessible.name: "Notes"
            onTextChanged: if (root.read) saveTimer.restart()
            // Tab leaves the note for the next control, as in any form;
            // a tab character is not worth a trap for the keyboard.
            Keys.onTabPressed: event => { event.accepted = false }
            Keys.onBacktabPressed: event => { event.accepted = false }
            // The caret stays in sight as the note grows past the card.
            onCursorRectangleChanged: {
                const rect = cursorRectangle
                if (rect.y < view.contentY) view.contentY = rect.y
                else if (rect.y + rect.height > view.contentY + view.height)
                    view.contentY = rect.y + rect.height - view.height
            }

            ShellText {
                visible: area.text.length === 0 && !area.activeFocus
                text: root.unreadable ? "The notes file cannot be read" : "Write something down …"
                muted: true
            }
        }
    }
}
