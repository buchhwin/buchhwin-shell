import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/Calculator.js" as Calc

ShellRoot {
    function value(input) {
        const result = Calc.evaluate(input)
        return result.ok ? result.value : "error:" + result.error
    }

    Component.onCompleted: {
        T.eq(value("1 + 2 * 3"), 7, "precedence")
        T.eq(value("(1 + 2) * 3"), 9, "parentheses")
        T.eq(value("2 ^ 3 ^ 2"), 512, "power is right associative")
        T.eq(value("-2 ^ 2"), -4, "unary minus binds weaker than power")
        T.eq(value("--3"), 3, "double unary minus")
        T.eq(value("10 % 4"), 2, "modulo")
        T.eq(value("1,5 * 2"), 3, "comma decimals")
        T.eq(value("2e3 + 1"), 2001, "exponent notation")
        T.near(value("sqrt(16) + pi"), 4 + Math.PI, "functions and constants", 1e-12)
        T.eq(value("3 × 4 ÷ 2"), 6, "typographic operators")
        T.ok(String(value("1 / 0")).startsWith("error"), "division by zero")
        T.ok(String(value("alert(1)")).startsWith("error"), "unknown identifiers rejected")
        T.ok(String(value("Qt.quit()")).startsWith("error"), "globals rejected")
        T.ok(String(value("constructor")).startsWith("error"), "prototype names rejected")
        T.ok(String(value("1 +")).startsWith("error"), "incomplete input")
        T.ok(String(value("1.2.3")).startsWith("error"), "invalid numbers")
        T.ok(Calc.looksLikeMath("12*3"), "inline detection")
        T.ok(!Calc.looksLikeMath("firefox"), "plain text is not math")
        T.eq(Calc.format(0.1 + 0.2), "0.3", "formatting rounds float noise")
        T.finish("CalculatorTest")
    }
}
