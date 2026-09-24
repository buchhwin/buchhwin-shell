import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/RecurrenceLogic.js" as R

// What the event editor offers for "Repeat" and how a rule reads in words.
// The rule grammar itself lives in scripts/lib/ical.py and is tested there.
ShellRoot {
    Component.onCompleted: {
        T.eq(R.repeatOptions().map(option => option.value),
             ["", "daily", "weekdays", "weekly", "monthly", "yearly"], "every repetition the editor offers")
        T.eq(R.repeatOptions()[0].label, "Never", "no repetition comes first")
        T.eq(R.endingOptions().map(option => option.value), ["never", "until", "count"], "how a repetition ends")

        // A weekly rule follows the day the event starts on.
        T.eq(R.weekdayOf(new Date(2026, 2, 10)), "TU", "Tuesday")
        T.eq(R.weekdayOf(new Date(2026, 2, 15)), "SU", "Sunday")
        T.eq(R.weekdayOf(null), "", "no date, no weekday")

        T.eq(R.describe({ repeat: "" }), "Does not repeat", "no rule")
        T.eq(R.describe({ repeat: "weekly", weekday: "TU", count: 0, until: "" }), "Every week on Tuesday", "weekly")
        T.eq(R.describe({ repeat: "daily", count: 1, until: "" }), "Every day, 1 time", "one time, not times")
        T.eq(R.describe({ repeat: "daily", count: 4, until: "" }), "Every day, 4 times", "a count")
        T.eq(R.describe({ repeat: "monthly", count: 0, until: "20261130T235959Z" }),
             "Every month, until 2026-11-30", "an end date")
        T.eq(R.describe({ repeat: "weekdays", count: 0, until: "" }), "Every weekday", "weekdays")

        T.eq(R.untilDay("20261130T235959Z"), "2026-11-30", "an UNTIL value as a day")
        T.eq(R.untilDay("20261130"), "2026-11-30", "an all-day UNTIL value")
        T.eq(R.untilDay(""), "", "no end date")

        // Reading the helper's answer back into the editor's fields.
        const start = new Date(2026, 2, 10)
        T.eq(R.emptyDraft(start), { repeat: "", weekday: "TU", ending: "never", count: 10, until: "", known: true },
             "a new event does not repeat, but knows its weekday")
        const weekly = R.ruleDraft({ recurs: true, repeat: "weekly", weekday: "TU", count: 0, until: "", ruleKnown: true }, start)
        T.eq([weekly.repeat, weekly.weekday, weekly.ending], ["weekly", "TU", "never"], "a weekly series")
        const counted = R.ruleDraft({ recurs: true, repeat: "daily", count: 3, until: "", ruleKnown: true }, start)
        T.eq([counted.ending, counted.count], ["count", 3], "a series that ends after a number of times")
        const dated = R.ruleDraft({ recurs: true, repeat: "monthly", count: 0, until: "20261130T235959Z", ruleKnown: true }, start)
        T.eq([dated.ending, dated.until], ["until", "2026-11-30"], "a series that ends on a date")
        const foreign = R.ruleDraft({ recurs: true, repeat: "monthly", ruleKnown: false }, start)
        T.eq([foreign.known, foreign.repeat], [false, ""], "a rule the editor cannot show again is not offered")

        // Validation
        T.eq(R.validate({ repeat: "" }, "2026-03-10").ok, true, "no repetition is always fine")
        T.eq(R.validate({ repeat: "daily", ending: "count", count: 0 }, "2026-03-10").error,
             "Repeat between 1 and 999 times.", "a count of zero")
        T.eq(R.validate({ repeat: "daily", ending: "count", count: 1000 }, "2026-03-10").ok, false, "too many times")
        T.eq(R.validate({ repeat: "daily", ending: "count", count: 2.5 }, "2026-03-10").ok, false, "half a time")
        T.eq(R.validate({ repeat: "daily", ending: "until", until: "junk" }, "2026-03-10").error,
             "Enter the last date as YYYY-MM-DD.", "an unreadable end date")
        T.eq(R.validate({ repeat: "daily", ending: "until", until: "2026-03-09" }, "2026-03-10").error,
             "The repetition ends before the event starts.", "an end before the start")
        T.eq(R.validate({ repeat: "daily", ending: "until", until: "2026-03-10" }, "2026-03-10").ok, true,
             "ending on the first day is allowed")
        // Dates, not strings: "2026-9-5" sorts after "2026-12-24" as text.
        T.eq(R.validate({ repeat: "daily", ending: "until", until: "2026-12-24" }, "2026-9-5").ok, true,
             "an unpadded start day is still before a padded end date")
        T.eq(R.validate({ repeat: "daily", ending: "until", until: "2026-9-4" }, "2026-09-05").ok, false,
             "and an unpadded end date before the start is still refused")
        T.eq(R.validate({ repeat: "daily", ending: "until", until: "2026-03-09" }, "junk").ok, true,
             "a start day that is not a date is not compared against")

        // What reaches the helper
        T.eq(R.payload({ repeat: "" }), { repeat: "", weekday: "", count: 0, until: "" }, "no rule")
        T.eq(R.payload({ repeat: "weekly", weekday: "TU", ending: "never", count: 5, until: "2026-11-30" }),
             { repeat: "weekly", weekday: "TU", count: 0, until: "" }, "a rule that never ends drops both endings")
        T.eq(R.payload({ repeat: "daily", weekday: "TU", ending: "count", count: 5, until: "2026-11-30" }),
             { repeat: "daily", weekday: "", count: 5, until: "" }, "only a weekly rule carries a weekday")
        T.eq(R.payload({ repeat: "monthly", ending: "until", count: 5, until: "2026-11-30" }).until, "2026-11-30",
             "an end date")

        T.eq(R.sameRule({ repeat: "daily", ending: "never" }, { repeat: "daily", ending: "never", count: 3 }), true,
             "an unused count does not make a rule different")
        T.eq(R.sameRule({ repeat: "daily", ending: "never" }, { repeat: "weekly", ending: "never" }), false,
             "a different repetition is a different rule")

        T.finish("RecurrenceTest")
    }
}
