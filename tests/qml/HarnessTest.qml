import Quickshell
import QtQuick
import "Harness.js" as T

ShellRoot {
    Component.onCompleted: {
        T.eq(1 + 1, 2, "addition")
        T.near(0.1 + 0.2, 0.3, "floating point", 1e-12)
        T.throwsError(() => { throw new Error("x") }, "throws")
        T.finish("HarnessTest")
    }
}
