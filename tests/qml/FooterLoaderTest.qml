import Quickshell
import QtQuick
import QtQuick.Layouts
import "Harness.js" as T

// Settings keeps a page's footer (Displays' Apply bar) in a Loader under the
// page's Flickable (SettingsPanel.qml). A Loader keeps the implicit height of
// the item it last held after the item is gone, so once Displays had been
// open every other page ended 64 px short of the panel over an empty band
// The pattern, laid out in an offscreen window (a layout
// places its children only there): the bare Loader keeps the room, the one
// that hides while empty gives it back.
ShellRoot {
    id: root

    Component { id: footer; Rectangle { implicitHeight: 64; implicitWidth: 100 } }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 400

        ColumnLayout {
            id: bare
            width: 180
            height: 400
            spacing: 0
            Flickable { id: bareFlick; Layout.fillWidth: true; Layout.fillHeight: true }
            Loader { id: bareFooter; Layout.fillWidth: true; sourceComponent: footer }
        }
        ColumnLayout {
            x: 200
            width: 180
            height: 400
            spacing: 0
            Flickable { id: flick; Layout.fillWidth: true; Layout.fillHeight: true }
            Loader { id: guarded; Layout.fillWidth: true; visible: item !== null; sourceComponent: footer }
        }
    }

    Timer {
        id: loaded
        interval: 100
        running: true
        onTriggered: {
            T.eq([bareFlick.height, flick.height], [336, 336], "with a footer both pages are shorter by it")
            bareFooter.sourceComponent = null
            guarded.sourceComponent = null
            unloaded.start()
        }
    }
    Timer {
        id: unloaded
        interval: 100
        onTriggered: {
            T.eq(bareFooter.item, null, "the footer is gone")
            T.ok(bareFlick.height < 400, "a bare Loader keeps the room it had (why Settings hides it): " + bareFlick.height)
            T.eq(flick.height, 400, "hidden while empty, the page has the whole height again")
            guarded.sourceComponent = footer
            again.start()
        }
    }
    Timer {
        id: again
        interval: 100
        onTriggered: {
            T.eq(flick.height, 336, "and a footer that comes back takes its room again")
            T.finish("FooterLoaderTest")
        }
    }
}
