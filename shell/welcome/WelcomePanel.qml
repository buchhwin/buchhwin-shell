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
            text: "This is buchhwin-shell. There is no menu bar and no dock: everything has a key, and every key opens the same thing every time.",
            keys: [], action: ""
        },
        {
            icon: Icons.search, title: "Find anything",
            text: "The launcher starts apps, opens settings pages, does arithmetic and searches the web. Type ? for the web, = to calculate, @ for a settings page.",
            keys: ["Super", "D"], action: "launcher"
        },
        {
            icon: "󰕾", title: "Turn things on and off",
            text: "Wi-Fi, Bluetooth, brightness, sound, battery. The pencil in its header arranges the tiles the way you want them.",
            keys: ["Super", "O"], action: "controlCenter"
        },
        {
            icon: "󰃭", title: "Time and weather",
            text: "The dashboard has the month, the week, the day and your KDE calendars. “+” creates an event, and a series can be changed one occurrence at a time.",
            keys: ["Super", "K"], action: "dashboard"
        },
        {
            icon: Icons.edit, title: "Make it yours",
            text: "The layout editor arranges the desktop: widgets on the wallpaper, a bar of pills at the top, or a notch. Drag what you see, where you see it.",
            keys: ["Super", "Alt", "E"], action: "editor"
        },
        {
            icon: "󰥻", title: "Everything else",
            text: "Super+F1 lists every shortcut, Super+I opens Settings. Nothing here is hidden behind a menu you have to find first.",
            keys: ["Super", "F1"], action: "shortcuts"
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
                    color: index === root.step ? Colors.accent : Colors.border
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
