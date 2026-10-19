import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/components/TrayMenuLogic.js" as Menu

// A tray menu's labels: the mnemonic marker of DBusMenu goes, a doubled
// underscore is the underscore it stands for.
ShellRoot {
    Component.onCompleted: {
        T.eq(Menu.label("_Open"), "Open", "the mnemonic marker goes")
        T.eq(Menu.label("Save _As"), "Save As", "inside the label too")
        T.eq(Menu.label("Save__As"), "Save_As", "two underscores are one")
        T.eq(Menu.label("snake__case_name"), "snake_casename", "and a marker beside them still goes")
        T.eq(Menu.label("a _ b"), "a _ b", "an underscore before a space is a character")
        T.eq(Menu.label("trailing_"), "trailing_", "and so is one at the end")
        T.eq(Menu.label("____"), "__", "a run of four is two")
        T.eq(Menu.label(undefined), "", "no text, no label")
        T.finish("TrayMenuTest")
    }
}
