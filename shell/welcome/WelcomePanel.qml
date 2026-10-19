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
    // Enter presses Next: the tour opened with nothing focused, and Return
    // only reaches a focused button, so the keyboard had to Tab past Skip
    // first. The panel hands Next the focus on every open, and it keeps it
    // from step to step.
    keyForward: nextButton

    property int step: 0
    // True while the tour has opened something to show it off. The panel closing
    // then is not the user dismissing the tour, and PanelService brings it back.
    property bool steppingAside: false
    readonly property var steps: [
        {
            icon: "󰋜", title: "Welcome",
            text: "This is buchhwin-shell. There is no menu bar, and the dock is off until you want it (" + ShortcutService.keyHint("SUPER + SHIFT + D", true)
                + " turns it on): everything has a key, and every key opens the same thing every time.",
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
            text: "The layout editor arranges the desktop: widgets on the wallpaper, a bar of pills at the top, or a notch. Drag what you see, where you see it. "
                + ShortcutService.keyHint("SUPER + ALT + P", true) + " switches between five modes - minimal, work, gaming, laptop and desk - each a desktop of its own.",
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
    // The words of every step take the height of the longest: the card is
    // centred and its height followed the text, so Next moved up and down
    // under a pointer clicking through the tour (by up to 59 px). Set from
    // the measured texts' own changes, not bound to them: a text lays itself
    // out when its height is first read, and inside a binding that read was
    // reported as a binding loop.
    property real textHeight: 0
    // The place question under the dashboard's keys counts as that step's
    // words here: the step was ~100 px taller than the others while it
    // asked, and Next moved by half that. `bodyHeight` is the most any step
    // needs for its words and the question below its keys (`placeHeight`,
    // with the gaps); the dashboard's words give up what they do not need of
    // it, and the other steps keep the rest free under their keys, where the
    // question would be.
    property real placeHeight: 0
    property real bodyHeight: 0
    function measureSteps() {
        let place = 0
        if (placeAsked) {
            place = section.spacing + placeMeasure.implicitHeight
            if (placeErrorShown) place += section.spacing + placeErrorMeasure.implicitHeight
            if (!WeatherService.hasLocation) place += section.spacing + findButton.implicitHeight
        }
        let words = 0, body = 0
        for (let index = 0; index < measure.count; ++index) {
            const item = measure.itemAt(index)
            if (!item) continue
            words = Math.max(words, item.implicitHeight)
            body = Math.max(body, item.implicitHeight + (steps[index].asksPlace === true ? place : 0))
        }
        placeHeight = place
        textHeight = words
        bodyHeight = Math.max(words, body)
    }
    // Under the keys of a step that does not ask: what the question needs
    // beyond the longest words, less the gap the spacer brings itself.
    readonly property real spareHeight: !asksPlace && bodyHeight - textHeight > section.spacing
        ? bodyHeight - textHeight - section.spacing : 0
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
    readonly property bool placeAsked: WeatherService.enabled && (!WeatherService.hasLocation || placeFound)
    readonly property bool asksPlace: current.asksPlace === true && placeAsked
    onPlaceAskedChanged: Qt.callLater(measureSteps)
    readonly property string placeText: WeatherService.hasLocation ? "Weather for " + WeatherService.locationName + "."
        : LocationService.detecting ? "Asking ipinfo.io …"
        : "The weather needs a place. Find it from this connection? That asks ipinfo.io once, which sees this computer's IP address. Or choose a city yourself."
    readonly property bool placeErrorShown: !WeatherService.hasLocation && !LocationService.detecting
        && LocationService.detectError.length > 0 && locating
    onPlaceErrorShownChanged: Qt.callLater(measureSteps)
    // Found or chosen during this tour: the step says so rather than going
    // quiet.
    property bool placeFound: false
    Connections {
        target: WeatherService
        function onHasLocationChanged() {
            if (WeatherService.hasLocation && (root.wanted || root.steppingAside)) root.placeFound = true
            Qt.callLater(root.measureSteps)
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
        id: stepColumn
        width: parent.width
        spacing: Metrics.panelGap
        // A step fades in while the card's height glides (ShellPanel),
        // instead of Next jumping up to 59 px in one frame.
        PageFade { target: stepColumn; key: root.step; live: root.openProgress === 1 }

        PanelHeader {
            Layout.fillWidth: true
            icon: root.current.icon
            title: root.current.title
            subtitle: "Step " + (root.step + 1) + " of " + root.steps.length
        }

        CardSection {
            id: section
            Layout.fillWidth: true

            ShellText {
                id: stepText
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(implicitHeight, root.asksPlace ? root.bodyHeight - root.placeHeight
                    : root.spareHeight > 0 ? root.textHeight : root.bodyHeight)
                text: root.current.text
                wrapMode: Text.Wrap
            }
            // Every step's words, measured at the same width and never shown.
            // The width is the card's, not the words' own: theirs is set by
            // the layout these heights feed, and read from there it is a loop.
            Item {
                visible: false
                Repeater {
                    id: measure
                    model: root.steps
                    ShellText {
                        required property var modelData
                        width: section.width - section.padding * 2
                        text: modelData.text
                        wrapMode: Text.Wrap
                        onImplicitHeightChanged: Qt.callLater(root.measureSteps)
                    }
                }
                // And the place question's lines at that width, on every
                // step (the shown ones lay out only on their own).
                ShellText {
                    id: placeMeasure
                    width: section.width - section.padding * 2
                    text: root.placeText
                    role: "small"
                    wrapMode: Text.Wrap
                    onImplicitHeightChanged: Qt.callLater(root.measureSteps)
                }
                ShellText {
                    id: placeErrorMeasure
                    width: section.width - section.padding * 2
                    text: root.placeErrorShown ? LocationService.detectError : ""
                    role: "small"
                    wrapMode: Text.Wrap
                    onImplicitHeightChanged: Qt.callLater(root.measureSteps)
                }
            }

            // The keys' row keeps its height on the step without keys, for the
            // same reason as the words above.
            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(tryButton.implicitHeight, chips.implicitHeight)
                RowLayout {
                    anchors.fill: parent
                    visible: root.current.keys.length > 0
                    spacing: Metrics.spaceSm
                    KeyChips { id: chips; keys: root.current.keys; accent: true }
                    ShellButton {
                        id: tryButton
                        focusOnTab: true
                        text: "Try it"
                        variant: "surface"
                        compact: true
                        onClicked: root.tryIt()
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            Item {
                Layout.fillWidth: true
                visible: root.spareHeight > 0
                implicitHeight: root.spareHeight
            }
            ShellText {
                Layout.fillWidth: true
                visible: root.asksPlace
                text: root.placeText
                role: "small"
                muted: true
                wrapMode: Text.Wrap
            }
            ShellText {
                Layout.fillWidth: true
                visible: root.asksPlace && root.placeErrorShown
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
                    id: findButton
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
            // Forward after the word, as the start menu's links have it; Done
            // keeps its check in front.
            ShellButton {
                id: nextButton
                icon: root.last ? Icons.check : ""
                trailingIcon: root.last ? "" : Icons.forward
                text: root.last ? "Done" : "Next"
                variant: "accent"
                focusOnTab: true
                onClicked: root.next()
            }
        }
    }
}
