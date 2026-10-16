import Quickshell
import QtQuick
import qs.theme
import qs.shell.components
import "Harness.js" as T
import "../../shell/settings/pages"
import "../../services/settings/SettingsFieldLogic.js" as F
import "../../services/settings/SwatchLogic.js" as S
import "../../services/appearance/PanelStyleLogic.js" as P

// Settings fields and swatches, without a window: when a page is let go and
// which fields hold a draft (ui-b#16), what a field for a stored value does as
// the focus leaves it and as the page takes or refuses a value (ui-b#8,
// ui-b#11), and the colour swatches as controls a keyboard and a screen reader
// can use (ui-b#13, design#2).
ShellRoot {
    id: root
    property var stored: ({ value: "https://example.org/?q=%s" })
    property var commits: []
    property int picked: 0

    Item {
        id: host
        width: 600
        height: 400
        readonly property Item toolTipLayer: layer

        Column {
            width: parent.width
            StoredTextField {
                id: field
                width: 300
                storedText: root.stored.value
                // A page that tidies what it takes and refuses what it cannot.
                onCommit: value => {
                    root.commits = root.commits.concat([value])
                    if (value.indexOf("bad") >= 0) return
                    root.stored = { value: value.trim() }
                }
            }
            ColorSwatch {
                id: swatch
                fill: "#4f8ff7"
                label: S.nameOf("#4f8ff7")
                onActivated: root.picked += 1
            }
        }
        ToolTipLayer { id: layer }
    }

    Component.onCompleted: {
        // Which fields hold a draft.
        T.eq(F.holdsDraft({ edited: true, text: "half typed" }), true, "typed and not handed on")
        T.eq(F.holdsDraft({ edited: false, text: "set by the page" }), false, "text the page put there is no draft")
        T.eq(F.holdsDraft({ edited: true, text: "" }), false, "an emptied field holds nothing (Escape, a chosen city, Add)")
        T.eq(F.holdsDraft({ edited: true, text: "   " }), false, "nor do spaces")
        T.eq(F.holdsDraft({ edited: true, text: "vol", scratch: true }), false, "a search or a test line is no draft")
        T.eq(F.holdsDraft({ edited: true, text: "same", storedText: "same" }), false, "what is stored already is no draft")
        T.eq(F.holdsDraft({ edited: true, text: "other", storedText: "same" }), true, "what differs from it is")
        T.eq(F.holdsDraft(null), false, "no field")

        // When the page goes.
        T.eq(F.releaseNow(F.CHECK_MS, false, false), true, "a minute after closing, nothing held")
        T.eq(F.releaseNow(F.CHECK_MS, false, true), false, "a draft keeps it")
        T.eq(F.releaseNow(F.CAP_MS, false, true), true, "but not past the cap")
        T.eq(F.releaseNow(F.CAP_MS * 2, true, false), false, "never while a display change waits for its answer")
        T.ok(F.CAP_MS > F.CHECK_MS, "the cap is later than the first look")

        // Leaving a field for a stored value.
        T.eq(F.leaveAction("", "x"), "restore", "an emptied field gets the stored value back")
        T.eq(F.leaveAction("x", "x"), "none", "an unchanged one does nothing")
        T.eq(F.leaveAction("y", "x"), "commit", "a changed one hands its text on")
        T.eq(F.leaveAction(undefined, undefined), "restore", "nothing at all is restored, not stored")

        // The field itself, as the page sees it.
        T.eq(field.text, root.stored.value, "the field starts at the stored value")
        field.text = ""
        field.edited = true
        field.leave()
        T.eq([field.text, root.commits.length, field.edited], [root.stored.value, 0, false],
             "left empty, it puts the stored value back and stores nothing")
        field.text = "  https://other.example/?q=%s  "
        field.edited = true
        field.leave()
        T.eq(root.commits, ["  https://other.example/?q=%s  "], "left changed, it hands the text on once")
        T.eq([root.stored.value, field.text, field.edited], ["https://other.example/?q=%s", "https://other.example/?q=%s", false],
             "and shows what was stored, nothing left to keep")
        field.text = "bad"
        field.edited = true
        field.settle(field.text)
        T.eq([field.text, field.edited], ["bad", true], "a refused value stays in the field as a draft")
        T.eq(F.holdsDraft(field), true, "and keeps the page")
        field.leave()
        T.eq(root.commits.length, 3, "leaving offers it again rather than dropping it")
        field.text = ""
        field.leave()
        T.eq([field.text, field.edited], [root.stored.value, false], "emptied, the stored value is back")
        root.stored = { value: "https://third.example/?q=%s" }
        T.eq(field.text, "https://third.example/?q=%s", "a change from elsewhere shows while nobody types in it")
        T.eq(F.holdsDraft(field), false, "the stored value in the field keeps no page")

        // The login screen's accent (ui-b#11): the field stores only what
        // install/sddm-theme.sh copies, ^#[0-9a-fA-F]{6}$, and refuses the rest.
        const installerTakes = text => /^#[0-9a-fA-F]{6}$/.test(text)
        T.eq([P.normalizeHex("#4f8"), P.normalizeHex(" 4F8FF7 ")], ["#44ff88", "#4f8ff7"], "a short or bare hex is written out")
        T.ok(["#4f8", "#4f8ff7", "4f8ff7"].every(text => installerTakes(P.normalizeHex(text))), "what is stored is what the installer takes")
        T.eq(["teal", "#4f8f", "", "#ggg"].map(text => P.normalizeHex(text)), ["", "", "", ""], "anything else is refused, not stored")

        // Swatches: a stop for Tab, named, and Return chooses.
        T.eq(swatch.activeFocusOnTab, true, "Tab reaches the swatch")
        T.eq([swatch.Accessible.name, swatch.Accessible.role], ["Blue", Accessible.Button], "it has a name and a role")
        swatch.choose()
        T.eq(root.picked, 1, "choosing it is one activation")
        T.eq([S.nameOf("#50E2CB"), S.nameOf("8f97a6"), S.nameOf("#123abc"), S.nameOf("")],
             ["Turquoise", "Gray", "#123ABC", ""], "names, US spelling, and a hex for a colour without one")
        T.ok(Colors.accentChoices.every(color => !/^#/.test(S.nameOf(color))), "every accent choice has a name")

        T.finish("SettingsFieldTest")
    }
}
