.pragma library

// The commands Settings > Login screen hands out to be pasted into a terminal
// and run with sudo. They are text for a shell, so every path in them is one
// word for it, whatever the file is called: a wallpaper named "Tom's
// beach.jpg" left the old command an unterminated quote, and a name with
// `'; …; '` in it added commands of its own - run as root, on the password
// the first sudo had just been given.

// One word for sh, bash or zsh: bare when it holds nothing a shell reads
// specially, else in single quotes, with each quote in it closed, escaped and
// opened again. Inside single quotes `$`, backquotes, `\` and `!` are plain
// characters in all three, and so is a newline. A leading `=` is zsh's path
// lookup (`=ls`), so such a word is quoted too.
function shellWord(text) {
    const value = String(text === undefined || text === null ? "" : text)
    if (/^[A-Za-z0-9_\/.,:@%+-][A-Za-z0-9_\/.,:=@%+-]*$/.test(value)) return value
    return "'" + value.replace(/'/g, "'\\''") + "'"
}

// The wallpaper always in quotes, as the page has always shown it, so the
// line reads the same for an ordinary name as before.
function quoted(text) {
    return "'" + String(text === undefined || text === null ? "" : text).replace(/'/g, "'\\''") + "'"
}

// The installer by its absolute path (Paths.shellFile): a terminal opens in
// the home directory, where "install/system-install.sh" is not found, and
// pasted elsewhere a relative name runs whatever file of that name the
// directory holds. The script finds its own tree from its path, so it works
// from anywhere.
function installCommand(scriptPath, wallpaper) {
    const picture = String(wallpaper === undefined || wallpaper === null ? "" : wallpaper)
    return "sudo " + shellWord(scriptPath) + " --sddm-theme"
        + (picture.length ? " --wallpaper " + quoted(picture) : "")
}

// The way back, in the same form: the previous theme and display manager.
function removeCommand(scriptPath) {
    return "sudo " + shellWord(scriptPath) + " --sddm-theme-remove"
}
