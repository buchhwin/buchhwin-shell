import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/components/NavLogic.js" as Nav

ShellRoot {
    component Control: Item { property bool focusOnTab: false; width: 40; height: 40 }

    // A 2 x 2 grid of controls, a hidden one, a plain item and a disabled one.
    property Item grid: Item {
        width: 200; height: 200
        Control { objectName: "a"; x: 0; y: 0 }
        Control { objectName: "b"; x: 100; y: 0 }
        Item {
            Control { objectName: "c"; x: 0; y: 100 }
            Control { objectName: "d"; x: 100; y: 100 }
        }
        Control { objectName: "hidden"; x: 50; y: 50; visible: false }
        Item { objectName: "plain"; x: 50; y: 150; width: 40; height: 40 }
        Control { objectName: "off"; x: 150; y: 150; enabled: false }
        Control { objectName: "header"; x: 140; y: -70 }
    }

    // A list taller than its view (the notification center's cards): the
    // walk reaches the cards below the fold, and the list follows.
    property Item page: Item {
        width: 200; height: 300
        Control { objectName: "top"; x: 0; y: 0 }
        Flickable {
            id: list
            y: 50
            width: 200; height: 200
            contentHeight: column.height
            Column {
                id: column
                Repeater {
                    model: 10
                    Control { objectName: "card" + index; width: 200; height: 60 }
                }
            }
        }
    }

    // Rows that are stops themselves, one with a control in its trailing
    // slot (ListRow's `trailing`: the Bluetooth page's Remove, a volume's
    // Unmount and Lock): the control is a stop of its own, right after its
    // row. A row without one is unchanged.
    component Row: Item {
        property bool focusOnTab: false
        default property alias trailing: slot.data
        width: 200; height: 40
        Item { id: slot; anchors.fill: parent }
    }
    property Item rows: Item {
        width: 200; height: 100
        Row { objectName: "row"; Control { objectName: "remove"; x: 150 } }
        Row { objectName: "bare"; y: 50 }
    }

    function named(name) { return Nav.focusables(grid).find(item => item.objectName === name) }
    function name(item) { return item ? item.objectName : "none" }

    Component.onCompleted: {
        T.eq(Nav.focusables(grid).map(name), ["a", "b", "c", "d", "header"], "controls in tree order; hidden, plain and disabled ones left out")
        T.eq(name(Nav.tabStep(grid, null, false)), "a", "Tab from nothing starts at the first")
        T.eq(name(Nav.tabStep(grid, null, true)), "header", "Shift+Tab from nothing starts at the last")
        T.eq(name(Nav.tabStep(grid, named("header"), false)), "a", "Tab wraps around")
        T.eq(name(Nav.arrowStep(grid, named("b"), 1, 0)), "none", "Right from the end of a row does not climb to a control above and beside it")
        T.eq(name(Nav.arrowStep(grid, named("a"), 1, 0)), "b", "Right goes to the neighbour")
        T.eq(name(Nav.arrowStep(grid, named("a"), 0, 1)), "c", "Down goes to the one below, not the diagonal")
        T.eq(name(Nav.arrowStep(grid, named("d"), -1, 0)), "c", "Left from the corner")
        T.eq(name(Nav.arrowStep(grid, named("a"), -1, 0)), "none", "nothing further left")
        T.eq(name(Nav.arrowStep(grid, named("c").children[0] || named("c"), 0, -1)), "a", "focus on a control's part counts as the control")

        // ---- into view ----------------------------------------------------
        const cards = Nav.focusables(page)
        T.eq(cards.map(name).slice(0, 3), ["top", "card0", "card1"], "the cards are in the walk, below the fold or not")
        T.eq(Nav.reveal(cards[1], 8), 0, "a card in view leaves the list where it is")
        T.eq(list.contentY, 0, "at the top")
        const fifth = cards[6]   // card5, at 300 in a 200 px view
        T.eq(Nav.reveal(fifth, 8), 1, "a card below the fold moves the list")
        T.eq(list.contentY, 300 + 60 + 8 - 200, "just far enough to show it, with the air below it")
        T.eq(Nav.reveal(cards[1], 8), 1, "back up to one above the view")
        T.eq(list.contentY, 0, "as far as the list goes, not past its start")
        T.eq(Nav.reveal(cards[10], 8), 1, "the last card")
        T.eq(list.contentY, 600 - 200, "at the end of the list, not past it")
        T.eq(Nav.reveal(cards[0], 8), 0, "a control outside any list moves nothing")
        T.eq(Nav.tabStep(page, cards[10], false), cards[0], "Tab from the last card wraps to the top")

        // ---- a row's own controls -------------------------------------------
        T.eq(Nav.focusables(rows).map(name), ["row", "remove", "bare"], "a row's trailing control is a stop after the row")
        const remove = Nav.focusables(rows)[1]
        T.eq(name(Nav.tabStep(rows, remove, false)), "bare", "Tab from it goes on to the next row")
        T.eq(name(Nav.arrowStep(rows, Nav.focusables(rows)[0], 1, 0)), "remove", "Right from the row reaches it")
        T.finish("NavTest")
    }
}
