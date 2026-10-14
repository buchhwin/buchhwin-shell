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
        T.finish("NavTest")
    }
}
