import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/ConvertLogic.js" as C

// Conversions in the launcher (services/launcher/ConvertLogic.js): which
// queries are one - only those start a process -, what qalc is asked, and
// which of its answers become a row. The outputs below are qalc 5.13's own,
// for the arguments `command` builds.
ShellRoot {
    function expression(text) {
        const parsed = C.parse(text)
        return parsed ? parsed.expression : null
    }

    Component.onCompleted: {
        // ---- the shape -----------------------------------------------------
        T.eq(expression("10 km to mi"), "10 km to -mi", "a conversion, one unit asked for (no mixed units)")
        T.eq(expression("3 h in min"), "3 h to -min", "\"in\" between the sides is a separator, not inches")
        T.eq(expression("72 in to cm"), "72 in to -cm", "and before \"to\" it is the inch")
        T.eq(expression("72 in in cm"), "72 in to -cm", "both at once: the separator is the last one")
        T.eq(expression("10 km to in"), "10 km to -in", "an inch as the target")
        T.eq(expression("20 C in F"), "20 °C to -°F", "a bare C and F between temperatures (qalc: coulombs, farads)")
        T.eq(expression("300 K to c"), "300 K to -°C", "kelvin to Celsius")
        T.eq(expression("-40 celsius as fahrenheit"), "-40 °C to -°F", "by name, with a minus")
        T.eq(expression("1 C to mC"), "1 C to -mC", "a charge stays a charge")
        T.eq(expression("1,5 h to min"), "1.5 h to -min", "a decimal comma is a decimal point (qalc would ask)")
        T.eq(expression("10km to mi"), "10 km to -mi", "a unit glued to its number")
        T.eq(expression("$100 to eur"), "100 $ to -eur", "a currency symbol in front")
        T.eq(expression("100 € → usd"), "100 € to -usd", "an arrow as the separator")
        T.eq(expression("60 mph -> km/h"), "60 mph to -km/h", "compound units")
        T.eq(expression("10 m² to ft²"), "10 m² to -ft²", "powers")
        T.eq(expression("255 to hex"), "255 to hex", "a number base takes no minus (\"-hex\" is an error to qalc)")
        T.eq(expression("1994 in roman"), "1994 to roman", "numerals")
        T.eq(expression("2e3 m to km"), "2e3 m to -km", "an exponent")
        T.eq([expression("firefox"), expression("10 km"), expression("km to mi"), expression("10 to km")], [null, null, null, null],
             "an app's name, a lone quantity, no number, no unit: nothing to ask")
        T.eq([expression("5 nautical miles to km"), expression("10 fl oz to ml")], [null, null],
             "two-word units are not offered (qalc reads them as products of prefixes)")
        T.eq([expression("10 km to km"), expression("10 km to"), expression("to km to mi")], [null, null, null],
             "the same unit, no target, no number")
        T.eq([expression("10 km to (mi)"), expression("10 km; rm to mi"), expression("1 + 2 to hex")], [null, null, null],
             "nothing but units and numbers reaches qalc")
        T.eq(C.parse("12 * (3 + 4)"), null, "arithmetic stays the calculator's")

        const money = C.parse("100 eur to usd")
        T.ok(money.currency, "two currencies by code")
        T.ok(C.parse("100 euros to dollars").currency && C.parse("$100 to eur").currency, "by name and by symbol")
        T.ok(!C.parse("10 km to mi").currency && !C.parse("100 eur to km").currency, "a unit is no currency, nor is half of a pair")
        T.eq(C.parse("255 to hex").kind, "base", "a base is its own kind")

        // ---- what qalc is asked ----------------------------------------------
        T.eq(C.command(C.parse("10 km to mi"), false),
             ["qalc", "-s", "ignore locale 1", "-s", "upxrates 0", "-s", "color 0", "-m", "2000", "10 km to -mi"],
             "no locale's decimal comma, no rates fetched on its own, no colours, cut off at two seconds")
        T.eq(C.command(money, true).slice(-2), ["-e", "100 eur to -usd"], "the day's rates first when asked to")
        T.eq(C.command(null, false), [], "nothing to ask")
        const day = 24 * 60 * 60 * 1000
        T.ok(!C.needsRates(money, false, 0, 10 * day), "rates are fetched only when the user turned it on")
        T.ok(C.needsRates(money, true, 0, 10 * day), "on, and never fetched: fetched")
        T.ok(!C.needsRates(money, true, 10 * day - 1000, 10 * day), "fetched today: not again")
        T.ok(C.needsRates(money, true, 8 * day, 10 * day), "a day old: again")
        T.ok(!C.needsRates(C.parse("10 km to mi"), true, 0, day), "never for units")
        T.ok(C.ratesFailed("warning: It has been 21 days since the exchange rates last were updated.\n100 EUR ≈ $113.78"),
             "a warning about the rates is a fetch that did not happen")
        T.ok(!C.ratesFailed("100 EUR ≈ $112.25\n"), "a clean answer is one that did")

        // ---- qalc's answers --------------------------------------------------
        const km = C.parse("10 km to mi")
        T.eq(C.answer("10 kilometers ≈ 6.213711922 mi\n", km),
             { title: "6.21371 mi", full: "6.213711922 mi", copy: "6.213711922 mi", number: "6.213711922", echo: "10 kilometers",
               approximate: true },
             "the answer rounded to read, how qalc read the question, and the full number to copy")
        T.eq(["$113.78", "CHF 83.1781", "−40 °F", "1073741824 B", "9.46E15 m", "0.000123456789 m", "123456.789 km", "1.5 h"].map(C.shownAnswer),
             ["$113.78", "CHF 83.1781", "−40 °F", "1073741824 B", "9.46E15 m", "0.000123457 m", "123457 km", "1.5 h"],
             "only a long decimal is rounded, to six digits")
        T.eq(C.subtitle(km, C.answer("10 kilometers ≈ 6.213711922 mi\n", km), false),
             "10 kilometers ≈ 6.213711922 mi · Enter copies", "the row's second line")
        const temperature = C.parse("-40 C to F")
        T.eq(C.answer("−40 °C = −40 °F\n", temperature).copy, "-40 °F", "the typographic minus is copied as a minus")
        T.eq(C.answer("−40 °C = −40 °F\n", temperature).number, "-40", "and the number alone too")
        const rates = "warning: It has been 21 days since the exchange rates last were updated.\n100 EUR ≈ $113.78\n"
        T.eq(C.answer(rates, money).number, "113.78", "a currency's symbol is not part of the number")
        T.eq(C.subtitle(money, C.answer(rates, money), false), "100 EUR ≈ $113.78 · offline exchange rates · Enter copies",
             "rates that were not fetched say so")
        T.eq(C.subtitle(money, C.answer(rates, money), true), "100 EUR ≈ $113.78 · Enter copies", "fetched ones do not")
        T.eq(C.answer("100 USD ≈ CHF 83.1781\n", C.parse("100 usd to chf")).title, "CHF 83.1781", "a code in front of the number")
        T.eq(C.answer("1 lightyear ≈ 9.460730473E15 m\n", C.parse("1 ly to m")).number, "9.460730473E15", "an exponent stays")
        T.eq(C.answer("255 = 0xFF\n", C.parse("255 to hex")).copy, "0xFF", "a base's answer")
        T.eq(C.answer("1994 = MCMXCIV\n", C.parse("1994 to roman")).number, "MCMXCIV", "numerals have no digits and are whole")

        T.eq(C.answer("5 meters = 5 m\n", C.parse("5 m to foo")), null, "still the unit it started in: no conversion")
        T.eq(C.answer("5 femtobyte·bytes = 5E−15 B²\n", C.parse("5 foo to bar")), null,
             "a lower-case word read as a product of prefixes")
        T.eq(C.answer("2 minute·seconds = 120 s²\n", C.parse("2 mins to s")), null, "\"mins\" read as minute·seconds")
        T.ok(C.answer("1 kilowatt·hour = 3600000 J\n", C.parse("1 kWh to J")) !== null, "while kWh is one")
        T.eq(C.answer("3000 rpm ≈ −(−(1130973.355 / z) × (z h·rad) / h²)\n", C.parse("3000 rpm to hz")), null,
             "a formula is no answer")
        T.eq(C.answer("warning: Did you mean \"stone\" (instead of \"stunde\")?\n1 second·tonne ≈ 3 min\n", C.parse("1 stunde to min")), null,
             "a guess qalc warns about")
        T.eq(C.answer("error: \"j\" is not a valid variable/function/unit.\n1 hour = −0 h / 0\n", C.parse("1 kwh to j")), null,
             "an error")
        T.eq([C.answer("", km), C.answer("6.2 mi\n", km), C.answer("10 kilometers ≈ \n", km)], [null, null, null],
             "no output, no separator, no answer")

        T.finish("LauncherConvertTest")
    }
}
