pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "terminal/TerminalLogic.js" as Logic

// Settings > Terminal. Generates the Starship prompt (starship.toml), Kitty
// overrides (kitty.conf) and the Fastfetch greeting switch in the shell's
// config directory for terminals started through launch-kitty.sh, reloads
// running Kitty windows in the real session and renders a prompt preview.
Singleton {
    id: root

    readonly property var promptColors: Logic.promptColors
    readonly property var errorColors: Logic.errorColors
    readonly property var timeFormats: Logic.timeFormats
    readonly property var modules: Logic.modules

    readonly property var options: Logic.options(path => SettingsService.value(path))
    readonly property string starshipPath: Paths.configDir + "/starship.toml"
    readonly property string kittyPath: Paths.configDir + "/kitty.conf"
    readonly property string starshipText: Logic.starshipToml(options, SettingsService.accent)
    readonly property string kittyText: Logic.kittyConf(options, SettingsService.accent)
    readonly property string fastfetchText: options.fastfetchOnStart ? "1\n" : "0\n"
    // SettingsService.accent is also the wallpaper accent when that option is on.
    readonly property string fastfetchColorText: Logic.fastfetchColorText(options, SettingsService.accent)
    // cmatrix knows colour names only; cava gets a gradient from the accent.
    readonly property string cmatrixColorText: Logic.cmatrixColorLine(options, SettingsService.accent) + "\n"
    readonly property string cavaConfigText: Logic.cavaConfig(options, SettingsService.accent)
    // Sending signals to Kitty would reach the host's terminals from a nested
    // test session.
    readonly property bool realSession: AppearanceService.realSession

    property string previewText: ""
    property string previewError: ""
    // "builtin" (the distribution's own ASCII logo) or "image". Read from the
    // configuration rather than inferred from an empty path, because "no image
    // chosen" and "the chosen image is gone" are not the same thing to say.
    property string fastfetchLogo: "builtin"
    property string fastfetchImage: ""
    property string fastfetchError: ""
    property bool choosingImage: false
    // Set by the settings page; the preview only runs while it is shown.
    property bool pageOpen: false

    property int filesReady: 0
    readonly property bool ready: SettingsService.loaded && filesReady === 3

    onStarshipTextChanged: writeTimer.restart()
    onKittyTextChanged: writeTimer.restart()
    onFastfetchTextChanged: writeTimer.restart()
    onFastfetchColorTextChanged: writeTimer.restart()
    onReadyChanged: if (ready) writeTimer.restart()
    onPageOpenChanged: if (pageOpen) { refreshPreview(); refreshImage() }
    // Logo width in columns; also removes a stretching height from older configs.
    readonly property int imageSize: Math.max(8, Math.min(60, options.imageSize))
    onImageSizeChanged: if (SettingsService.loaded) sizeProc.running = true
    Connections {
        target: SettingsService
        function onLoadedChanged() { if (SettingsService.loaded) sizeProc.running = true }
    }
    readonly property bool previewGit: options.previewGit
    onPreviewGitChanged: refreshPreview()

    function write() {
        if (!ready) return
        if (starshipFile.text() !== starshipText) starshipFile.setText(starshipText)
        if (fastfetchFile.text() !== fastfetchText) fastfetchFile.setText(fastfetchText)
        if (fastfetchColorFile.text() !== fastfetchColorText) fastfetchColorFile.setText(fastfetchColorText)
        if (cmatrixColorFile.text() !== cmatrixColorText) cmatrixColorFile.setText(cmatrixColorText)
        if (cavaConfigFile.text() !== cavaConfigText) cavaConfigFile.setText(cavaConfigText)
        if (kittyFile.text() !== kittyText) {
            const existed = kittyFile.text().length > 0
            kittyFile.setText(kittyText)
            // Kitty re-reads its config files on SIGUSR1.
            if (existed && realSession) Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"])
        }
        refreshPreview()
    }

    property bool previewPending: false
    function refreshPreview() {
        if (!ready || !pageOpen) return
        if (previewProc.running) previewPending = true
        else previewProc.running = true
    }

    function refreshImage() { imageProc.running = true }

    function useBuiltinLogo() {
        if (choosingImage) return
        builtinProc.running = true
    }

    function chooseImage() {
        if (choosingImage) return
        choosingImage = true
        chooseProc.running = true
    }

    Timer { id: writeTimer; interval: 300; onTriggered: root.write() }

    FileView {
        id: starshipFile
        path: root.starshipPath
        atomicWrites: true
        printErrors: false
        onLoaded: root.filesReady |= 1
        onLoadFailed: root.filesReady |= 1
    }

    FileView {
        id: kittyFile
        path: root.kittyPath
        atomicWrites: true
        printErrors: false
        onLoaded: root.filesReady |= 2
        onLoadFailed: root.filesReady |= 2
    }

    // Read by zsh/.zshrc; "0" turns the greeting off.
    FileView {
        id: fastfetchFile
        path: Paths.configDir + "/fastfetch-on-start"
        atomicWrites: true
        printErrors: false
    }

    // Read by zsh/.zshrc: colour of Fastfetch's labels (--color-keys).
    FileView {
        id: fastfetchColorFile
        path: Paths.configDir + "/fastfetch-color"
        atomicWrites: true
        printErrors: false
    }

    // Read by zsh/.zshrc: cmatrix -C and cava -p.
    FileView {
        id: cmatrixColorFile
        path: Paths.configDir + "/cmatrix-color"
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: cavaConfigFile
        path: Paths.configDir + "/cava.conf"
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: previewProc
        stderr: ErrorLog { label: "TerminalService.previewProc" }
        // A git checkout (the shell itself) shows branch and status.
        command: ["starship", "prompt", "--path", root.options.previewGit ? Quickshell.shellPath("") : Paths.home,
                  "--status", "0", "--jobs", "0", "--terminal-width", "72"]
        environment: ({ STARSHIP_CONFIG: root.starshipPath })
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewText = Logic.ansiToRich(text.replace(/^\n+/, ""))
                root.previewError = text.trim().length ? "" : "Starship is not available"
            }
        }
        onExited: {
            if (!root.previewPending) return
            root.previewPending = false
            running = true
        }
    }

    Process {
        id: sizeProc
        stderr: ErrorLog { label: "TerminalService.sizeProc" }
        command: ["python3", Paths.script("fastfetch-image.py"), "size", String(root.imageSize)]
    }

    Process {
        id: imageProc
        stderr: ErrorLog { label: "TerminalService.imageProc" }
        command: ["python3", Paths.script("fastfetch-image.py"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.fastfetchImage = result.source || ""
                    root.fastfetchLogo = result.kind === "image" ? "image" : "builtin"
                    root.fastfetchError = result.error || ""
                } catch (error) {
                    root.fastfetchError = "Fastfetch configuration unreadable"
                }
            }
        }
    }

    Process {
        id: builtinProc
        stderr: ErrorLog { label: "TerminalService.builtinProc" }
        command: ["python3", Paths.script("fastfetch-image.py"), "builtin"]
        onExited: root.refreshImage()
    }

    Process {
        id: chooseProc
        stderr: ErrorLog { label: "TerminalService.chooseProc" }
        command: ["sh", "-c", "file=$(kdialog --title 'Fastfetch image' --getopenfilename \"$HOME/Pictures\" 'Images (*.png *.jpg *.jpeg *.webp *.bmp)') || exit 0; [ -n \"$file\" ] && python3 \"$1\" set \"$file\"", "sh", Paths.script("fastfetch-image.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length) {
                    try { root.fastfetchError = JSON.parse(text).error || "" } catch (error) {}
                }
            }
        }
        onExited: {
            root.choosingImage = false
            root.refreshImage()
        }
    }
}
