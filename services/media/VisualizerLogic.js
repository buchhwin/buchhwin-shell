.pragma library

// The media popup's visualizer: bars that move with what is playing, drawn
// from cava's raw output (MprisService runs it, shell/popups/MediaPopup.qml
// draws it). Pure functions, unit tested in VisualizerTest.qml.
//
// Only inside the open media popup, only while something plays, only with
// Settings' switch on and full motion: a surface redrawn on every frame is
// what cost the notch 8-9 late frames per workspace slide once (testing.md
// pitfall 40), so it is never in the notch or the bar, and nothing of it runs
// while the popup is closed. cava itself takes 1-3 % of a CPU while it runs.
//
// cava listens to the default output's monitor through PipeWire - a capture
// stream like a microphone's, which the privacy indicator would count as
// "microphone in use". So the stream carries a name of its own
// (PIPEWIRE_PROPS, which libpipewire reads for every stream it makes), and
// AudioService leaves that name out the way it leaves out Settings' level
// meter.

var NODE_NAME = "buchhwin-shell-visualizer"
var BARS = 24
var FRAMERATE = 30
// cava's raw ASCII output counts each bar from 0 to this.
var RANGE = 100

// cava's configuration: the default output's sound, mono (one row of bars,
// not two mirrored halves), raw numbers on stdout, one frame per line. After
// a second of silence it stops drawing until sound comes back.
function config(bars, framerate) {
    return [
        "[general]",
        "bars = " + (bars || BARS),
        "framerate = " + (framerate || FRAMERATE),
        "sleep_timer = 1",
        "[input]",
        "method = pipewire",
        "source = auto",
        "[output]",
        "method = raw",
        "raw_target = /dev/stdout",
        "data_format = ascii",
        "ascii_max_range = " + RANGE,
        "bar_delimiter = 59",
        "frame_delimiter = 10",
        "channels = mono",
        ""
    ].join("\n")
}

// The stream's properties (PIPEWIRE_PROPS): the name AudioService knows, and
// the words a mixer shows.
function streamProps() {
    return "{ node.name = \"" + NODE_NAME + "\" media.name = \"Visualizer\" application.name = \"buchhwin-shell\" }"
}

// Writes the configuration (under umask 077, to `configPath`) and becomes
// cava. Everything goes in as arguments. cava's own messages are dropped: a
// visualizer that cannot start is bars that do not show, not lines in the
// shell's log; a cava that is not installed ends with 127, which the service
// notes.
function command(configPath, configText) {
    return ["sh", "-c",
        "umask 077; f=$1; mkdir -p -- \"${f%/*}\" && printf '%s' \"$2\" > \"$f\" || exit 1; "
        + "command -v cava >/dev/null 2>&1 || exit 127; "
        + "PIPEWIRE_PROPS=$3; export PIPEWIRE_PROPS; exec cava -p \"$f\" 2>/dev/null",
        "sh", configPath, configText, streamProps()]
}

// One frame ("12;40;7;...;") -> `bars` heights between 0 and 1; a bar the
// line does not have is 0.
function parseFrame(line, bars) {
    const count = bars || BARS
    const values = String(line || "").split(";")
    const result = []
    for (let i = 0; i < count; ++i) {
        const value = Number(values[i])
        result.push(isFinite(value) && values[i] !== undefined && values[i].length ? Math.max(0, Math.min(1, value / RANGE)) : 0)
    }
    return result
}

// Whether cava runs: the popup shows the bars (it counts itself while open
// with the switch on), something plays, and cava was not found missing.
function wanted(trackers, playing, missing) {
    return trackers > 0 && playing === true && missing !== true
}

// Whether the popup shows the bars: the switch, full motion (reduced motion
// keeps them off - they are nothing but motion) and a player.
function shown(setting, motion, hasPlayer) {
    return setting === true && motion === true && hasPlayer === true
}
