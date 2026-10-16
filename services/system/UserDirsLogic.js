.pragma library

// ~/.config/user-dirs.dirs, written by xdg-user-dirs-update in shell syntax:
//   XDG_PICTURES_DIR="$HOME/Bilder"
// The wallpaper's default folder and the start menu's places read it. Unit
// tested (WallpaperTest, StartMenuTest).

// The directory one key names (PICTURES, DOWNLOAD, DOCUMENTS …), "" when the
// file does not say. Only the $HOME form and absolute paths are taken;
// anything else is not ours to evaluate. A bare $HOME is how the file turns a
// directory off.
function userDir(text, key, home) {
    if (!/^[A-Z]+$/.test(String(key || ""))) return ""
    const pattern = new RegExp("^\\s*XDG_" + key + "_DIR\\s*=\\s*\"([^\"\\n]*)\"\\s*$", "m")
    const match = pattern.exec(String(text || ""))
    if (!match) return ""
    const value = match[1]
    if (value.indexOf("$HOME/") === 0) return String(home || "") + value.slice(5)
    if (value === "$HOME") return ""
    return value.charAt(0) === "/" ? value : ""
}
