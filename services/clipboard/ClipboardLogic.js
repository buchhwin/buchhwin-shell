.pragma library

// The commands ClipboardService runs on the history's files. Pure functions,
// unit tested in ClipboardPrivacyTest.qml.
//
// The history holds every text and picture copied - a password included when
// the program it came from did not mark it - and cliphist created its database
// with the default mode (0644), the previews' directory 0755: readable by every
// local account wherever the home directory is not private (older openSUSE
// defaults, a shared or NFS home). So both are the user's alone: the recorders
// run under umask 077, which cliphist inherits when it creates the database,
// and a database from before is set to 0600 as they start; the previews'
// directory is made 0700, and what is decoded into it 0600.

// A recorder's argv (or the wipe's, which creates a missing database too),
// run through a shell that sets the mode first and then becomes the command
// itself (exec), so the command line start-shell.sh looks for when it reaps
// helpers stays the recorder's own.
function privately(dbPath, command) {
    return ["sh", "-c", "umask 077; [ -e \"$1\" ] && chmod 600 -- \"$1\"; shift; exec \"$@\"", "sh", dbPath]
        .concat(command)
}

// Decodes previews: pairs of [cliphist id, file name]. A file that is there
// already is kept; one that comes out empty is removed (a failed decode is
// tried again next time); every file that is there afterwards is printed.
function previewsCommand(thumbDir, dbPath, pairs) {
    const args = []
    for (const pair of pairs) args.push(pair[0], pair[1])
    return ["sh", "-c",
        "umask 077; mkdir -p \"$1\" && { chmod 700 \"$1\" || true; } && dir=\"$1\" && db=\"$2\" && shift 2 && while [ $# -gt 1 ]; do [ -s \"$dir/$2\" ] || cliphist -db-path \"$db\" decode \"$1\" > \"$dir/$2\"; if [ -s \"$dir/$2\" ]; then echo \"$2\"; else rm -f \"$dir/$2\"; fi; shift 2; done",
        "sh", thumbDir, dbPath].concat(args)
}
