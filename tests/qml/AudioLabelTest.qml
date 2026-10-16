import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/audio/AudioLabelLogic.js" as L

// AudioLabelLogic: a device's name split into the port (the row's title) and
// the card (the line under it). The names are the ones PipeWire gives this
// laptop's ALSA card, which only differ in their last words.
ShellRoot {
    Component.onCompleted: {
        const card = "Ryzen HD Audio Controller"
        T.eq(L.split(card + " Speaker", "Speaker", []), { title: "Speaker", subtitle: card },
             "the port PipeWire appended is the title, even for the only output")
        T.eq(L.split(card + " Digital Microphone", "", [card + " Stereo Microphone"]),
             { title: "Digital Microphone", subtitle: card },
             "without a port, the words shared with another device of the list are the card")
        T.eq(L.split(card + " Stereo Microphone", "", [card + " Digital Microphone", "USB Headset Mono"]),
             { title: "Stereo Microphone", subtitle: card }, "the longest share with any other device counts")
        T.eq(L.split("WH-1000XM4", "Headset", ["Ryzen HD Audio Controller Speaker"]), { title: "WH-1000XM4", subtitle: "" },
             "a port the label does not end with, and nothing shared: the label stays whole")
        T.eq(L.split("Speaker", "Speaker", []), { title: "Speaker", subtitle: "" }, "a label that is only the port stays whole")
        T.eq(L.split(card, "", [card + " Speaker"]), { title: card, subtitle: "" },
             "a label that is all card stays whole rather than leaving no title")
        T.eq(L.split("Twin Headset", "", ["Twin Headset"]), { title: "Twin Headset", subtitle: "" },
             "two devices of the same name: nothing to tell them apart by, the whole name")
        T.eq(L.split("  " + card + "   Speaker ", " Speaker", []), { title: "Speaker", subtitle: card }, "spaces do not matter")
        T.eq(L.split("", "", []), { title: "", subtitle: "" }, "nothing")
        T.eq(L.sharedWords(["a", "b", "c"], ["a", "b", "d"]), 2, "shared leading words")

        // One line beside a state: the port where the card goes without
        // saying (this laptop's two microphones), else the whole name.
        T.eq(L.shortName(card + " Digital Microphone", "Digital Microphone", [card + " Stereo Microphone"]), "Digital Microphone",
             "a microphone beside another of its card: the port")
        T.eq(L.shortName("Jabra Evolve2 65 Mono", "Mono", [card + " Digital Microphone", card + " Stereo Microphone"]),
             "Jabra Evolve2 65 Mono", "a headset whose port is only its profile: its whole name, not 'Mono'")
        T.eq(L.shortName(card + " Digital Microphone", "Digital Microphone", []), "Digital Microphone",
             "the only input: nothing to tell it from, the port")
        T.eq(L.shortName(card + " Digital Microphone", "Digital Microphone", ["Jabra Evolve2 65 Mono"]), card + " Digital Microphone",
             "beside another card's device only: the whole name")
        T.eq(L.shortName(card + " Digital Microphone", "", [card + " Stereo Microphone"]), "Digital Microphone",
             "without a port, by the words shared with the other microphone")
        T.eq(L.shortName("WH-1000XM4", "", [card + " Speaker"]), "WH-1000XM4", "nothing to shorten")
        T.finish("AudioLabelTest")
    }
}
