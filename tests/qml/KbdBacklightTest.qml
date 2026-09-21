import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/power/KbdBacklightLogic.js" as K

ShellRoot {
    Component.onCompleted: {
        // This machine's light has three levels; nothing may hard-code that.
        T.eq([K.label(0, 2), K.label(1, 2), K.label(2, 2)], ["Off", "Low", "High"], "three levels are words")
        T.eq([K.label(0, 1), K.label(1, 1)], ["Off", "On"], "a light with one step is off or on")
        T.eq([K.label(0, 3), K.label(2, 3), K.label(3, 3)], ["Off", "Medium", "High"], "four levels are still words")
        T.eq([K.label(0, 8), K.label(4, 8), K.label(8, 8)], ["Off", "50%", "100%"],
             "past what words can name, a percentage - and off is still Off")
        T.eq(K.label(1, 0), "", "a machine with no keyboard light says nothing at all")

        // The OSD cuts its track into one box per step, and gives up on that
        // when there are too many to count at a glance.
        T.eq([K.segments(1), K.segments(2), K.segments(6)], [1, 2, 6], "one box per step")
        T.eq([K.segments(7), K.segments(0), K.segments(-3)], [0, 0, 0], "and a plain track otherwise")

        // Stepping clamps at both ends: a held key stops at the brightest
        // rather than starting again at off.
        T.eq([K.step(0, 2, 1), K.step(1, 2, 1), K.step(2, 2, 1)], [1, 2, 2], "up, and no further")
        T.eq([K.step(2, 2, -1), K.step(1, 2, -1), K.step(0, 2, -1)], [1, 0, 0], "down, and no further")
        T.eq(K.step(0, 2, 5), 2, "a step past the top lands on the top")

        // The toggle does not remember where it was: the key is pressed to see
        // the keyboard, and half-lit is not what that asks for.
        T.eq([K.toggle(0, 2), K.toggle(1, 2), K.toggle(2, 2)], [2, 0, 0], "off goes bright, anything else goes off")
        T.eq(K.toggle(0, 0), 0, "nothing to toggle on a machine without one")

        T.eq([K.fraction(0, 2), K.fraction(1, 2), K.fraction(2, 2)], [0, 0.5, 1], "the fraction the OSD animates")
        T.eq(K.fraction(1, 0), 0, "and no division by a maximum of nothing")

        // A value that is not a whole number is *no answer*, and no answer is
        // not zero: a keyboard whose light is off must not read as a keyboard
        // that has none, or the OSD would appear on machines without one.
        T.eq([K.parseLevel("2"), K.parseLevel("0"), K.parseLevel(" 1\n")], [2, 0, 1], "a sysfs brightness file")
        T.eq([K.parseLevel(""), K.parseLevel(null), K.parseLevel("x"), K.parseLevel("-1")],
             [null, null, null, null], "anything else is no answer, not off")

        // The driver prefix differs per machine, so the name is matched on its
        // tail and never spelled out.
        T.eq(K.deviceFrom("input3::capslock\ntpacpi::kbd_backlight\nplatform::mute\n"), "tpacpi::kbd_backlight", "ThinkPad")
        T.eq(K.deviceFrom("asus::kbd_backlight\n"), "asus::kbd_backlight", "and any other driver")
        T.eq(K.deviceFrom("input3::capslock\nplatform::mute\n"), "", "a machine with no keyboard light")
        T.eq(K.deviceFrom(""), "", "and an empty listing")
        T.eq(K.deviceFrom("dell::kbd_backlight_x\n"), "", "a name that merely contains it is not it")

        T.finish("KbdBacklightTest")
    }
}
