import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/power/StayAwakeLogic.js" as StayAwakeLogic

// Stay awake's choices on the control center's Power page, listed the way
// the Do Not Disturb page lists its own: the running one selected, an hour
// with what is left of it beneath. "Until unplugged" is there while a
// charger is in to unplug. A choice made here is the one the quick
// switches (the battery popup's, the control center's tile) start next time.
CardSection {
    title: "Stay awake"
    padding: Metrics.spaceXs
    spacing: Metrics.spaceXxs

    Repeater {
        model: StayAwakeLogic.MODES.filter(mode => mode === IdleService.stayAwakeMode || IdleService.stayAwakeOffered(mode))
        ListRow {
            required property string modelData
            Layout.fillWidth: true
            level: 1
            icon: modelData === "1h" ? Icons.busy
                : modelData === "unplug" ? "󰚦"
                : modelData === "manual" ? IdleService.stayAwakeIcon
                : "󰾪"
            selected: IdleService.stayAwakeMode === modelData
            title: StayAwakeLogic.title(modelData)
            subtitle: selected && modelData === "1h" ? IdleService.stayAwakeSubtitle : ""
            onClicked: IdleService.chooseStayAwake(modelData)
        }
    }
}
