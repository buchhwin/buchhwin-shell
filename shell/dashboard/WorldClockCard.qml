import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dashboard/WorldClockLogic.js" as Logic
import "../../services/arrange/FitLogic.js" as Fit
import "../../services/appearance/TimeFormat.js" as TimeFormat

// The dashboard's world clock: a few places, the time there and how far
// ahead or behind it is - a colleague's time without opening an app. The
// places are the user's (Settings keeps them as desktop.worldClocks); the
// pencil in the card's corner adds and removes them, searching the tz
// database's own list of places. WorldClockLogic has how the times are made.
//
// Nothing here runs while the dashboard is closed: the offsets are asked as
// it opens and on the quarter hours while it is open, from the dashboard's own
// minute clock, and the list of places is read only while choosing one.
CardSection {
    id: root
    // The dashboard's minute clock, and whether the dashboard is open.
    property date now: new Date()
    property bool active: false
    // The cell's shape: a one-step cell has room for the times alone.
    property string fitClass: "small"
    // The cell's height, from the item that fills it - not this card's own,
    // which grows with the places it shows (a binding loop through roomFor).
    property real cellHeight: 0

    readonly property var zones: Logic.parseZones(SettingsService.value("desktop.worldClocks"))
    readonly property string zoneDir: Quickshell.env("TZDIR") || Logic.ZONE_DIR
    property var offsets: ({})
    readonly property int localOffset: -now.getTimezoneOffset()
    property bool editing: false
    // How many places the cell has room for, counted the way the events card
    // counts its rows - from a place row's real height (`rowHeight`, which
    // the rows report; the sum of the font sizes before it is drawn), and
    // with room for the line that says how many more there are when not all
    // of them fit. The two heights are handed over by handlers, not read in
    // this binding: a Text's height read here would be a loop (testing.md
    // pitfall 138).
    property real rowHeight: Typography.titleSize + Typography.smallSize + Metrics.spaceXs
    property real moreHeight: Typography.smallSize + Metrics.spaceXs
    readonly property real placeRoom: cellHeight - padding * 2 - header.implicitHeight - spacing
    readonly property int roomFor: {
        const all = Fit.rowsFor(placeRoom, rowHeight, spacing)
        return zones.length > all ? Fit.rowsFor(placeRoom - moreHeight - spacing, rowHeight, spacing) : all
    }
    readonly property int hiddenPlaces: editing ? 0 : Math.max(0, zones.length - roomFor)

    padding: Metrics.spaceLg

    function store(list) {
        SettingsService.set("desktop.worldClocks", Logic.storeZones(list))
    }
    function add(zone) {
        const list = Logic.withZone(zones, zone)
        if (list) store(list)
        search.text = ""
    }

    // ---- the offsets: one `date` run for every place ----------------------
    function askOffsets() {
        if (!active || !zones.length) return
        if (offsetsRun.running) { offsetsRun.again = true; return }
        offsetsRun.command = Logic.offsetsCommand(zones, zoneDir)
        offsetsRun.running = true
    }
    onActiveChanged: {
        if (active) askOffsets()
        else editing = false
    }
    onZonesChanged: askOffsets()
    onNowChanged: if (Logic.offsetsDue(now)) askOffsets()
    Component.onCompleted: askOffsets()

    Process {
        id: offsetsRun
        property bool again: false
        stderr: ErrorLog { label: "WorldClockCard.offsets" }
        stdout: StdioCollector { onStreamFinished: root.offsets = Logic.parseOffsets(text) }
        onExited: if (again) { again = false; Qt.callLater(root.askOffsets) }
    }

    // ---- the places to choose from: read only while choosing --------------
    FileView {
        id: zoneTab
        path: root.editing ? root.zoneDir + "/zone.tab" : ""
        printErrors: false
    }
    FileView {
        id: countryTab
        path: root.editing ? root.zoneDir + "/iso3166.tab" : ""
        printErrors: false
    }
    readonly property var zoneTable: editing && zoneTab.loaded ? Logic.parseZoneTab(zoneTab.text()) : []
    readonly property var countryNames: editing && countryTab.loaded ? Logic.parseCountries(countryTab.text()) : ({})
    readonly property var suggestions: editing && zones.length < Logic.LIMIT
        ? Logic.search(zoneTable, countryNames, search.text, zones, 5) : []

    RowLayout {
        id: header
        Layout.fillWidth: true
        visible: root.fitClass !== "icon" || root.editing
        spacing: Metrics.spaceSm
        ShellText { Layout.fillWidth: true; text: "World clock"; role: "title"; elide: Text.ElideRight }
        ShellButton {
            icon: root.editing ? Icons.check : Icons.modify
            variant: root.editing ? "accent" : "ghost"
            compact: true
            toolTip: root.editing ? "Done" : "Change places"
            onClicked: {
                root.editing = !root.editing
                search.text = ""
            }
        }
    }
    // The pencil opens the search with the keys in it, as a search does
    // wherever it opens: typing went nowhere until a click into the field.
    onEditingChanged: if (editing) Qt.callLater(() => { if (root.editing && search.visible) search.forceActiveFocus() })

    // The places and their time.
    Repeater {
        model: root.editing ? [] : root.zones
        RowLayout {
            id: place
            required property string modelData
            required property int index
            readonly property var offset: root.offsets[modelData]
            // One binding for both: read through a second property, the text
            // below could see the offset arrive before the clock made of it.
            readonly property var clock: offset !== undefined && offset !== null
                ? Logic.wallClock(root.now.getTime(), offset, root.localOffset) : null
            Layout.fillWidth: true
            visible: index < root.roomFor
            spacing: Metrics.spaceSm
            onImplicitHeightChanged: if (implicitHeight > 0) root.rowHeight = implicitHeight
            Component.onCompleted: if (implicitHeight > 0) root.rowHeight = implicitHeight
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { Layout.fillWidth: true; text: Logic.cityOf(place.modelData); elide: Text.ElideRight }
                ShellText {
                    Layout.fillWidth: true
                    visible: root.fitClass !== "icon"
                    // An offset `date` could not give is a place the zone
                    // database here does not know (any more).
                    text: place.offset === null ? "Unknown place"
                        : place.clock ? [Logic.difference(place.offset, root.localOffset), Logic.dayNote(place.clock.dayShift)]
                                            .filter(part => part.length).join(" · ")
                        : ""
                    role: "small"
                    muted: true
                    elide: Text.ElideRight
                }
            }
            ShellText {
                text: place.clock ? TimeFormat.time(place.clock.date, SettingsService.twelveHourClock, ":") : "–"
                role: "title"
                font.features: { "tnum": 1 }
            }
        }
    }

    // Last, as under the events: the places that did not fit are said, so a
    // short list does not look like all of them.
    ShellText {
        Layout.fillWidth: true
        visible: root.hiddenPlaces > 0
        text: root.hiddenPlaces === 1 ? "1 more place" : root.hiddenPlaces + " more places"
        role: "small"
        muted: true
        elide: Text.ElideRight
        onImplicitHeightChanged: if (implicitHeight > 0) root.moreHeight = implicitHeight
        Component.onCompleted: if (implicitHeight > 0) root.moreHeight = implicitHeight
    }

    EmptyState {
        Layout.fillWidth: true
        visible: !root.editing && root.zones.length === 0
        row: root.fitClass === "icon" || root.fitClass === "small" || root.fitClass === "wide"
        icon: "\u{f01e7}"
        title: "No places yet"
        description: row ? "" : "Add the places of the people you work with"
        ShellButton {
            icon: Icons.add
            text: "Add a place"
            compact: true
            onClicked: root.editing = true
        }
    }

    // Choosing: a search for a place first, what it finds under it, then the
    // places with a remove each. All of it scrolls inside the cell, which
    // stays the size it was given - three rows hold the field and two finds.
    // Inset by the focus ring, which the list's clip cut off on three sides.
    ScrollList {
        Layout.fillWidth: true
        visible: root.editing
        card: false
        padding: Metrics.focusRingWidth + Metrics.focusRingGap
        maxHeight: Math.max(Metrics.controlHeight, root.cellHeight - root.padding * 2 - header.implicitHeight - root.spacing)

        ShellTextField {
            id: search
            width: parent.width
            visible: root.zones.length < Logic.LIMIT
            icon: Icons.search
            placeholder: "City or country …"
            // Return takes the first place the search offers.
            onAccepted: if (root.suggestions.length) root.add(root.suggestions[0].zone)
        }
        ShellText {
            width: parent.width
            visible: root.zones.length >= Logic.LIMIT
            text: "At most " + Logic.LIMIT + " places"
            role: "small"
            muted: true
        }
        Repeater {
            model: root.suggestions
            ListRow {
                required property var modelData
                width: parent.width
                compact: true
                icon: Icons.add
                title: modelData.label
                subtitle: modelData.detail
                onClicked: root.add(modelData.zone)
            }
        }
        Repeater {
            model: root.editing ? root.zones : []
            ListRow {
                required property string modelData
                width: parent.width
                compact: true
                interactive: false
                title: Logic.cityOf(modelData)
                subtitle: modelData
                ShellButton {
                    icon: Icons.remove
                    variant: "ghost"
                    compact: true
                    toolTip: "Remove"
                    onClicked: root.store(Logic.withoutZone(root.zones, modelData))
                }
            }
        }
    }
}
