import QtQuick
import QtQuick.Effects
import qs.theme

// Album cover as a vinyl record: a black disc with grooves, the cover as the
// round centre label and a real spindle hole. It spins while music plays and
// stops where it is on pause.
Item {
    id: root
    property url source
    property bool spinning: false
    readonly property int status: image.status
    implicitWidth: Metrics.popupMediaCover
    implicitHeight: Metrics.popupMediaCover

    // Path of a disc with a centred hole (odd-even fill leaves the hole empty).
    function ring(ctx, centre, outer, inner) {
        ctx.fillRule = Qt.OddEvenFill
        ctx.beginPath()
        ctx.moveTo(centre + outer, centre)
        ctx.arc(centre, centre, outer, 0, Math.PI * 2)
        ctx.closePath()
        ctx.moveTo(centre + inner, centre)
        ctx.arc(centre, centre, inner, 0, Math.PI * 2)
        ctx.closePath()
    }

    Item {
        id: disc
        anchors.fill: parent

        // Vinyl with grooves; the spindle hole stays transparent.
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const r = width / 2
                ctx.fillStyle = Colors.vinyl
                root.ring(ctx, r, r, r * Effects.vinylHole)
                ctx.fill()
                ctx.lineWidth = 1
                for (let ring = r * (Effects.vinylLabel + 0.04); ring < r * 0.96; ring += r * 0.028) {
                    // style: the record is always near-black (Colors.vinyl), so its grooves and
            // sheen are white at a token strength rather than a theme colour.
            ctx.strokeStyle = Qt.rgba(1, 1, 1, Effects.vinylGrooves * (Effects.vinylGrooveBase + Effects.vinylGrooveSwing * Math.sin(ring))) // style: see above
                    ctx.beginPath()
                    ctx.arc(r, r, ring, 0, Math.PI * 2)
                    ctx.stroke()
                }
            }
        }

        // The cover as the label, with the hole cut out.
        Item {
            id: label
            anchors.centerIn: parent
            width: parent.width * Effects.vinylLabel
            height: width

            Image {
                id: image
                anchors.fill: parent
                source: root.source
                sourceSize.width: root.width * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            Canvas {
                id: labelShape
                anchors.fill: parent
                visible: false
                layer.enabled: true
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const r = width / 2
                    ctx.fillStyle = "white"
                    root.ring(ctx, r, r, root.width / 2 * Effects.vinylHole)
                    ctx.fill()
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: image
                visible: image.status === Image.Ready
                maskEnabled: true
                maskSource: labelShape
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }

        NumberAnimation on rotation {
            from: 0; to: 360
            duration: Animations.vinylTurn
            loops: Animation.Infinite
            // Only "Off" stops the record; Reduced keeps this slow, calm turn.
            running: Animations.enabled
            paused: running && !root.spinning
        }
    }

    // Light reflection that does not turn with the record.
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const r = width / 2
            const gradient = ctx.createLinearGradient(0, 0, width, height)
            gradient.addColorStop(0, Qt.rgba(1, 1, 1, Effects.vinylSheen)) // style: see the grooves above
            gradient.addColorStop(0.45, Qt.rgba(1, 1, 1, 0)) // style: fully transparent, not a colour
            gradient.addColorStop(0.55, Qt.rgba(1, 1, 1, 0)) // style: fully transparent, not a colour
            gradient.addColorStop(1, Qt.rgba(1, 1, 1, Effects.vinylSheen * Effects.vinylSheenLower)) // style: see the grooves above
            ctx.fillStyle = gradient
            root.ring(ctx, r, r, r * Effects.vinylHole)
            ctx.fill()
        }
    }
}
