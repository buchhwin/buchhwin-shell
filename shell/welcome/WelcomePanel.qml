import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// The short tour on the first start: what this desktop is, and the six keys
// that open everything else. It shows itself once (`onboarding.completed`) and
// can be opened again from Settings > About.
//
// Every step names a real key, and "Try it" runs it, so the tour teaches by
// doing rather than by describing. Only one shell panel is open at a time, so
// "Try it" steps aside through PanelService.openOver: closing what it opened
// brings the tour back on the step it left. Dismissing the tour counts as done,
// but stepping aside is not dismissing it.
ShellPanel {
    id: root
    panelId: "welcome"
    placement: "center"
    cardWidth: Metrics.welcomeWidth
    scrimColor: Colors.scrimStrong

    property int step: 0
    // True while the tour has opened something to show it off. The panel closing
    // then is not the user dismissing the tour, and PanelService brings it back.
    property bool steppingAside: false
    readonly property var steps: [
        {
            icon: "󰋜", title: "Welcome",
            text: "This is buchhwin-shell. There is no menu bar, and the dock is off until you want it: everything has a key, and every key opens the same thing every time.",
            keys: [], action: ""
        },
        {
            icon: Icons.search, title: "Find anything",
            text: "The launcher starts apps, opens settings pages, does arithmetic and searches the web. Type ? for the web, = to calculate, @ for a settings page.",
            keys: ShortcutService.keyHintParts("SUPER + D"), action: "launcher"
        },
        {
            icon: "󰕾", title: "Turn things on and off",
            text: "Wi-Fi, Bluetooth, brightness, sound, battery. “Arrange tiles” in its header puts them where you want them.",
            keys: ShortcutService.keyHintParts("SUPER + O"), action: "controlCenter"
        },
        {
            icon: "󰃭", title: "Time and weather",
            text: "The dashboard has the month, the weather and the events of your KDE calendars. “+” creates an event, and a series can be changed one occurrence at a time.",
            keys: ShortcutService.keyHintParts("SUPER + K"), action: "dashboard", asksPlace: true
        },
        {
            icon: Icons.arrange, title: "Make it yours",
            text: "The layout editor arranges the desktop: widgets on the wallpaper, a bar of pills at the top, or a notch. Drag what you see, where you see it.",
            keys: ShortcutService.keyHintParts("SUPER + ALT + E"), action: "editor"
        },
        {
            icon: "󰥻", title: "Everything else",
            text: ShortcutService.keyHint("SUPER + F1", true) + " lists every shortcut, " + ShortcutService.keyHint("SUPER + I", true)
                + " opens Settings. Nothing here is hidden behind a menu you have to find first.",
            keys: ShortcutService.keyHintParts("SUPER + F1"), action: "shortcuts"
        }
    ]
    readonly property var current: steps[Math.max(0, Math.min(steps.length - 1, step))]
    readonly property bool last: step >= steps.length - 1

    onWantedChanged: if (wanted) {
        step = Number(PanelService.args.step) || 0
        steppingAside = false
    }

    // It shows itself once, a few seconds after the shell settled: at startup
    // it would fight the wallpaper and the widgets for the first frame, and a
    // panel that appears over something the user already opened is rude.
    // `repeat` so the timer does not clear its own `running` when it fires: a
    // non-repeating one does, which tears down the binding below for good. It
    // fires while a panel the user opened is in front, decides not to
    // interrupt, and then can never come back - the onboarding is gone for the
    // rest of the session. Repeating, it simply waits for the panel to close,
    // and `onboarding.completed` is what stops it for good.
    Timer {
        repeat: true
        interval: Animations.welcomeDelay
        running: AppearanceService.realSession && SettingsService.loaded
            && !SettingsService.value("onboarding.completed")
        onTriggered: if (!PanelService.active.length) PanelService.open("welcome")
    }
    // Closing it counts as done, however it was closed - but stepping aside to
    // demonstrate a step is not closing it.
    onShownChanged: if (!shown && !steppingAside) SettingsService.set("onboarding.completed", true)

    function next() {
        if (last) {
            SettingsService.set("onboarding.completed", true)
            PanelService.close("welcome")
            return
        }
        step += 1
    }

    // The weather needs a place, and finding it from the connection asks a
    // third party (ipinfo.io), which sees this computer's address. That is
    // the user's call: the tour asks, where the shell used to ask ipinfo.io
    // by itself at the first start. A place already set is never asked about.
    readonly property bool asksPlace: current.asksPlace === true && WeatherService.enabled
        && (!WeatherService.hasLocation || placeFound)
    // Found or chosen during this tour: the step says so rather than going
    // quiet.
    property bool placeFound: false
    Connections {
        target: WeatherService
        function onHasLocationChanged() {
            if (WeatherService.hasLocation && (root.wanted || root.steppingAside)) root.placeFound = true
        }
    }
    // Asked from here, so a failure is this step's to show.
    property bool locating: false
    function findPlace() {
        locating = true
        LocationService.detectByIp()
    }
    function chooseCity() {
        steppingAside = true
        PanelService.openOver("settings", { page: "weather" }, { step: root.step })
    }

    function tryIt() {
        const action = current.action
        if (!action.length) return
        steppingAside = true
        // The layout editor is not a panel - it owns the screen and its own
        // keyboard focus - so the tour waits for edit mode to end instead of
        // handing PanelService a return address.
        if (action === "editor") {
            PanelService.close("welcome")
            LayoutService.editMode = true
            return
        }
        PanelService.openOver(action === "shortcuts" ? "shortcutSheet" : action,
                              {}, { step: root.step })
    }

    // The way back from the layout editor, which has no return address.
    Connections {
        target: LayoutService
        function onEditModeChanged() {
            if (!LayoutService.editMode && root.steppingAside)
                PanelService.open("welcome", { step: root.step })
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.panelGap

        PanelHeader {
            Layout.fillWidth: true
            icon: root.current.icon
            title: root.current.title
            subtitle: "Step " + (root.step + 1) + " of " + root.steps.length
        }

        CardSection {
            Layout.fillWidth: true

            ShellText {
                Layout.fillWidth: true
                text: root.current.text
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.current.keys.length > 0
                spacing: Metrics.spaceSm
                KeyChips { keys: root.current.keys; accent: true }
                ShellButton {
                    focusOnTab: true
                    text: "Try it"
                    variant: "surface"
                    compact: true
                    onClicked: root.tryIt()
                }
                Item { Layout.fillWidth: true }
            }

            ShellText {
                Layout.fillWidth: true
                visible: root.asksPlace
                text: WeatherService.hasLocation ? "Weather for " + WeatherService.locationName + "."
                    : LocationService.detecting ? "Asking ipinfo.io …"
                    : "The weather needs a place. Find it from this connection? That asks ipinfo.io once, which sees this computer's IP address. Or choose a city yourself."
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }
            ShellText {
                Layout.fillWidth: true
                visible: root.asksPlace && !WeatherService.hasLocation && !LocationService.detecting
                    && LocationService.detectError.length > 0 && root.locating
                text: LocationService.detectError
                role: "small"
                color: Colors.warning
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.asksPlace && !WeatherService.hasLocation
                spacing: Metrics.spaceSm
                ShellButton {
                    focusOnTab: true
                    icon: Icons.location
                    text: "Find my place"
                    compact: true
                    enabledState: !LocationService.detecting
                    onClicked: root.findPlace()
                }
                ShellButton {
                    focusOnTab: true
                    text: "Choose a city …"
                    variant: "ghost"
                    compact: true
                    onClicked: root.chooseCity()
                }
                Item { Layout.fillWidth: true }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm

            // One dot per step, so the tour says how long it is.
            Repeater {
                model: root.steps.length
                Rectangle {
                    required property int index
                    implicitWidth: Metrics.dotSize
                    implicitHeight: Metrics.dotSize
                    radius: width / 2
                    // The track, as a slider's groove: a hairline's border colour
                    // left the other steps all but invisible.
                    color: index === root.step ? Colors.accentFill : Colors.track
                }
            }

            Item { Layout.fillWidth: true }

            ShellButton {
                focusOnTab: true
                text: "Skip"
                variant: "ghost"
                visible: !root.last
                onClicked: root.requestClose()
            }
            ShellButton {
                icon: root.last ? Icons.check : Icons.forward
                text: root.last ? "Done" : "Next"
                variant: "accent"
                focusOnTab: true
                onClicked: root.next()
            }
        }
    }
}
