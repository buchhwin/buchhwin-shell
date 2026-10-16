import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/media/MediaLogic.js" as M

// The media popup's and the media card's arithmetic: a length that is a real
// one (a live stream has none, or INT64_MAX µs), the times drawn beside the
// seek bar, and how many player chips fit in one row.
ShellRoot {
    Component.onCompleted: {
        // ---- a real length ------------------------------------------------
        T.eq(M.realLength(true, 245.5), 245.5, "a track's length")
        T.eq(M.realLength(true, 9223372036854.775), 0, "INT64_MAX µs is a live stream, not a length")
        T.eq(M.realLength(true, 0), 0, "zero is no length")
        T.eq(M.realLength(true, -1), 0, "a negative length is none")
        T.eq(M.realLength(true, NaN), 0, "not a number")
        T.eq(M.realLength(true, undefined), 0, "missing")
        T.eq(M.realLength(false, 245), 0, "a length the player does not support means nothing")
        T.eq(M.realLength(true, 3 * 3600), 10800, "a three-hour recording is still a track")
        T.ok(M.realLength(true, M.MAX_LENGTH - 1) > 0 && M.realLength(true, M.MAX_LENGTH) === 0, "the ceiling is ~115 days")

        // ---- times --------------------------------------------------------
        T.eq(M.formatTime(0), "0:00", "zero")
        T.eq(M.formatTime(59.9), "0:59", "seconds are floored")
        T.eq(M.formatTime(61), "1:01", "m:ss")
        T.eq(M.formatTime(3599), "59:59", "under an hour")
        T.eq(M.formatTime(3600), "1:00:00", "an hour is h:mm:ss")
        T.eq(M.formatTime(3725), "1:02:05", "h:mm:ss with padded minutes")
        T.eq(M.formatTime(300, 5400), "0:05:00", "the elapsed time of a long track keeps its shape")
        T.eq(M.formatTime(5100, 5400), "1:25:00", "and so does the remaining one")
        T.eq(M.formatTime(300, 245), "5:00", "a short track stays m:ss")
        T.eq([M.formatTime(-5), M.formatTime(NaN), M.formatTime(undefined)], ["0:00", "0:00", "0:00"], "nothing sensible is zero")

        // ---- player chips -------------------------------------------------
        T.eq(M.chipsThatFit([60, 70], 200, 4, 30), 2, "two chips that fit side by side")
        T.eq(M.chipsThatFit([60, 70], 134, 4, 30), 2, "exactly the room")
        T.eq(M.chipsThatFit([60, 70], 133, 4, 30), 1, "one short: the first and the +N chip")
        T.eq(M.chipsThatFit([60, 70, 80], 168, 4, 30), 2, "three players, two fit beside +1")
        T.eq(M.chipsThatFit([60, 70, 80], 167, 4, 30), 1, "the +N chip takes its room first")
        T.eq(M.chipsThatFit([300], 200, 4, 30), 0, "a chip wider than the row leaves only +N")
        T.eq(M.chipsThatFit([], 200, 4, 30), 0, "no players")
        T.eq(M.chipsThatFit([60, 70], 0, 4, 30), 0, "no room yet")

        // The "+N" chip walks the players the row has no room for.
        T.eq(M.nextHiddenIndex(4, 4, 0), -1, "nothing hidden")
        T.eq(M.nextHiddenIndex(4, 2, 0), 2, "the first hidden one while a shown one plays")
        T.eq(M.nextHiddenIndex(4, 2, 2), 3, "then the next")
        T.eq(M.nextHiddenIndex(4, 2, 3), 2, "and round again")
        T.eq(M.nextHiddenIndex(3, 0, -1), 0, "no active player: the first")

        // ---- cover art: what MprisService does with a url -----------------
        // Schemes in any case (security#2: "HTTPS://" went past curl to Qt's
        // own network stack); any other scheme is no cover at all.
        T.eq(["https://cdn.example/a.jpg", "HTTPS://cdn.example/a.jpg", "Http://cdn.example/a.jpg"].map(M.artKind),
             ["remote", "remote", "remote"], "http(s) in any case is fetched by curl")
        T.eq(["file:///tmp/a.png", "FILE:///tmp/a.png"].map(M.artKind), ["file", "file"], "a path in any case is checked")
        T.eq(["data:image/png;base64,AAAA", "DATA:image/png;base64,AAAA"].map(M.artKind), ["data", "data"],
             "an inline picture is handed on")
        T.eq(["ftp://cdn.example/a.jpg", "gopher://x/a", "qrc:/a.png", "/tmp/a.png", "", null, undefined].map(M.artKind),
             ["none", "none", "none", "none", "none", "none", "none"], "every other scheme, a bare path or nothing is no cover")
        T.eq(M.artPath("file:///tmp/My%20Cover.png"), "/tmp/My Cover.png", "a path is decoded")
        T.eq(M.artPath("FILE:///tmp/a.png"), "/tmp/a.png", "in any case")
        T.eq(M.artPath("file:///tmp/100%.png"), "/tmp/100%.png", "a bare % stays as it is")
        T.eq([M.artPath("https://x/a.png"), M.artPath("")], ["", ""], "only a file url has a path")
        T.eq(M.artFileUrl("FILE:///tmp/a%20b.png"), "file:///tmp/a%20b.png", "a checked file is handed out in lower case, still encoded")
        T.eq(M.artFileUrl("https://x/a.png"), "", "and nothing else is")

        T.finish("MediaTest")
    }
}
