import Quickshell
import QtQuick
import "Harness.js" as T

ShellRoot {
    Component.onCompleted: {
        T.eq(1 + 1, 2, "addition")
        T.near(0.1 + 0.2, 0.3, "floating point", 1e-12)
        T.throwsError(() => { throw new Error("x") }, "throws")
        // What JSON cannot write is not equal to what it writes instead.
        T.ok(!T.same(NaN, null), "NaN is not null")
        T.ok(!T.same(Infinity, null), "Infinity is not null")
        T.ok(!T.same(function () {}, undefined), "a function is not undefined")
        T.ok(!T.same([NaN], [null]), "NaN in a list is not null")
        T.ok(!T.same({ a: undefined }, {}), "an undefined member is not a missing one")
        T.ok(!T.same([undefined], [null]), "undefined in a list is not null")
        T.ok(T.same(undefined, undefined) && T.same(NaN, NaN) && T.same({ a: [1, "x"] }, { a: [1, "x"] }),
             "the same values are still the same")
        T.ok(T.same(-0, 0), "-0 compares as 0")
        T.ok(!T.same("undefined", undefined) && !T.same("NaN", NaN), "a string of the same name is not the value")
        T.eq(T.format(NaN) + " " + T.format({ a: undefined }), "NaN {\"a\":undefined}", "and a failure names them")
        T.finish("HarnessTest")
    }
}
