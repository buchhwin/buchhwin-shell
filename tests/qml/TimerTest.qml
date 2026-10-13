import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/timer/TimerLogic.js" as L

ShellRoot {
    Component.onCompleted: {
        T.eq([L.parseDuration("5m"), L.parseDuration("90s"), L.parseDuration("1h30m"), L.parseDuration("25"),
              L.parseDuration("1:30"), L.parseDuration(" 2 min ")], [300, 90, 5400, 1500, 90, 120],
             "the ways a duration is typed")
        T.eq([L.parseDuration(""), L.parseDuration("soon"), L.parseDuration("0"), L.parseDuration("1:75"),
              L.parseDuration("25h"), L.parseDuration(undefined)], [0, 0, 0, 0, 0, 0],
             "anything else is no timer, and nothing past a day")
        T.eq([L.remainingText(299001), L.remainingText(59000), L.remainingText(3723000), L.remainingText(-5)],
             ["5:00", "0:59", "1:02:03", "0:00"], "the time left, rounded up to the second")
        T.eq([L.fraction(150000, 300), L.fraction(0, 300), L.fraction(400000, 300), L.fraction(10, 0)],
             [0.5, 0, 1, 0], "how much is left, clamped")
        T.eq([L.label(300), L.label(60), L.label(3600), L.label(7200), L.label(90)],
             ["5 minutes", "1 minute", "1 hour", "2 hours", "90 seconds"], "the duration in words")
        T.finish("TimerTest")
    }
}
