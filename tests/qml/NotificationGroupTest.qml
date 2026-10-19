import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/NotificationLogic.js" as N

// The centre's grouping, and the way its list is built from it: keyed by the
// group keys (strings, compared by value) with the notification objects as
// the cards' model, the same delegates are kept across arrivals and across
// Clear all - the list as it was rebuilt every group and every card for each
// notification that came or went (1890 cards for a Clear all of 100).
ShellRoot {
    id: root
    property var history: []
    property bool clearing: false
    property var expanded: ({})
    readonly property var matching: clearing ? [] : N.search(history, "")
    readonly property var groups: N.group(matching)
    readonly property var groupKeys: groups.map(entry => entry.key)
    readonly property var groupIndex: N.groupIndex(groups)
    property int groupsBuilt: 0
    property int cardsBuilt: 0
    // How often each notification was given a card, since the last reset.
    property var builtFor: ({})

    // Stand-ins for the server's notification objects: QObjects, which the
    // model tells apart by identity as it does the real ones.
    Component {
        id: fake
        QtObject {
            property int id: 0
            property string appName: ""
            property string appIcon: ""
            property string summary: ""
            property string body: ""
        }
    }

    Item {
        Repeater {
            id: groupList
            model: ScriptModel { values: root.groupKeys }
            Item {
                id: groupItem
                required property string modelData
                readonly property var group: root.groupIndex[modelData] || ({ key: modelData, name: "", icon: "", items: [] })
                readonly property var shown: N.visibleItems(group, root.expanded[modelData] === true)
                readonly property alias cards: cardList
                Component.onCompleted: root.groupsBuilt += 1
                Repeater {
                    id: cardList
                    model: ScriptModel { values: groupItem.shown }
                    Item {
                        required property var modelData
                        property int born: -1
                        Component.onCompleted: {
                            born = modelData.id
                            root.cardsBuilt += 1
                            root.builtFor[modelData.id] = (root.builtFor[modelData.id] || 0) + 1
                        }
                    }
                }
            }
        }
    }

    function make(id, app) {
        return fake.createObject(root, { id: id, appName: "App" + app, summary: String(id) })
    }
    // Every card on screen, by the id of the notification it shows.
    function cardsById() {
        const table = {}
        for (let g = 0; g < groupList.count; ++g) {
            const cards = groupList.itemAt(g).cards
            for (let c = 0; c < cards.count; ++c) table[cards.itemAt(c).modelData.id] = cards.itemAt(c)
        }
        return table
    }
    function wrongCards() {
        const table = cardsById()
        return Object.keys(table).filter(id => table[id].born !== Number(id))
    }

    Component.onCompleted: {
        const history = [
            { appName: "Brave", appIcon: "brave", summary: "1" },
            { appName: "Kitty", appIcon: "", summary: "2" },
            { appName: "brave", appIcon: "", summary: "3" },
            { appName: "", appIcon: "", summary: "4" },
            { appName: "Brave", appIcon: "", summary: "5" },
            { appName: "Brave", appIcon: "", summary: "6" },
            null
        ]
        const groups = N.group(history)
        T.eq(groups.map(g => g.name), ["Brave", "System", "Kitty"], "groups ordered by newest notification, case-insensitive app names")
        T.eq(groups[0].items.map(n => n.summary), ["6", "5", "3", "1"], "newest first inside a group")
        T.eq(groups[0].icon, "brave", "first known icon kept")
        T.eq(N.visibleItems(groups[0], false).map(n => n.summary), ["6", "5"], "collapsed group shows two")
        T.eq(N.visibleItems(groups[0], true).length, 4, "expanded group shows all")
        T.eq(N.visibleItems({ items: [1, 2, 3] }, false).length, 3, "three are shown without collapsing")
        T.eq(N.visibleItems(undefined, false), [], "a group that has just gone shows nothing and does not throw")
        T.eq(N.group([]).length, 0, "empty history")

        const index = N.groupIndex(groups)
        T.eq(Object.keys(index), ["brave", "__system", "kitty"], "every group by its key")
        T.ok(index.brave === groups[0], "the very group, not a copy")
        T.eq(N.groupIndex(null), {}, "no groups at all")

        // The bell over a group: Normal and Muted, and an always-urgent app
        // back to normal - never on to "Always urgent", which made un-muting
        // an app break through Do Not Disturb.
        T.eq([N.nextAppRule("default"), N.nextAppRule("mute"), N.nextAppRule("critical"), N.nextAppRule(undefined)],
             ["mute", "default", "default", "mute"], "the bell toggles between normal and muted")

        // Settings' list of apps: the ones with a rule, history or not, and
        // the ones in the history.
        const rows = N.ruleRows({ signal: "mute", thunderbird: "critical", stale: "nonsense" },
                                [{ appName: "Brave" }, { appName: "Signal" }, { appName: "" }, { appName: "brave" }])
        T.eq(rows.map(row => [row.key, row.name, row.rule]),
             [["brave", "Brave", "default"], ["signal", "Signal", "mute"], ["__system", "System", "default"],
              ["thunderbird", "Thunderbird", "critical"]],
             "rules and history apps, by name, the history's spelling first")
        T.eq(N.ruleRows({ __system: "mute" }, []).map(row => row.name), ["System"], "the system's rule without a notification")
        T.eq(N.ruleRows(null, null), [], "nothing at all")

        // The list itself. A hundred notifications of ten apps.
        const list = []
        for (let id = 1; id <= 100; ++id) list.push(make(id, (id - 1) % 10))
        root.history = list
        T.eq([groupList.count, root.groupsBuilt, root.cardsBuilt], [10, 10, 20], "ten groups of two cards each")
        const before = cardsById()

        // One more for App4: its group moves to the top, nothing is rebuilt
        // but the one new card.
        root.history = root.history.concat([make(101, 4)])
        T.eq([root.groupsBuilt, root.cardsBuilt], [10, 21], "an arrival builds its own card and nothing else")
        const after = cardsById()
        T.eq(Object.keys(before).filter(id => id !== "85" && after[id] !== before[id]), [],
             "every other card is the same card")
        T.eq(wrongCards(), [], "and shows the notification it was made for")

        // Dismissed one by one, newest first, as Clear all used to: each
        // notification is given a card once at most (the one coming into
        // view as the one above it goes), and no group is built again.
        root.builtFor = {}
        const cardsBefore = root.cardsBuilt
        for (let left = root.history.length - 1; left >= 0; --left) root.history = root.history.slice(0, left)
        T.eq(groupList.count, 0, "all gone")
        T.eq(root.groupsBuilt, 10, "dismissing a hundred builds no group again")
        T.eq(Object.keys(root.builtFor).filter(id => root.builtFor[id] > 1), [], "and no card twice")
        // The 80 that never had a card, and the one the arrival pushed out
        // of view, which comes back into it.
        T.eq(root.cardsBuilt - cardsBefore, 81, "only the ones that came into view")

        // Clear all now: the list is emptied once and the dismissals after it
        // build nothing at all.
        const again = []
        for (let id = 201; id <= 300; ++id) again.push(make(id, (id - 1) % 10))
        root.history = again
        const built = root.cardsBuilt
        root.clearing = true
        T.eq(groupList.count, 0, "clearing empties the list at once")
        for (let left = root.history.length - 1; left >= 0; --left) root.history = root.history.slice(0, left)
        root.clearing = false
        T.eq([groupList.count, root.cardsBuilt - built], [0, 0], "and no card is built while the history goes")
        T.finish("NotificationGroupTest")
    }
}
