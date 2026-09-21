import Quickshell.Io

// The standard error of a helper process, in the shell log rather than
// nowhere.
//
// Almost every Process in this directory left `stderr` unset or collected it
// into a collector that threw it away, so a helper's traceback vanished and
// all the user ever saw was "Action failed". The shell log is where a session
// is debugged from, and `console.warn` is what reaches it - `console.log` does
// not.
//
// A line at a time rather than a collector: a monitor process runs for the
// whole session, and a collector holds everything until the stream ends, which
// for those is never.
SplitParser {
    id: log
    // Which process this is, so a line in the log says where it came from.
    // Never a title, a path the user typed or anything else private: the name
    // of a helper the shell itself ships.
    property string label: ""
    splitMarker: "\n"
    onRead: data => {
        const line = String(data).trim()
        if (line.length) console.warn("buchhwin-shell:", log.label, "stderr:", line)
    }
}
