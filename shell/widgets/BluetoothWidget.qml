import QtQuick
import qs.shell.widgets
import qs.services
WidgetBase {
    icon: BluetoothService.icon
    label: inGroup ? (BluetoothService.connected.length > 1 ? String(BluetoothService.connected.length) : "") : BluetoothService.summary
    maxLabelWidth: 160
    name: "Bluetooth"
    // What is actually connected, which the summary has no room for.
    detail: BluetoothService.connected.length ? BluetoothService.connected.map(d => d.name).join(", ") : ""
}
