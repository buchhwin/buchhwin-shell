import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/launcher/ModeOrder.js" as Order

// The launcher's mode order, from every shape a stored string can be in. A
// nested session can show that the switch is in some order; it cannot show what
// happens to a stored order when a mode is added, removed or named twice, and
// that is the part that can lose a mode for good.
ShellRoot {
    readonly property var all: ["apps", "commands", "settings", "calculator", "web", "emoji", "files"]

    Component.onCompleted: {
        // ---- nothing stored --------------------------------------------------
        T.eq(Order.order("", all), all, "no order stored is the shell's own")
        T.eq(Order.order(null, all), all, "and so is none at all")
        T.eq(Order.order("apps,commands", []), [], "with no modes there is nothing to order")

        // ---- a stored order --------------------------------------------------
        T.eq(Order.order("web,emoji,apps", all),
             ["apps", "web", "emoji", "commands", "settings", "calculator", "files"],
             "what the string names comes first, the rest keeps the shell's order behind it")
        T.eq(Order.order(" web , emoji ", all)[1], "web", "spaces around a name do not make a new one")

        // ---- what must not be lost -------------------------------------------
        // A mode the string predates has to appear anyway, or a mode added in a
        // later version is invisible to everyone who ever reordered theirs.
        T.eq(Order.order("apps,commands,settings,calculator,web,emoji", all).indexOf("files"), 6,
             "a mode the stored order never heard of is still there, at the end")
        T.eq(Order.order("apps,nonsense,web", all).indexOf("nonsense"), -1,
             "a name the shell does not know is dropped rather than left as a hole")
        T.eq(Order.order("web,web,apps", all).filter(name => name === "web").length, 1,
             "a name twice is one mode")
        T.ok(all.every(name => Order.order("emoji", all).indexOf(name) >= 0),
             "whatever is stored, every mode the shell has is in the result")
        T.eq(Order.order("apps,commands", ["apps", "commands"]), ["apps", "commands"],
             "a shorter list of modes is not padded with ones that do not exist")

        // ---- apps leads ------------------------------------------------------
        // It is the mode with no prefix, the one the launcher opens in. A
        // launcher whose first mode needs a prefix opens showing nothing.
        T.eq(Order.order("web,apps", all)[0], "apps", "apps leads, wherever the string put it")
        T.eq(Order.order("files,web,emoji", all)[0], "apps", "and even when the string does not name it")

        // ---- moving one ------------------------------------------------------
        const moved = Order.move("", all, "emoji", -1)
        T.eq(Order.order(moved, all),
             ["apps", "commands", "settings", "calculator", "emoji", "web", "files"],
             "a mode moves one place up")
        T.eq(Order.order(Order.move(moved, all, "emoji", 1), all), all, "and back down again")
        T.eq(Order.order(Order.move("", all, "commands", -1), all), all,
             "nothing moves above apps")
        T.eq(Order.order(Order.move("", all, "files", 1), all), all,
             "nor below the last one")
        T.eq(Order.order(Order.move("", all, "apps", 1), all), all, "and apps does not move at all")
        T.eq(Order.order(Order.move("", all, "nonsense", 1), all), all,
             "a mode that is not there moves nowhere")

        T.ok(!Order.canMove("", all, "apps", -1) && !Order.canMove("", all, "apps", 1),
             "so the buttons beside apps are both off")
        T.ok(!Order.canMove("", all, "commands", -1), "and the one above the first movable mode")
        T.ok(Order.canMove("", all, "commands", 1) && Order.canMove("", all, "files", -1),
             "while the ones that would do something are on")

        // ---- the objects, not just the names ---------------------------------
        const modes = all.map(id => ({ id: id, label: id.toUpperCase() }))
        T.eq(Order.apply("web,apps", modes).map(mode => mode.label),
             ["APPS", "WEB", "COMMANDS", "SETTINGS", "CALCULATOR", "EMOJI", "FILES"],
             "apply keeps the whole mode, in the order")
        T.eq(Order.apply("", []), [], "and nothing out of nothing")

        T.finish("ModeOrderTest")
    }
}
