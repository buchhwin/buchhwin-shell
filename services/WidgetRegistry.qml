pragma Singleton
import Quickshell
import QtQuick
import qs.theme

// Widget catalogue: adding a widget means one QML file in shell/widgets and
// one entry here. Unavailable entries appear disabled in the picker. Every
// available widget can also be a pill bar item; pillDisplay is its default
// look there ("icon" or "full"). `action` is the panel a click opens: the
// clock opens the dashboard, most others their own popup (shell/popups).
//
// Three flags for the dock's own pieces: `dockOnly` (nowhere but the dock -
// not in availableTypes, refused by LayoutService elsewhere), `once` (one on
// the dock is enough: a second Apps drew every app twice, and two start
// buttons shared one place to open the menu from) and `pillSized: false` (it
// sizes itself, so the editor offers no item size for it).
Singleton {
    readonly property var categories: [
        { id: "time", label: "Time" },
        { id: "system", label: "System" },
        { id: "desktop", label: "Desktop" },
        { id: "media", label: "Media" },
        { id: "information", label: "Information" },
        { id: "optional", label: "Optional" },
        // The dock's own pieces: offered only while the editor edits the dock.
        { id: "dock", label: "Dock", dockOnly: true }
    ]

    readonly property var allStyles: ["minimal", "capsule", "card"]

    readonly property var types: ({
        // The dock's own (shell/dock/Dock.qml): the pinned and running apps,
        // and a start button with the fastfetch Saturn that opens the start
        // menu (shell/startmenu), or the launcher (`dock.startOpens`, see
        // actionOf). Not offered on the desktop or the bar - the apps need the
        // dock's surface around them.
        // The apps take their size from Settings > Dock (dock.iconSize).
        "apps": { label: "Apps", icon: Icons.window, category: "dock", dockOnly: true, once: true, pillSized: false,
                  pillDisplay: "full", pillDisplays: ["full"], file: "AppsWidget.qml", sizes: ["small"], action: "",
                  available: true, noHighlight: true, defaults: {} },
        "start": { label: "Start button", icon: Icons.apps, category: "dock", dockOnly: true, once: true, pillDisplay: "icon",
                   file: "StartWidget.qml", sizes: ["small", "medium", "large"], action: "startMenu", available: true,
                   defaults: {} },
        "clock": { label: "Clock", icon: "󰥔", category: "time", file: "ClockWidget.qml",
                   sizes: ["small", "medium", "large"], action: "dashboard", available: true,
                   defaults: { anchorX: "right", x: 0.985, y: 0.02, size: "small", style: "minimal" } },
        "date": { label: "Date", icon: "󰃭", category: "time", file: "DateWidget.qml",
                  sizes: ["small", "medium", "large"], action: "dashboard", available: true,
                  defaults: { anchorX: "right", x: 0.985, y: 0.1, size: "small", style: "minimal" } },
        "battery": { label: "Battery", icon: "󰁹", category: "system", file: "BatteryWidget.qml",
                     sizes: ["small", "medium", "large"], action: "batteryPopup", available: true,
                     defaults: { anchorX: "right", x: 0.93, y: 0.02, style: "capsule" } },
        "network": { pillDisplay: "icon", label: "Network", icon: "󰤨", category: "system", file: "NetworkWidget.qml",
                     sizes: ["small", "medium"], action: "networkPopup", available: true,
                     defaults: { anchorX: "right", x: 0.9, y: 0.02, style: "capsule" } },
        "bluetooth": { pillDisplay: "icon", label: "Bluetooth", icon: "󰂯", category: "system", file: "BluetoothWidget.qml",
                       sizes: ["small", "medium", "large"], action: "bluetoothPopup", available: true,
                       defaults: { anchorX: "right", x: 0.88, y: 0.02, style: "capsule" } },
        "volume": { label: "Volume", icon: "󰕾", category: "system", file: "VolumeWidget.qml",
                    sizes: ["small", "medium", "large"], action: "volumePopup", available: true,
                    defaults: { anchorX: "right", x: 0.86, y: 0.02, style: "capsule" } },
        "vpn": { pillDisplay: "icon", label: "VPN", icon: "󰖂", category: "system", file: "VpnWidget.qml",
                 sizes: ["small", "medium"], action: "vpnPopup", available: true,
                 defaults: { anchorX: "right", x: 0.84, y: 0.02, style: "capsule" } },
        "workspace": { label: "Workspace", icon: Icons.arrange, category: "desktop", file: "WorkspaceWidget.qml",
                       sizes: ["small"], action: "", available: true,
                       defaults: { anchorX: "left", x: 0.015, y: 0.02, style: "capsule" } },
        "activeWindow": { label: "Active window", icon: "󰖯", category: "desktop", file: "ActiveWindowWidget.qml",
                          sizes: ["small", "medium", "large"], action: "", available: true,
                          defaults: { anchorX: "center", x: 0.5, y: 0.02, style: "minimal" } },
        "notificationIndicator": { pillDisplay: "icon", label: "Notifications", icon: "󰂚", category: "desktop",
                                   file: "NotificationIndicatorWidget.qml", sizes: ["small", "medium", "large"],
                                   action: "notifications", available: true,
                                   defaults: { anchorX: "right", x: 0.82, y: 0.02, style: "capsule" } },
        "privacy": { pillDisplay: "icon", label: "Privacy", icon: "󰍬", category: "system", file: "PrivacyWidget.qml",
                     sizes: ["small", "medium"], action: "privacyPopup", available: true,
                     defaults: { anchorX: "right", x: 0.8, y: 0.02, style: "capsule" } },
        // Only visible while recording; a click stops it. The pill bar shows it
        // on its own when no pill contains it.
        "recording": { label: "Screen recording", icon: "󰑊", category: "system", file: "RecordingWidget.qml",
                       sizes: ["small"], action: "", available: true,
                       defaults: { anchorX: "right", x: 0.78, y: 0.02, style: "capsule" } },
        "nowPlaying": { pillDisplay: "icon", pillDisplays: ["icon", "full", "expanded"], label: "Playback", icon: "󰎆", category: "media", file: "NowPlayingWidget.qml",
                        sizes: ["small", "medium"], action: "mediaPopup", available: true,
                        defaults: { anchorX: "left", x: 0.015, y: 0.9, style: "card" } },
        "weather": { label: "Weather", icon: "󰖐", category: "information", file: "WeatherWidget.qml",
                     sizes: ["small", "medium"], action: "weatherPopup", available: true,
                     defaults: { anchorX: "right", x: 0.985, y: 0.12, style: "card" } },
        "calendarSummary": { label: "Events", icon: "󰸗", category: "information", file: "CalendarWidget.qml",
                             sizes: ["small", "medium"], action: "eventsPopup", available: true,
                             defaults: { anchorX: "right", x: 0.985, y: 0.14, style: "card" } },
        "cpu": { label: "CPU", icon: "󰻠", category: "optional", file: "SystemStatWidget.qml",
                 sizes: ["small", "medium"], action: "systemPopup", available: true, options: { metric: "cpu" },
                 defaults: { anchorX: "left", x: 0.015, y: 0.95, style: "capsule" } },
        "ram": { label: "RAM", icon: "󰍛", category: "optional", file: "SystemStatWidget.qml",
                 sizes: ["small", "medium", "large"], action: "systemPopup", available: true, options: { metric: "ram" },
                 defaults: { anchorX: "left", x: 0.08, y: 0.95, style: "capsule" } },
        "colorPicker": { label: "Color picker", icon: "󰈊", category: "optional", file: "ColorPickerWidget.qml",
                         sizes: ["small", "medium", "large"], action: "colorPicker", available: true,
                         defaults: { anchorX: "left", x: 0.22, y: 0.95, style: "capsule" } },
        "disk": { label: "Disk", icon: "󰋊", category: "optional", file: "SystemStatWidget.qml",
                  sizes: ["small", "medium", "large"], action: "systemPopup", available: true, options: { metric: "disk" },
                  defaults: { anchorX: "left", x: 0.15, y: 0.95, style: "capsule" } },
        // A way into the control center that is not a keyboard shortcut, and a
        // readout of what is on while it is closed.
        "quickPanel": { pillDisplay: "icon", label: "Control center", icon: "󰕮", category: "desktop",
                        file: "QuickPanelWidget.qml", sizes: ["small", "medium", "large"],
                        action: "controlCenter", available: true,
                        defaults: { anchorX: "right", x: 0.76, y: 0.02, style: "capsule" } },
        // `actionArgs` opens Settings on the updates page rather than at the
        // top of a list of twenty.
        "updates": { label: "Updates", icon: "󰚰", category: "optional", file: "UpdatesWidget.qml",
                     sizes: ["small", "medium", "large"], action: "settings", actionArgs: { page: "updates" },
                     available: true,
                     defaults: { anchorX: "left", x: 0.29, y: 0.95, style: "capsule" } }
    })

    function type(name) {
        return types[name] || null
    }

    // The panel a click on a widget of this type opens. The table's own
    // `action`, but for the start button, which follows Settings > Dock >
    // Start button: read here rather than written into `types`, which every
    // pill reads its entry from - a change would re-evaluate them all.
    function actionOf(name) {
        const entry = types[name]
        if (!entry) return ""
        if (name === "start") return SettingsService.value("dock.startOpens") === "launcher" ? "launcher" : "startMenu"
        return entry.action
    }

    function isAvailable(name) {
        const entry = types[name]
        return entry !== undefined && entry.available && entry.file.length > 0
    }

    function source(name) {
        const entry = types[name]
        return entry && entry.file.length ? Qt.resolvedUrl("../shell/widgets/" + entry.file) : ""
    }

    // Pill looks offered in the bar editor, with labels.
    function pillDisplays(name) {
        const entry = types[name]
        const values = entry && entry.pillDisplays ? entry.pillDisplays : ["icon", "full"]
        const media = values.indexOf("expanded") >= 0
        const labels = { icon: media ? "Compact" : "Icon", full: media ? "Title" : "Full", expanded: "Expanded" }
        return values.map(value => ({ value: value, label: labels[value] }))
    }

    // The dock's own pieces only for a caller that asks for them: every
    // picker but the layout editor's dock one (which lists by category) puts
    // a widget somewhere else - an Apps widget there is empty and a start
    // button opens nothing.
    function availableTypes(includeDockOnly) {
        return Object.keys(types).filter(name => isAvailable(name) && (includeDockOnly === true || !types[name].dockOnly))
            .map(name => Object.assign({ name: name }, types[name]))
    }

    function isDockOnly(name) {
        const entry = types[name]
        return entry !== undefined && entry.dockOnly === true
    }
    function isOnce(name) {
        const entry = types[name]
        return entry !== undefined && entry.once === true
    }
    // Whether the editor's Item size means anything for it.
    function pillSized(name) {
        const entry = types[name]
        return entry === undefined || entry.pillSized !== false
    }

    function typesIn(category) {
        return Object.keys(types).filter(name => types[name].category === category)
            .map(name => Object.assign({ name: name }, types[name]))
    }
}
