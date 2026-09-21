.pragma library

// The one place a time is turned into text.
//
// It was nine `Qt.formatTime(date, "HH:mm")` calls in six files - the clock
// widget, the calendar widget, the dashboard, the hourly strip, the lock
// screen and the weather service - so the shell could only ever show 24 hours,
// however its locale was set. The date already followed the locale through
// `SettingsService.locale.toString(...)`; only the time did not. The Starship
// prompt in the terminal even had its own `timeFormat` setting, so the
// *prompt* was configurable and the shell's own clock was not.
//
// Nine copies of a rule is eight too many by this project's own measure, which
// is why the ten-frame animation floor lives in AnimationLogic.js rather than
// at each call site. Same reasoning, same shape.
//
// `twelve` is a boolean rather than the setting, and the locale question is
// answered by SettingsService: `Qt.locale(...).timeFormat()` needs the QML
// `Locale` enum, which a pragma library has no business reaching for. This
// file is arithmetic and string work, and is unit tested as such.

// The hour as it should be shown. 24-hour keeps the leading zero, because a
// column of times has to line up; 12-hour drops it, because "06:52 PM" is not
// how anyone writes it.
function hour(date, twelve) {
    const value = date.getHours()
    if (!twelve) return value < 10 ? "0" + value : String(value)
    const shown = value % 12
    return String(shown === 0 ? 12 : shown)
}

function minute(date) {
    const value = date.getMinutes()
    return value < 10 ? "0" + value : String(value)
}

// "AM"/"PM", and an empty string on a 24-hour clock so a caller can append it
// unconditionally.
function suffix(date, twelve) {
    if (!twelve) return ""
    return date.getHours() < 12 ? "AM" : "PM"
}

// The whole time. `separator` is what goes between the two numbers - the
// clock widget uses " : " at its largest size and ":" in a pill.
function time(date, twelve, separator) {
    const middle = separator === undefined ? ":" : String(separator)
    const tail = suffix(date, twelve)
    return hour(date, twelve) + middle + minute(date) + (tail.length ? " " + tail : "")
}

// An hour on its own, for the weather strip: "14" or "2 PM".
function hourLabel(date, twelve) {
    const tail = suffix(date, twelve)
    return hour(date, twelve) + (tail.length ? " " + tail : "")
}
