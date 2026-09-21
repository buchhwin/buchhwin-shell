import QtQuick
import qs.theme

// A card on a panel. `level` picks its step on the depth ladder: 1 sits on a
// panel, 2 sits inside another card. Interactive cards (tiles, chips) take the
// One UI press feedback: a step darker and a small dip.
Rectangle {
    id: root
    property bool interactive: false
    property bool hovered: false
    property bool pressed: false
    property bool highlighted: false
    // 1 = on a panel, 2 = inside a card.
    property int level: 1

    readonly property color baseColor: level >= 2 ? Colors.surface2 : Colors.surface1
    readonly property color hoverColor: level >= 2 ? Colors.surface2Hover : Colors.surface1Hover
    readonly property color pressedColor: level >= 2 ? Colors.surface2Pressed : Colors.surface1Pressed

    radius: Metrics.radiusCard
    color: highlighted ? Colors.accentSoft
        : interactive && pressed ? pressedColor
        : interactive && hovered ? hoverColor : baseColor
    border.width: Metrics.borderWidth
    border.color: highlighted ? Colors.accentBorder
        : level >= 2 ? Colors.borderInner : Colors.border
    scale: interactive && pressed ? Effects.pressScaleWide : 1

    Behavior on color { ColorAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    Behavior on scale { NumberAnimation { duration: Animations.move(Animations.press); easing.type: Animations.easing } }
}
