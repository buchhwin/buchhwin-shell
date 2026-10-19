import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/DateFormat.js" as F

// A date in the locale's order of day and month. The dashboard said "Mon, Oct
// 19" and the lock screen "Monday, 19 October" under the same en_GB locale:
// fixed patterns, two of them. The patterns below are Qt's own long dates
// (Qt.locale(name).dateFormat()), written out so a newer Qt's data cannot
// move what the rules are tested on; the real locales follow at the end.
ShellRoot {
    Component.onCompleted: {
        // ---- the locale's long date without its year -------------------------
        T.eq(F.pattern("dddd, MMMM d, yyyy", "long"), "dddd, MMMM d", "en_US: month first")
        T.eq(F.pattern("dddd, d MMMM yyyy", "long"), "dddd, d MMMM", "en_GB: day first")
        T.eq(F.pattern("dddd, d. MMMM yyyy", "long"), "dddd, d. MMMM", "de_DE keeps its full stop")
        T.eq(F.pattern("dddd d MMMM yyyy", "long"), "dddd d MMMM", "fr_FR without a comma")
        T.eq(F.pattern("dddd, d 'de' MMMM 'de' yyyy", "long"), "dddd, d 'de' MMMM",
             "es_ES: the year's 'de' goes with it, the month's stays")
        T.eq(F.pattern("dddd, d MMMM yyyy 'г'.", "long"), "dddd, d MMMM", "ru_RU: the year's marker after it goes too")
        T.eq(F.pattern("yyyy年M月d日dddd", "long"), "M月d日dddd", "ja_JP: a year in front, with its marker")
        T.eq(F.pattern("yyyy. MMMM d., dddd", "long"), "MMMM d., dddd", "hu_HU")
        T.eq(F.pattern("yyyy 'm'. MMMM d 'd'., dddd", "long"), "MMMM d 'd'., dddd", "lt_LT")

        // ---- short, without the weekday, with the year -------------------------
        T.eq(F.pattern("dddd, MMMM d, yyyy", "short"), "ddd, MMM d", "en_US short")
        T.eq(F.pattern("dddd, d MMMM yyyy", "short"), "ddd, d MMM", "en_GB short")
        T.eq(F.pattern("dddd, d. MMMM yyyy", "short"), "ddd, d. MMM", "de_DE short")
        T.eq(F.pattern("dddd, MMMM d, yyyy", "day"), "MMMM d", "en_US without the weekday")
        T.eq(F.pattern("dddd, d. MMMM yyyy", "day"), "d. MMMM", "de_DE without the weekday")
        T.eq(F.pattern("yyyy年M月d日dddd", "day"), "M月d日", "ja_JP keeps the day's marker")
        T.eq(F.pattern("yyyy. MMMM d., dddd", "day"), "MMMM d.", "hu_HU drops only the comma")
        T.eq(F.pattern("dddd, d MMMM yyyy", "year"), "dddd, d MMMM yyyy", "with the year: the locale's long date")
        T.eq(F.pattern("dddd, MMMM d, yyyy"), "dddd, MMMM d", "no form is the long one")

        // ---- what cannot be taken apart falls back on the order ------------------
        T.eq(F.pattern("d. MMMM yyyy, 'den' dddd yyyy", "long"), "dddd, d MMMM",
             "a year in the middle: day first by the locale's order")
        T.eq(F.pattern("MMMM yyyy d", "long"), "dddd, MMMM d", "and month first")
        T.eq(F.pattern("", "long"), "dddd, MMMM d", "no pattern at all")
        T.eq([F.dayFirst("dddd, d MMMM yyyy"), F.dayFirst("dddd, MMMM d, yyyy"), F.dayFirst("yyyy年M月d日dddd")],
             [true, false, false], "which comes first")

        // ---- the real locales ---------------------------------------------------
        const day = new Date(2026, 9, 19)
        T.eq(F.date(day, Qt.locale("en_US"), "long"), "Monday, October 19", "en_US")
        T.eq(F.date(day, Qt.locale("en_GB"), "long"), "Monday, 19 October", "en_GB")
        T.eq(F.date(day, Qt.locale("de_DE"), "long"), "Montag, 19. Oktober", "de_DE")
        T.eq(F.date(day, Qt.locale("en_US"), "short"), "Mon, Oct 19", "en_US short")
        T.eq(F.date(day, Qt.locale("en_GB"), "short"), "Mon, 19 Oct", "en_GB short")
        T.eq(F.date(day, Qt.locale("en_GB"), "day"), "19 October", "en_GB without the weekday")
        T.eq(F.date(day, Qt.locale("en_US"), "year"), "Monday, October 19, 2026", "en_US with the year")
        T.eq(F.date(day, Qt.locale("en_GB"), "year"), "Monday, 19 October 2026", "en_GB with the year")
        T.eq(F.date(null, Qt.locale("en_US"), "long"), "", "no date, no words")

        // ---- the order Settings chooses -------------------------------------------
        // "locale" and an order this file does not know are the locale's own.
        T.eq(F.pattern("dddd, MMMM d, yyyy", "long", "locale"), "dddd, MMMM d", "locale: en_US as it is")
        T.eq(F.pattern("dddd, MMMM d, yyyy", "long", "sideways"), "dddd, MMMM d", "an unknown order is the locale's")
        T.eq(F.pattern("dddd, MMMM d, yyyy", "long", "dayMonth"), "dddd, d MMMM", "day first on en_US")
        T.eq(F.pattern("dddd, d MMMM yyyy", "long", "monthDay"), "dddd, MMMM d", "month first on en_GB")
        T.eq(F.pattern("dddd, d. MMMM yyyy", "long", "dayMonth"), "dddd, d. MMMM",
             "de_DE asked for its own order keeps its full stop")
        T.eq(F.pattern("dddd, d MMMM yyyy", "long", "dayMonth"), "dddd, d MMMM", "en_GB asked for its own order")
        T.eq(F.pattern("dddd, MMMM d, yyyy", "short", "dayMonth"), "ddd, d MMM", "short, day first")
        T.eq(F.pattern("dddd, d MMMM yyyy", "day", "monthDay"), "MMMM d", "without the weekday, month first")
        T.eq(F.pattern("dddd, MMMM d, yyyy", "year", "dayMonth"), "dddd, d MMMM yyyy", "with the year, day first")
        T.eq(F.pattern("dddd, d MMMM yyyy", "year", "monthDay"), "dddd, MMMM d, yyyy", "with the year, month first")
        T.eq(F.pattern("dddd, d MMMM yyyy", "year", "dayMonth"), "dddd, d MMMM yyyy", "with the year in its own order")
        T.eq(F.pattern("yyyy年M月d日dddd", "long", "dayMonth"), "dddd, d MMMM", "ja_JP the other way round")
        T.eq(F.pattern("", "long", "dayMonth"), "dddd, d MMMM", "no pattern, day first")
        T.eq([F.wantsDayFirst("dayMonth", "dddd, MMMM d, yyyy"), F.wantsDayFirst("monthDay", "dddd, d MMMM yyyy"),
              F.wantsDayFirst("locale", "dddd, d MMMM yyyy"), F.wantsDayFirst(undefined, "dddd, MMMM d, yyyy")],
             [true, false, true, false], "which comes first, asked")
        T.eq(F.ORDERS, ["locale", "dayMonth", "monthDay"], "the three choices")

        // ---- numbers ----------------------------------------------------------------
        T.eq(F.numericPattern("dd/MM/yyyy", true), "d/M", "en_GB's short date without the year")
        T.eq(F.numericPattern("M/d/yy", false), "M/d", "en_US's")
        T.eq(F.numericPattern("dd.MM.yy", true), "d.M.", "de_DE's, with the full stop after the month")
        T.eq(F.numericPattern("M/d/yy", true), "d.M.", "day first where the locale writes month first")
        T.eq(F.numericPattern("dd/MM/yyyy", false), "M/d", "and month first where it writes day first")
        T.eq(F.numericPattern("yyyy/MM/dd", false), "M/d", "ja_JP: a year in front")
        T.eq(F.numericPattern("", true), "d.M.", "no short pattern")
        T.eq(F.pattern("dddd, d MMMM yyyy", "numeric", "locale", "dd/MM/yyyy"), "d/M", "the numeric form")
        T.eq(F.pattern("dddd, d MMMM yyyy", "short", "locale", "dd/MM/yyyy", true), "ddd d/M", "the short form in numbers")
        T.eq(F.pattern("dddd, d MMMM yyyy", "short", "locale", "dd/MM/yyyy", false), "ddd, d MMM", "and in words")
        T.eq(F.pattern("dddd, d MMMM yyyy", "long", "locale", "dd/MM/yyyy", true), "dddd, d MMMM",
             "numbers change only the short form")

        // ---- the real locales, asked for an order ------------------------------------
        T.eq(F.date(day, Qt.locale("en_GB"), "long", "monthDay"), "Monday, October 19", "en_GB month first")
        T.eq(F.date(day, Qt.locale("en_US"), "long", "dayMonth"), "Monday, 19 October", "en_US day first")
        T.eq(F.date(day, Qt.locale("de_DE"), "long", "monthDay"), "Montag, Oktober 19", "de_DE month first, German words")
        T.eq(F.date(day, Qt.locale("en_US"), "year", "dayMonth"), "Monday, 19 October 2026", "en_US day first with the year")
        T.eq(F.date(day, Qt.locale("en_GB"), "long", "locale"), "Monday, 19 October", "en_GB as the language says")
        T.eq(F.date(day, Qt.locale("en_GB"), "numeric"), "19/10", "en_GB in numbers")
        T.eq(F.date(day, Qt.locale("en_US"), "numeric"), "10/19", "en_US in numbers")
        T.eq(F.date(day, Qt.locale("de_DE"), "numeric"), "19.10.", "de_DE in numbers")
        T.eq(F.date(new Date(2026, 9, 9), Qt.locale("en_US"), "numeric", "dayMonth"), "9.10.", "one digit where one is enough")
        T.eq(F.date(day, Qt.locale("en_GB"), "short", "locale", true), "Mon 19/10", "en_GB short in numbers")
        T.eq(F.date(day, Qt.locale("en_US"), "short", "dayMonth", true), "Mon 19.10.", "en_US short, day first, in numbers")
        T.eq(F.date(day, Qt.locale("en_GB"), "short", "locale", false), "Mon, 19 Oct", "short in words as before")

        T.finish("DateFormatTest")
    }
}
