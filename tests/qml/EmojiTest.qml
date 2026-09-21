import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/emoji/EmojiLogic.js" as E

// Searching the emoji list and remembering what was picked. The list itself is
// config/emoji.json, which is read here as the shell reads it.
ShellRoot {
    FileView {
        id: listFile
        path: Qt.resolvedUrl("../../config/emoji.json").toString().replace("file://", "")
        blockLoading: true
    }

    Component.onCompleted: {
        const data = JSON.parse(listFile.text())
        const list = data.emoji

        // ---- the file ------------------------------------------------------
        T.ok(list.length > 1000, "the list has more than a thousand emoji: " + list.length)
        T.ok(list.every(entry => entry.e.length > 0 && entry.n.length > 0), "every emoji has a name")
        T.ok(list.every(entry => Array.isArray(entry.k)), "every emoji has its search words")
        const groups = data.groups.map(entry => entry.key)
        T.ok(groups.indexOf("recent") === 0, "the recent group comes first")
        T.ok(list.every(entry => groups.indexOf(entry.g) > 0), "every emoji is in a group that exists")
        T.ok(list.some(entry => entry.m === 1), "some emoji take a skin tone")
        T.ok(!list.some(entry => entry.e.indexOf("\u{1F3FB}") >= 0), "no skin-tone copies are in the list")

        // ---- searching -----------------------------------------------------
        const smile = E.search(list, "grinning face", "", 10)
        T.eq(smile[0].n, "grinning face", "an exact name wins")
        T.ok(E.search(list, "smi", "", 5).length > 0, "a prefix finds something")
        T.ok(E.search(list, "cat", "", 50).some(entry => entry.n.indexOf("cat") >= 0), "a word in the middle")
        T.eq(E.search(list, "zzzznothing", "", 10).length, 0, "nothing matches nonsense")
        T.ok(E.search(list, "", "food", 500).every(entry => entry.g === "food"), "a group keeps its own emoji")
        T.ok(E.search(list, "", "food", 500).length > 20, "the food group is not empty")
        T.eq(E.search(list, "grinning", "food", 20).length, 0, "a search stays inside its group")
        T.eq(E.search(list, "grinning face", "", 3).length <= 3, true, "the limit is kept")

        // ---- skin tones ------------------------------------------------------
        const tonable = list.find(entry => entry.m === 1)
        const plain = list.find(entry => entry.m !== 1)
        T.eq(E.withTone(tonable, 0), tonable.e, "tone 0 is the emoji itself")
        T.eq(E.withTone(tonable, 3), tonable.e + "\u{1F3FD}", "a tone is written after the emoji")
        T.eq(E.withTone(plain, 3), plain.e, "an emoji without tones is untouched")
        T.eq(E.withTone(tonable, 99), tonable.e + "\u{1F3FF}", "a tone out of range is the last one")
        T.eq(E.withTone(null, 2), "", "nothing to tone")
        T.eq(E.withoutTone(tonable.e + "\u{1F3FD}"), tonable.e, "the tone comes back off")
        T.eq(E.withoutTone(plain.e), plain.e, "an emoji without one is unchanged")

        // ---- what was used before --------------------------------------------
        T.eq(E.parseRecent(""), [], "no file yet")
        T.eq(E.parseRecent("not json"), [], "a broken file is no file")
        T.eq(E.parseRecent('{"version": 2, "recent": ["x"]}'), [], "another version is ignored")
        T.eq(E.parseRecent('{"version": 1, "recent": ["\u{1F600}", 5, ""]}'), ["\u{1F600}"], "only usable entries")
        T.eq(E.remember([], "\u{1F600}"), ["\u{1F600}"], "the first one")
        T.eq(E.remember(["\u{1F600}", "\u{1F601}"], "\u{1F601}"), ["\u{1F601}", "\u{1F600}"],
             "picking one again moves it to the front instead of repeating it")
        T.eq(E.remember(["\u{1F600}"], ""), ["\u{1F600}"], "nothing to remember")
        let many = []
        for (let index = 0; index < 60; ++index) many = E.remember(many, "e" + index)
        T.eq(many.length, E.MAX_RECENT, "the list stops growing")
        T.eq(many[0], "e59", "the newest is first")
        T.eq(E.parseRecent(E.serializeRecent(["\u{1F600}"])), ["\u{1F600}"], "written and read back")

        const entries = E.recentEntries([tonable.e + "\u{1F3FD}", "\u{1F600}", "not-an-emoji"], list)
        T.eq(entries[0].e, tonable.e + "\u{1F3FD}", "a remembered emoji keeps its tone")
        T.eq(entries[0].n, tonable.n, "and it is named after the one it came from")
        T.ok(entries.every(entry => entry.g === "recent"), "they are all in the recent group")
        T.eq(entries.length, 2, "one that is no longer in the list is dropped")

        T.finish("EmojiTest")
    }
}
