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

        T.finish("DateFormatTest")
    }
}
