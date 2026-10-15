import Quickshell
import QtQuick
import qs.shell.components
import "Harness.js" as T

// A tile whose device is missing is dimmed, and dimmed means it does nothing:
// no click, no key, no hover that promises a click.
ShellRoot {
    id: root
    property int fired: 0

    Item {
        width: 400
        height: 200
        QuickTile {
            id: tile
            width: 200
            title: "Wi-Fi"
            showChevron: true
            available: false
            onToggled: root.fired += 1
            onActivated: root.fired += 1
            onDetailsRequested: root.fired += 1
        }
    }

    Component.onCompleted: {
        const area = tile.children.find(child => child instanceof MouseArea)
        T.ok(area !== undefined, "the tile has its mouse area")
        T.eq(area.enabled, false, "a dimmed tile takes no click and shows no hover")
        T.eq([tile.hovered, tile.pressed], [false, false], "and draws neither")

        // The keys a focused tile answers: none of them may reach the signals.
        tile.Keys.spacePressed(null)
        tile.Keys.returnPressed(null)
        tile.Keys.enterPressed(null)
        T.eq(root.fired, 0, "nor a key")

        tile.available = true
        T.eq(area.enabled, true, "with the device back it answers the mouse")
        tile.Keys.spacePressed(null)
        tile.Keys.returnPressed(null)
        T.eq(root.fired, 2, "and the keys")

        T.finish("QuickTileTest")
    }
}
