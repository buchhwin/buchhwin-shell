import Quickshell
import QtQuick
import "Harness.js" as T
import "../../shell/editor/SnapEngine.js" as Snap

ShellRoot {
    Component.onCompleted: {
        const opts = { screenWidth: 1000, screenHeight: 600, threshold: 10, grid: false, gridSize: 24, margin: 16 }
        let result = Snap.snap({ x: 8, y: 300, width: 100, height: 40 }, [], opts)
        T.eq(result.x, 16, "snaps left edge to screen margin")
        T.eq(result.guides[0], { orientation: "vertical", position: 16 }, "vertical guide")

        result = Snap.snap({ x: 446, y: 100, width: 100, height: 40 }, [], opts)
        T.eq(result.x, 450, "snaps centre to screen centre")

        result = Snap.snap({ x: 205, y: 97, width: 50, height: 60 }, [{ x: 100, y: 100, width: 100, height: 30 }], opts)
        T.eq([result.x, result.y], [200, 100], "snaps to another widget's right and top edges")

        result = Snap.snap({ x: 290, y: 150, width: 50, height: 20 }, [], Object.assign({}, opts, { grid: true }))
        T.eq([result.x, result.y], [288, 144], "grid snapping when no guide is near")

        result = Snap.snap({ x: 8, y: 3, width: 100, height: 40 }, [], Object.assign({}, opts, { disabled: true }))
        T.eq([result.x, result.y, result.guides.length], [8, 3, 0], "Alt disables snapping")

        result = Snap.snap({ x: 990, y: 590, width: 100, height: 40 }, [], Object.assign({}, opts, { threshold: 0 }))
        T.eq([result.x, result.y], [900, 560], "stays on screen")

        T.finish("SnapTest")
    }
}
