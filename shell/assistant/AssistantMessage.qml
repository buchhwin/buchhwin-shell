import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/assistant/AssistantLogic.js" as Logic

// One message of the assistant's conversation: a question on the right in
// the accent's soft tint, an answer across the panel on a card, its code
// in the mono font with a copy button of its own. The text can be selected
// and copied with the keyboard; it is plain text, never markup (a model's
// answer is someone else's string - testing.md "plaintext").
Item {
    id: root
    property string role: "assistant"
    property string content: ""
    // The model that answered, for the line under an answer.
    property string answeredBy: ""
    property bool stopped: false
    // The reply being written: no copy buttons yet, a cursor-like note.
    property bool streaming: false
    readonly property bool asked: role === "user"
    readonly property var pieces: Logic.segments(content)
    readonly property real bubbleWidth: asked ? Math.min(width * 0.85, Math.ceil(questionText.advanceWidth) + Metrics.spaceMd * 2 + Metrics.spaceXs) : width

    implicitHeight: bubble.height + (footer.visible ? footer.implicitHeight + Metrics.spaceXs : 0)

    // A question is one piece of plain text and sizes the bubble to itself.
    TextMetrics {
        id: questionText
        font.family: Typography.family
        font.pixelSize: Typography.bodySize
        text: root.asked ? root.content.split("\n").reduce((longest, line) => line.length > longest.length ? line : longest, "") : ""
    }

    Rectangle {
        id: bubble
        anchors.right: root.asked ? parent.right : undefined
        anchors.left: root.asked ? undefined : parent.left
        width: root.bubbleWidth
        height: column.implicitHeight + Metrics.spaceMd * 2
        radius: Metrics.radiusCard
        color: root.asked ? Colors.accentSoft : Colors.surface1
        border.width: root.asked ? 0 : Metrics.borderWidth
        border.color: Colors.border

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Metrics.spaceMd
            spacing: Metrics.spaceSm

            Repeater {
                // By place and kind, so a piece that grows while the answer is
                // written keeps its row (AssistantLogic.segmentKeys).
                model: ScriptModel { values: Logic.segmentKeys(root.pieces) }
                Loader {
                    id: piece
                    required property string modelData
                    readonly property var segment: root.pieces[Number(modelData.split(":")[0])] || null
                    Layout.fillWidth: true
                    sourceComponent: segment && segment.kind === "code" ? codePiece : textPiece
                    Component {
                        id: textPiece
                        TextEdit {
                            text: piece.segment ? piece.segment.text : ""
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            color: Colors.text
                            selectionColor: Colors.accentSoft
                            selectedTextColor: Colors.text
                            font.family: Typography.family
                            font.pixelSize: Typography.bodySize
                            renderType: Typography.renderType
                        }
                    }
                    Component {
                        id: codePiece
                        Rectangle {
                            implicitHeight: code.implicitHeight + Metrics.spaceSm * 2
                            radius: Metrics.radiusInner
                            color: Colors.sunken
                            border.width: Metrics.borderWidth
                            border.color: Colors.borderInner
                            TextEdit {
                                id: code
                                anchors.left: parent.left
                                anchors.right: copyCode.visible ? copyCode.left : parent.right
                                anchors.top: parent.top
                                anchors.margins: Metrics.spaceSm
                                text: piece.segment ? piece.segment.text : ""
                                textFormat: TextEdit.PlainText
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                color: Colors.text
                                selectionColor: Colors.accentSoft
                                selectedTextColor: Colors.text
                                font.family: Typography.monoFamily
                                font.pixelSize: Typography.smallSize
                                renderType: Typography.renderType
                            }
                            ShellButton {
                                id: copyCode
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: Metrics.spaceXs
                                visible: !root.streaming && piece.segment && piece.segment.text.length > 0
                                focusOnTab: true
                                icon: Icons.copy
                                compact: true
                                variant: "ghost"
                                toolTip: "Copy the code"
                                onClicked: AssistantService.copy(piece.segment.text)
                            }
                        }
                    }
                }
            }

            ShellText {
                visible: root.pieces.length === 0
                text: root.streaming ? "…" : root.stopped ? "Stopped before it said anything" : ""
                muted: true
            }
        }
    }

    RowLayout {
        id: footer
        anchors.top: bubble.bottom
        anchors.topMargin: Metrics.spaceXs
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !root.asked && !root.streaming
        spacing: Metrics.spaceXs

        ShellText {
            Layout.fillWidth: true
            text: root.answeredBy.replace(/:latest$/, "") + (root.stopped ? " · stopped" : "")
            role: "caption"
        }
        ShellButton {
            visible: root.content.length > 0
            focusOnTab: true
            icon: Icons.copy
            text: "Copy"
            compact: true
            variant: "ghost"
            onClicked: AssistantService.copy(root.content)
        }
    }
}
