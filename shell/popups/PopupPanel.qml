import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.theme
import qs.services
import qs.shell.components

// Small panel for one topic, opened from a pill or desktop widget and
// centred below it (anchorX). Header with icon, heading, status and an
// optional switch; the body loads only while the panel is shown, so scans,
// discovery and sampling stop when it closes; optional footer link.
ShellPanel {
    id: root
    property string heading: ""
    property string detail: ""
    property string glyph: ""
    property bool glyphActive: false
    property bool hasToggle: false
    property bool toggleChecked: false
    property bool toggleEnabled: true
    property string footerText: ""
    property string footerGlyph: Icons.settings
    property Component body: null
    signal toggled(bool checked)
    signal footerClicked()

    // Optional image drawn blurred and faint behind the whole card (media cover).
    property string backdropSource: ""

    placement: "top-right"
    cardWidth: Metrics.popupWidth

    // Below the card body (ShellPanel gives it z 1), masked to the card corners.
    Item {
        parent: root.card
        anchors.fill: parent
        visible: root.shown && root.backdropSource.length > 0 && backdropImage.status === Image.Ready
        opacity: Effects.mediaBackdropOpacity

        Image {
            id: backdropImage
            anchors.fill: parent
            source: root.shown ? root.backdropSource : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 256
            asynchronous: true
            visible: false
            layer.enabled: true
        }
        Rectangle {
            id: backdropMask
            anchors.fill: parent
            radius: root.card.radius
            visible: false
            layer.enabled: true
            layer.smooth: true
        }
        MultiEffect {
            anchors.fill: parent
            source: backdropImage
            blurEnabled: true
            blur: 1
            blurMax: Effects.mediaBackdropBlur
            // Padding would stretch the mask beyond the card corners.
            autoPaddingEnabled: false
            saturation: 0.2
            maskEnabled: true
            maskSource: backdropMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Metrics.panelGap

        PopupHeader {
            Layout.fillWidth: true
            visible: root.heading.length > 0
            heading: root.heading
            detail: root.detail
            glyph: root.glyph
            active: root.glyphActive
            hasToggle: root.hasToggle
            checked: root.toggleChecked
            toggleEnabled: root.toggleEnabled
            onToggled: checked => root.toggled(checked)
        }

        Loader {
            Layout.fillWidth: true
            active: root.shown && root.body !== null
            visible: status === Loader.Ready
            sourceComponent: root.body
        }

        PopupFooterLink {
            Layout.fillWidth: true
            visible: root.footerText.length > 0
            text: root.footerText
            glyph: root.footerGlyph
            onClicked: root.footerClicked()
        }
    }
}
