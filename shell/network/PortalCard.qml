import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// The way to a captive portal's sign-in page (a hotel's, a train's, a guest
// network's), while NetworkManager finds one: the network popup and the
// control center's Wi-Fi page. The line beside the network already says
// "Sign-in required"; this is the click that leads there - the default
// browser at an address the portal answers in its place
// (NetworkService.openPortal). Nothing opens without the click.
//
// Short lines, for the 380 px popup where it is met first: what is needed,
// then the network's name - "Sign in to <network>" and "Opens its sign-in
// page in …" were cut off there. The button says the verb, and its tooltip
// where it leads.
CardSection {
    id: root
    visible: NetworkService.signInNeeded
    padding: Metrics.spaceSm

    ListRow {
        Layout.fillWidth: true
        level: 1
        icon: "󰖟"
        title: "Sign-in required"
        subtitle: NetworkService.portalName
        // The button is the control; the row only says what it is for.
        interactive: false
        ShellButton {
            focusOnTab: true
            compact: true
            variant: "accent"
            text: "Sign in"
            toolTip: "Opens the network's sign-in page in the browser"
            onClicked: NetworkService.openPortal()
        }
    }
}
